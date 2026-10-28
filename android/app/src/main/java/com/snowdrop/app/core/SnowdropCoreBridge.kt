package com.snowdrop.app.core

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.util.Log
import core.AndroidCallback
import core.Core
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import java.io.File
import java.util.UUID

sealed class EngineStatus(val title: String) {
    object Disconnected : EngineStatus("Disconnected")
    data class NeedsAuth(val url: String) : EngineStatus("Sign in Required")
    object Connecting : EngineStatus("Connecting...")
    object Connected : EngineStatus("Ready")
    data class Error(val message: String) : EngineStatus("Error")
}

data class PeerItem(
    val id: String,
    val hostName: String,
    val dnsName: String,
    val os: String,
    val ipAddresses: List<String>,
    val online: Boolean
) {
    val displayName: String
        get() = when {
            hostName.isNotEmpty() -> hostName
            dnsName.isNotEmpty() -> dnsName
            else -> id
        }

    val primaryIP: String?
        get() = ipAddresses.firstOrNull()
}

data class TransferItem(
    val id: String,
    val fileName: String,
    val peerName: String,
    val isIncoming: Boolean,
    val bytesTransferred: Long,
    val totalBytes: Long,
    val isCompleted: Boolean,
    val isSuccess: Boolean,
    val errorMessage: String? = null
) {
    val progress: Float
        get() = if (totalBytes > 0) (bytesTransferred.toFloat() / totalBytes.toFloat()).coerceIn(0f, 1f) else 0f
}

object SnowdropCoreBridge : AndroidCallback {
    private const val TAG = "SnowdropCoreBridge"
    private val scope = CoroutineScope(Dispatchers.Main)

    private val _status = MutableStateFlow<EngineStatus>(EngineStatus.Disconnected)
    val status: StateFlow<EngineStatus> = _status.asStateFlow()

    private val _peers = MutableStateFlow<List<PeerItem>>(emptyList())
    val peers: StateFlow<List<PeerItem>> = _peers.asStateFlow()

    private val _activeTransfer = MutableStateFlow<TransferItem?>(null)
    val activeTransfer: StateFlow<TransferItem?> = _activeTransfer.asStateFlow()

    private val _recentTransfers = MutableStateFlow<List<TransferItem>>(emptyList())
    val recentTransfers: StateFlow<List<TransferItem>> = _recentTransfers.asStateFlow()

    private var isRunning = false
    private lateinit var appContext: Context

    fun init(context: Context) {
        appContext = context.applicationContext
        start()
    }

    fun start() {
        if (isRunning) return
        try {
            val dataDir = appContext.filesDir.absolutePath
            val downloadDir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "Snowdrop"
            ).apply { mkdirs() }.absolutePath

            val deviceName = "${Build.MANUFACTURER} ${Build.MODEL}"
            Core.startAndroidEngine(dataDir, downloadDir, deviceName, this)
            isRunning = true
            _status.value = EngineStatus.Connecting
        } catch (e: Exception) {
            Log.e(TAG, "Failed starting Snowdrop engine", e)
            _status.value = EngineStatus.Error(e.message ?: "Failed starting engine")
        }
    }

    fun stop() {
        if (!isRunning) return
        try {
            Core.stopAndroidEngine()
            isRunning = false
            _status.value = EngineStatus.Disconnected
            _peers.value = emptyList()
            _activeTransfer.value = null
        } catch (e: Exception) {
            Log.e(TAG, "Failed stopping engine", e)
        }
    }

    fun sendFile(context: Context, peerIP: String, uri: Uri) {
        scope.launch(Dispatchers.IO) {
            try {
                val contentResolver = context.contentResolver
                var fileName = "file.bin"
                var fileSize = 0L

                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (cursor.moveToFirst()) {
                        if (nameIdx >= 0) fileName = cursor.getString(nameIdx)
                        if (sizeIdx >= 0) fileSize = cursor.getLong(sizeIdx)
                    }
                }

                val pfd = contentResolver.openFileDescriptor(uri, "r") ?: return@launch
                val fd = pfd.detachFd()

                val transferID = "tx-${UUID.randomUUID().toString().take(8)}"
                val newTransfer = TransferItem(
                    id = transferID,
                    fileName = fileName,
                    peerName = peerIP,
                    isIncoming = false,
                    bytesTransferred = 0,
                    totalBytes = fileSize,
                    isCompleted = false,
                    isSuccess = false
                )
                _activeTransfer.value = newTransfer

                Core.sendFileToPeer(peerIP, fd.toLong(), fileName, fileSize, transferID)
            } catch (e: Exception) {
                Log.e(TAG, "Failed sending file", e)
            }
        }
    }

    fun cancelTransfer(transferID: String) {
        Core.cancelAndroidTransfer(transferID)
    }

    // MARK: - AndroidCallback Implementation

    override fun onStatusChange(status: Long, message: String) {
        scope.launch {
            _status.value = when (status) {
                Core.StatusDisconnected -> EngineStatus.Disconnected
                Core.StatusNeedsAuth -> {
                    val current = _status.value
                    if (current is EngineStatus.NeedsAuth) current else EngineStatus.NeedsAuth("")
                }
                Core.StatusConnecting -> EngineStatus.Connecting
                Core.StatusConnected -> EngineStatus.Connected
                else -> EngineStatus.Error(message)
            }
        }
    }

    override fun onAuthRequired(authURL: String) {
        scope.launch {
            _status.value = EngineStatus.NeedsAuth(authURL)
        }
    }

    override fun onPeersUpdated(peersJSON: String) {
        scope.launch {
            try {
                val array = JSONArray(peersJSON)
                val list = mutableListOf<PeerItem>()
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    val ipsArr = obj.getJSONArray("ipAddresses")
                    val ips = mutableListOf<String>()
                    for (j in 0 until ipsArr.length()) {
                        ips.add(ipsArr.getString(j))
                    }
                    list.add(
                        PeerItem(
                            id = obj.getString("id"),
                            hostName = obj.optString("hostName", ""),
                            dnsName = obj.optString("dnsName", ""),
                            os = obj.optString("os", ""),
                            ipAddresses = ips,
                            online = obj.optBoolean("online", false)
                        )
                    )
                }
                _peers.value = list
            } catch (e: Exception) {
                Log.e(TAG, "Error parsing peers", e)
            }
        }
    }

    override fun onProgress(transferId: String, current: Long, total: Long) {
        scope.launch {
            val existing = _activeTransfer.value
            if (existing != null && existing.id == transferId) {
                _activeTransfer.value = existing.copy(
                    bytesTransferred = current,
                    totalBytes = total
                )
            } else {
                _activeTransfer.value = TransferItem(
                    id = transferId,
                    fileName = "Receiving File...",
                    peerName = "Tailnet Peer",
                    isIncoming = true,
                    bytesTransferred = current,
                    totalBytes = total,
                    isCompleted = false,
                    isSuccess = false
                )
            }
        }
    }

    override fun onTransferComplete(transferId: String, success: Boolean, errorMsg: String) {
        scope.launch {
            val existing = _activeTransfer.value
            if (existing != null && existing.id == transferId) {
                val completed = existing.copy(
                    bytesTransferred = existing.totalBytes,
                    isCompleted = true,
                    isSuccess = success,
                    errorMessage = if (errorMsg.isEmpty()) null else errorMsg
                )
                val history = _recentTransfers.value.toMutableList()
                history.add(0, completed)
                if (history.size > 10) history.removeAt(history.lastIndex)
                _recentTransfers.value = history
                _activeTransfer.value = null
            }
        }
    }
}
