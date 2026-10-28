package com.snowdrop.app.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.snowdrop.app.core.SnowdropCoreBridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class TransferService : Service() {
    private val serviceScope = CoroutineScope(Dispatchers.Main)
    private var job: Job? = null
    private val notificationManager by lazy {
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            val transferID = intent.getStringExtra(EXTRA_TRANSFER_ID)
            if (!transferID.isNullOrEmpty()) {
                SnowdropCoreBridge.cancelTransfer(transferID)
            }
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        startForegroundNotification()
        observeTransfer()
        return START_STICKY
    }

    private fun observeTransfer() {
        job?.cancel()
        job = serviceScope.launch {
            SnowdropCoreBridge.activeTransfer.collectLatest { transfer ->
                if (transfer == null) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                } else {
                    updateNotification(
                        transfer.fileName,
                        (transfer.progress * 100).toInt(),
                        transfer.id
                    )
                }
            }
        }
    }

    private fun startForegroundNotification() {
        val notification = buildNotification("Initializing transfer...", 0, "")
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

    private fun updateNotification(fileName: String, progressPct: Int, transferID: String) {
        val notification = buildNotification("Transferring $fileName ($progressPct%)", progressPct, transferID)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(text: String, progress: Int, transferID: String) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Snowdrop File Transfer")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setProgress(100, progress, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .apply {
                if (transferID.isNotEmpty()) {
                    val cancelIntent = Intent(this@TransferService, TransferService::class.java).apply {
                        action = ACTION_CANCEL
                        putExtra(EXTRA_TRANSFER_ID, transferID)
                    }
                    val pendingCancel = PendingIntent.getService(
                        this@TransferService,
                        0,
                        cancelIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", pendingCancel)
                }
            }
            .build()

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "File Transfers",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows real-time progress for Snowdrop transfers"
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        job?.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val CHANNEL_ID = "snowdrop_transfer_channel"
        const val NOTIFICATION_ID = 42445
        const val ACTION_CANCEL = "com.snowdrop.app.action.CANCEL"
        const val EXTRA_TRANSFER_ID = "transfer_id"

        fun start(context: Context) {
            val intent = Intent(context, TransferService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
