package com.snowdrop.app.service

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.snowdrop.app.R
import com.snowdrop.app.SnowdropApplication
import com.snowdrop.app.domain.ApprovalDecision
import com.snowdrop.app.domain.ApprovalRequest
import com.snowdrop.app.domain.TransferDirection
import com.snowdrop.app.domain.TransferItem
import com.snowdrop.app.ui.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class TransferActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext as? SnowdropApplication ?: return
        val transferId = intent.getStringExtra(TransferService.EXTRA_TRANSFER_ID).orEmpty()
        if (transferId.isNotEmpty()) {
            TransferService.cancelApprovalNotification(context, transferId)
        }

        when (intent.action) {
            TransferService.ACTION_APPROVAL_ACCEPT ->
                app.store.resolveApproval(transferId, ApprovalDecision.ACCEPT)
            TransferService.ACTION_APPROVAL_TRUST ->
                app.store.resolveApproval(transferId, ApprovalDecision.ALWAYS_TRUST)
            TransferService.ACTION_APPROVAL_DECLINE ->
                app.store.resolveApproval(transferId, ApprovalDecision.DECLINE)
            TransferService.ACTION_CANCEL ->
                if (transferId.isNotEmpty()) app.store.cancelTransfer(transferId)
        }
    }
}

class TransferService : Service() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var observeJob: Job? = null
    private val postedTransferIds = mutableMapOf<String, Int>()
    private val notificationManager by lazy {
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                observeJob?.cancel()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_CANCEL -> {
                val transferId = intent.getStringExtra(EXTRA_TRANSFER_ID).orEmpty()
                if (transferId.isNotEmpty()) {
                    (application as? SnowdropApplication)?.store?.cancelTransfer(transferId)
                }
            }
        }

        createNotificationChannels(this)
        val idle = buildIdleNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, idle, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, idle)
        }
        observeActiveTransfers()
        return START_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        observeJob?.cancel()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        observeJob?.cancel()
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun observeActiveTransfers() {
        if (observeJob?.isActive == true) return
        val app = application as? SnowdropApplication ?: return
        observeJob = serviceScope.launch {
            app.store.uiState
                .map { it.activeTransfers }
                .distinctUntilChanged()
                .collectLatest { transfers ->
                    val currentIds = transfers.mapTo(HashSet()) { it.id }
                    val stale = postedTransferIds.keys.filter { it !in currentIds }
                    for (id in stale) {
                        postedTransferIds.remove(id)?.let { notifId ->
                            notificationManager.cancel(notifId)
                        }
                    }

                    if (!canPostNotifications(this@TransferService)) return@collectLatest
                    for (transfer in transfers) {
                        val notifId = postedTransferIds.getOrPut(transfer.id) {
                            transferNotificationId(transfer.id)
                        }
                        notificationManager.notify(notifId, buildTransferNotification(transfer))
                    }
                }
        }
    }

    private fun buildIdleNotification(): Notification {
        val pendingOpen = pendingMainIntent(this, requestCode = 0)
        val stopIntent = Intent(this, TransferService::class.java).apply { action = ACTION_STOP }
        val pendingStop = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_SERVICE_ID)
            .setContentTitle("Snowdrop")
            .setContentText("Ready to receive files in background")
            .setSmallIcon(R.drawable.ic_snowdrop_notification)
            .setLargeIcon(decodeLargeIcon(this))
            .setContentIntent(pendingOpen)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(0, "Stop", pendingStop)
            .build()
    }

    private fun buildTransferNotification(transfer: TransferItem): Notification {
        val pct = (transfer.progress * 100).toInt()
        val isIncoming = transfer.direction == TransferDirection.INCOMING
        val title = when {
            transfer.isBatch && isIncoming -> "Receiving files"
            transfer.isBatch -> "Sending files"
            isIncoming -> "Receiving file"
            else -> "Sending file"
        }
        val body = when {
            transfer.isBatch -> "File ${transfer.fileIndex} of ${transfer.totalFiles} ($pct%)"
            isIncoming -> "${transfer.fileName} ($pct%)"
            else -> "${transfer.fileName} to ${transfer.peerName} ($pct%)"
        }

        val cancelIntent = Intent(this, TransferActionReceiver::class.java).apply {
            action = ACTION_CANCEL
            putExtra(EXTRA_TRANSFER_ID, transfer.id)
        }
        val cancelReqCode = (transfer.id.hashCode() and 0xFFFF) + 20_000
        val pendingCancel = PendingIntent.getBroadcast(
            this,
            cancelReqCode,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_TRANSFER_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSubText("$pct%")
            .setSmallIcon(R.drawable.ic_snowdrop_notification)
            .setLargeIcon(decodeLargeIcon(this))
            .setContentIntent(pendingMainIntent(this, requestCode = 0))
            .setProgress(100, pct, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .addAction(0, "Cancel", pendingCancel)
            .build()
    }

    companion object {
        const val CHANNEL_SERVICE_ID = "snowdrop_service_channel"
        const val CHANNEL_TRANSFER_ID = "snowdrop_transfer_channel_v2"
        const val CHANNEL_RECEIVED_ID = "snowdrop_received_channel"
        const val NOTIFICATION_ID = 42445

        const val ACTION_CANCEL = "com.snowdrop.app.action.CANCEL"
        const val ACTION_STOP = "com.snowdrop.app.action.STOP"
        const val ACTION_APPROVAL_ACCEPT = "com.snowdrop.app.action.APPROVAL_ACCEPT"
        const val ACTION_APPROVAL_TRUST = "com.snowdrop.app.action.APPROVAL_TRUST"
        const val ACTION_APPROVAL_DECLINE = "com.snowdrop.app.action.APPROVAL_DECLINE"
        const val EXTRA_TRANSFER_ID = "transfer_id"

        private fun transferNotificationId(transferId: String): Int =
            43_000 + (transferId.hashCode() and 0x0FFF)

        private fun approvalNotificationId(transferId: String): Int =
            44_000 + (transferId.hashCode() and 0x0FFF)

        private fun receivedNotificationId(uriString: String): Int =
            45_000 + (uriString.hashCode() and 0x0FFF)

        private fun canPostNotifications(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
            return ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        }

        private fun decodeLargeIcon(context: Context) = runCatching {
            BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)
        }.getOrNull()

        private fun pendingMainIntent(context: Context, requestCode: Int): PendingIntent {
            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        fun createNotificationChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_SERVICE_ID,
                    "Background Reachability",
                    NotificationManager.IMPORTANCE_LOW
                ).apply { setShowBadge(false) }
            )
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_TRANSFER_ID,
                    "Transfers & Approvals",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    enableVibration(true)
                    setShowBadge(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            )
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_RECEIVED_ID,
                    "Received Files",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }

        fun showApprovalNotification(context: Context, req: ApprovalRequest) {
            if (!canPostNotifications(context)) return
            createNotificationChannels(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val baseReqCode = (req.transferId.hashCode() and 0x3FFF) * 4 + 30_000
            fun actionIntent(actionName: String, offset: Int): PendingIntent {
                val intent = Intent(context, TransferActionReceiver::class.java).apply {
                    action = actionName
                    putExtra(EXTRA_TRANSFER_ID, req.transferId)
                }
                return PendingIntent.getBroadcast(
                    context,
                    baseReqCode + offset,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }

            val notification = NotificationCompat.Builder(context, CHANNEL_TRANSFER_ID)
                .setContentTitle("Transfer request")
                .setContentText("${req.senderName} wants to send ${req.fileName} (${req.formattedSize})")
                .setSmallIcon(R.drawable.ic_snowdrop_notification)
                .setLargeIcon(decodeLargeIcon(context))
                .setContentIntent(pendingMainIntent(context, baseReqCode))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setAutoCancel(true)
                .addAction(0, "Accept", actionIntent(ACTION_APPROVAL_ACCEPT, 1))
                .addAction(0, "Always Trust", actionIntent(ACTION_APPROVAL_TRUST, 2))
                .addAction(0, "Decline", actionIntent(ACTION_APPROVAL_DECLINE, 3))
                .build()

            nm.notify(approvalNotificationId(req.transferId), notification)
        }

        fun cancelApprovalNotification(context: Context, transferId: String) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(approvalNotificationId(transferId))
        }

        fun showReceivedNotification(context: Context, fileName: String, contentUri: String) {
            if (!canPostNotifications(context)) return
            createNotificationChannels(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val uri = Uri.parse(contentUri)
            val mimeType = context.contentResolver.getType(uri) ?: "*/*"
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            val reqCode = 50_000 + (contentUri.hashCode() and 0x3FFF)
            val pendingView = PendingIntent.getActivity(
                context,
                reqCode,
                viewIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(context, CHANNEL_RECEIVED_ID)
                .setSmallIcon(R.drawable.ic_snowdrop_notification)
                .setLargeIcon(decodeLargeIcon(context))
                .setContentTitle("File received")
                .setContentText(fileName)
                .setContentIntent(pendingView)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()

            nm.notify(receivedNotificationId(contentUri), notification)
        }

        fun start(context: Context) {
            createNotificationChannels(context)
            val intent = Intent(context, TransferService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
