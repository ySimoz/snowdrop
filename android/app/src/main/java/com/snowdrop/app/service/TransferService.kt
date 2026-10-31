package com.snowdrop.app.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.snowdrop.app.R
import com.snowdrop.app.core.ApprovalRequest
import com.snowdrop.app.core.SnowdropCoreBridge
import com.snowdrop.app.ui.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class TransferActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val transferID = intent.getStringExtra(TransferService.EXTRA_TRANSFER_ID) ?: ""
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(TransferService.NOTIFICATION_APPROVAL_ID)

        when (intent.action) {
            TransferService.ACTION_APPROVAL_ACCEPT -> {
                SnowdropCoreBridge.resolveApproval(transferID, 1)
            }
            TransferService.ACTION_APPROVAL_TRUST -> {
                SnowdropCoreBridge.resolveApproval(transferID, 2)
            }
            TransferService.ACTION_APPROVAL_DECLINE -> {
                SnowdropCoreBridge.resolveApproval(transferID, 3)
            }
            TransferService.ACTION_CANCEL -> {
                if (transferID.isNotEmpty()) {
                    SnowdropCoreBridge.cancelTransfer(transferID)
                }
            }
        }
    }
}

class TransferService : Service() {
    private val serviceScope = CoroutineScope(Dispatchers.Main)
    private var job: Job? = null
    private val notificationManager by lazy {
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels(this)
        SnowdropCoreBridge.init(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                job?.cancel()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_CANCEL -> {
                val transferID = intent.getStringExtra(EXTRA_TRANSFER_ID)
                if (!transferID.isNullOrEmpty()) {
                    SnowdropCoreBridge.cancelTransfer(transferID)
                }
            }
        }

        startForegroundNotification()
        observeTransfer()
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        startForegroundNotification()
    }

    private fun observeTransfer() {
        job?.cancel()
        job = serviceScope.launch {
            SnowdropCoreBridge.activeTransfer.collectLatest { transfer ->
                if (transfer == null) {
                    notificationManager.cancel(NOTIFICATION_TRANSFER_ID)
                    notificationManager.notify(NOTIFICATION_ID, buildIdleNotification())
                } else {
                    val progressPct = (transfer.progress * 100).toInt()
                    val title = if (transfer.isBatch) {
                        if (transfer.isIncoming) "Receiving Files" else "Sending Files"
                    } else {
                        if (transfer.isIncoming) "Receiving File" else "Sending File"
                    }
                    val desc = if (transfer.isBatch) {
                        "Transferring ${transfer.fileIndex} of ${transfer.totalFiles} files ($progressPct%)"
                    } else if (transfer.isIncoming) {
                        "${transfer.fileName} ($progressPct%)"
                    } else {
                        "${transfer.fileName} to ${transfer.peerName} ($progressPct%)"
                    }
                    notificationManager.notify(
                        NOTIFICATION_TRANSFER_ID,
                        buildTransferNotification(title, desc, progressPct, transfer.id)
                    )
                }
            }
        }
    }

    private fun startForegroundNotification() {
        val notification = buildIdleNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildIdleNotification(): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingOpen = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, TransferService::class.java).apply {
            action = ACTION_STOP
        }
        val pendingStop = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val largeIcon = try {
            BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
        } catch (_: Exception) { null }

        val builder = NotificationCompat.Builder(this, CHANNEL_SERVICE_ID)
            .setContentTitle("Snowdrop")
            .setContentText("Ready to receive files in background")
            .setSmallIcon(R.drawable.ic_snowdrop_notification)
            .setContentIntent(pendingOpen)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop Service", pendingStop)

        if (largeIcon != null) {
            builder.setLargeIcon(largeIcon)
        }

        return builder.build()
    }

    private fun buildTransferNotification(
        title: String,
        text: String,
        progress: Int,
        transferID: String
    ): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingOpen = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val largeIcon = try {
            BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
        } catch (_: Exception) { null }

        val builder = NotificationCompat.Builder(this, CHANNEL_TRANSFER_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSubText("$progress%")
            .setSmallIcon(R.drawable.ic_snowdrop_notification)
            .setContentIntent(pendingOpen)
            .setProgress(100, progress, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)

        if (largeIcon != null) {
            builder.setLargeIcon(largeIcon)
        }

        if (transferID.isNotEmpty()) {
            val cancelIntent = Intent(this, TransferActionReceiver::class.java).apply {
                action = ACTION_CANCEL
                putExtra(EXTRA_TRANSFER_ID, transferID)
            }
            val pendingCancel = PendingIntent.getBroadcast(
                this,
                2,
                cancelIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", pendingCancel)
        }

        return builder.build()
    }

    override fun onDestroy() {
        job?.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val CHANNEL_SERVICE_ID = "snowdrop_service_channel"
        const val CHANNEL_TRANSFER_ID = "snowdrop_transfer_channel_v2"
        const val NOTIFICATION_ID = 42445
        const val NOTIFICATION_TRANSFER_ID = 42447
        const val NOTIFICATION_APPROVAL_ID = 42446

        const val ACTION_CANCEL = "com.snowdrop.app.action.CANCEL"
        const val ACTION_STOP = "com.snowdrop.app.action.STOP"
        const val ACTION_APPROVAL_ACCEPT = "com.snowdrop.app.action.APPROVAL_ACCEPT"
        const val ACTION_APPROVAL_TRUST = "com.snowdrop.app.action.APPROVAL_TRUST"
        const val ACTION_APPROVAL_DECLINE = "com.snowdrop.app.action.APPROVAL_DECLINE"
        const val EXTRA_TRANSFER_ID = "transfer_id"

        fun createNotificationChannels(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                val existing = nm.getNotificationChannel(CHANNEL_TRANSFER_ID)
                if (existing != null && existing.importance < NotificationManager.IMPORTANCE_HIGH) {
                    nm.deleteNotificationChannel(CHANNEL_TRANSFER_ID)
                }

                val serviceChannel = NotificationChannel(
                    CHANNEL_SERVICE_ID,
                    "Snowdrop Background Service",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Keeps Snowdrop alive to receive files in background"
                    setShowBadge(false)
                }

                val transferChannel = NotificationChannel(
                    CHANNEL_TRANSFER_ID,
                    "Transfer Alerts & Progress",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Alerts for incoming file transfers, approval requests, and progress"
                    enableVibration(true)
                    setShowBadge(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }

                nm.createNotificationChannel(serviceChannel)
                nm.createNotificationChannel(transferChannel)
            }
        }

        fun showApprovalNotification(context: Context, req: ApprovalRequest) {
            createNotificationChannels(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val acceptIntent = Intent(context, TransferActionReceiver::class.java).apply {
                action = ACTION_APPROVAL_ACCEPT
                putExtra(EXTRA_TRANSFER_ID, req.transferId)
            }
            val trustIntent = Intent(context, TransferActionReceiver::class.java).apply {
                action = ACTION_APPROVAL_TRUST
                putExtra(EXTRA_TRANSFER_ID, req.transferId)
            }
            val declineIntent = Intent(context, TransferActionReceiver::class.java).apply {
                action = ACTION_APPROVAL_DECLINE
                putExtra(EXTRA_TRANSFER_ID, req.transferId)
            }

            val pAccept = PendingIntent.getBroadcast(context, 101, acceptIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val pTrust = PendingIntent.getBroadcast(context, 102, trustIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val pDecline = PendingIntent.getBroadcast(context, 103, declineIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pOpen = PendingIntent.getActivity(context, 100, openIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

            val largeIcon = try {
                BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)
            } catch (_: Exception) { null }

            val builder = NotificationCompat.Builder(context, CHANNEL_TRANSFER_ID)
                .setContentTitle("Transfer Request")
                .setContentText("${req.senderName} wants to send ${req.fileName} (${req.formattedSize})")
                .setSmallIcon(R.drawable.ic_snowdrop_notification)
                .setContentIntent(pOpen)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setAutoCancel(true)
                .addAction(0, "Accept", pAccept)
                .addAction(0, "Always Trust", pTrust)
                .addAction(0, "Decline", pDecline)

            if (largeIcon != null) {
                builder.setLargeIcon(largeIcon)
            }

            val notification = builder.build()

            nm.notify(NOTIFICATION_APPROVAL_ID, notification)
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

        fun stop(context: Context) {
            val intent = Intent(context, TransferService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}
