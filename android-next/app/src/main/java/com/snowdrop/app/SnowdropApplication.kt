package com.snowdrop.app

import android.app.Application
import android.content.Context
import android.os.Build
import android.provider.Settings
import com.snowdrop.app.data.LiveSnowdropBackend
import com.snowdrop.app.data.ReceivedFileStorage
import com.snowdrop.app.data.SnowdropStore
import com.snowdrop.app.service.TransferService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class SnowdropApplication : Application() {
    lateinit var store: SnowdropStore
        private set

    lateinit var storage: ReceivedFileStorage
        private set

    override fun onCreate() {
        super.onCreate()

        val prefs = getSharedPreferences("snowdrop_prefs", Context.MODE_PRIVATE)
        val backend = LiveSnowdropBackend(this)
        storage = ReceivedFileStorage(this)
        val incomingDir = File(cacheDir, "incoming").apply { mkdirs() }
        val deviceName = loadDeviceName(prefs)
        val requireApproval = prefs.getBoolean("require_approval", true)
        val autoAcceptTrusted = prefs.getBoolean("auto_accept_trusted", true)

        store = SnowdropStore(
            backend = backend,
            dataDir = filesDir.absolutePath,
            downloadDir = incomingDir.absolutePath,
            initialDeviceName = deviceName,
            initialDownloadLocation = storage.downloadLocationName(),
            initialRequireApproval = requireApproval,
            initialAutoAcceptTrusted = autoAcceptTrusted,
            onPersistDeviceName = { updated ->
                prefs.edit().putString("device_name", updated).apply()
            },
            onPersistApprovalConfig = { req, auto ->
                prefs.edit()
                    .putBoolean("require_approval", req)
                    .putBoolean("auto_accept_trusted", auto)
                    .apply()
            },
            onIncomingFileSave = { _, filePath ->
                withContext(Dispatchers.IO) {
                    storage.saveReceivedFile(filePath)
                }
            },
            onIncomingApprovalNotification = { request ->
                TransferService.showApprovalNotification(this, request)
            },
            onApprovalNotificationCleared = { transferId ->
                TransferService.cancelApprovalNotification(this, transferId)
            },
            onTransferReceivedNotification = { fileName, uriString ->
                TransferService.showReceivedNotification(this, fileName, uriString)
            }
        )
        store.start()
    }

    private fun loadDeviceName(prefs: android.content.SharedPreferences): String {
        val saved = prefs.getString("device_name", null)?.trim()
        if (!saved.isNullOrEmpty()) return saved

        val globalName = runCatching {
            Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        }.getOrNull()?.trim()
        if (!globalName.isNullOrEmpty()) return globalName

        val manufacturer = Build.MANUFACTURER.orEmpty().trim()
        val model = Build.MODEL.orEmpty().trim()
        val combined = if (model.startsWith(manufacturer, ignoreCase = true)) model else "$manufacturer $model"
        return combined.trim().ifEmpty { "Android" }
    }
}
