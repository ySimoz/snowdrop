package com.snowdrop.app.core

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.util.Log
import com.snowdrop.app.R
import com.snowdrop.app.service.TransferService
import core.AndroidCallback
import core.Core
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
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
    val rawDisplayName: String = "",
    val dnsName: String,
    val os: String,
    val ipAddresses: List<String>,
    val online: Boolean
) {
    val displayName: String
        get() = when {
            rawDisplayName.isNotEmpty() -> rawDisplayName
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
    val errorMessage: String? = null,
    val fileUri: Uri? = null,
    val isBatch: Boolean = false,
    val fileIndex: Int = 1,
    val totalFiles: Int = 1,
    val currentFileName: String = "",
    val currentFileBytes: Long = 0,
    val currentFileTotal: Long = 0
) {
    val progress: Float
        get() = if (totalBytes > 0) (bytesTransferred.toFloat() / totalBytes.toFloat()).coerceIn(0f, 1f) else 0f
    val fileProgress: Float
        get() = if (currentFileTotal > 0) (currentFileBytes.toFloat() / currentFileTotal.toFloat()).coerceIn(0f, 1f) else 0f
}

data class ApprovalRequest(
    val transferId: String,
    val senderNodeId: String,
    val senderName: String,
    val fileName: String,
    val fileSize: Long,
    val formattedSize: String
)

data class TrustedPeer(
    val nodeId: String,
    val deviceName: String,
    val autoAccept: Boolean
)

object SnowdropCoreBridge : AndroidCallback {
    private const val TAG = "SnowdropCoreBridge"
    private val scope = CoroutineScope(Dispatchers.Main)

    private val _status = MutableStateFlow<EngineStatus>(EngineStatus.Disconnected)
    val status: StateFlow<EngineStatus> = _status.asStateFlow()

    private val _deviceName = MutableStateFlow<String>("")
    val deviceName: StateFlow<String> = _deviceName.asStateFlow()

    private val _peers = MutableStateFlow<List<PeerItem>>(emptyList())
    val peers: StateFlow<List<PeerItem>> = _peers.asStateFlow()

    private val _activeTransfer = MutableStateFlow<TransferItem?>(null)
    val activeTransfer: StateFlow<TransferItem?> = _activeTransfer.asStateFlow()

    private val _recentTransfers = MutableStateFlow<List<TransferItem>>(emptyList())
    val recentTransfers: StateFlow<List<TransferItem>> = _recentTransfers.asStateFlow()

    private val _pendingApproval = MutableStateFlow<ApprovalRequest?>(null)
    val pendingApproval: StateFlow<ApprovalRequest?> = _pendingApproval.asStateFlow()

    private val _trustedPeers = MutableStateFlow<List<TrustedPeer>>(emptyList())
    val trustedPeers: StateFlow<List<TrustedPeer>> = _trustedPeers.asStateFlow()

    private val _requireApproval = MutableStateFlow(true)
    val requireApproval: StateFlow<Boolean> = _requireApproval.asStateFlow()

    private val _autoAccept = MutableStateFlow(true)
    val autoAccept: StateFlow<Boolean> = _autoAccept.asStateFlow()

    private val _downloadLocationName = MutableStateFlow<String>("Downloads/Snowdrop")
    val downloadLocationName: StateFlow<String> = _downloadLocationName.asStateFlow()

    private var isRunning = false
    private var cachedAuthURL = ""
    private lateinit var appContext: Context

    data class StagedFile(
        val uri: Uri,
        val name: String,
        val size: Long
    ) {
        val formattedSize: String
            get() = when {
                size >= 1024 * 1024 * 1024 -> String.format("%.2f GB", size.toDouble() / (1024 * 1024 * 1024))
                size >= 1024 * 1024 -> String.format("%.1f MB", size.toDouble() / (1024 * 1024))
                size >= 1024 -> String.format("%.0f KB", size.toDouble() / 1024)
                size > 0 -> "$size B"
                else -> "Unknown size"
            }
    }

    fun getFileInfo(context: Context, uri: Uri): StagedFile {
        var name = "file.bin"
        var size = 0L
        try {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (cursor.moveToFirst()) {
                    if (nameIdx >= 0) name = cursor.getString(nameIdx) ?: "file.bin"
                    if (sizeIdx >= 0) size = cursor.getLong(sizeIdx)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed reading URI metadata: $uri", e)
        }
        return StagedFile(uri, name, size)
    }

    fun getSavedDeviceName(context: Context): String {
        val prefs = context.getSharedPreferences("snowdrop_prefs", Context.MODE_PRIVATE)
        val saved = prefs.getString("device_name", null)
        if (!saved.isNullOrBlank()) {
            return if (saved == saved.lowercase()) {
                saved.split(" ").filter { it.isNotBlank() }.joinToString(" ") { it.replaceFirstChar { c -> c.titlecase() } }
            } else {
                saved
            }
        }

        val systemName = try {
            android.provider.Settings.Global.getString(context.contentResolver, android.provider.Settings.Global.DEVICE_NAME)
        } catch (_: Exception) {
            null
        }

        val raw = if (!systemName.isNullOrBlank()) {
            systemName
        } else {
            val man = Build.MANUFACTURER ?: ""
            val model = Build.MODEL ?: ""
            if (model.startsWith(man, ignoreCase = true)) {
                model
            } else {
                "$man $model"
            }
        }

        return raw.split(" ")
            .filter { it.isNotBlank() }
            .joinToString(" ") { word ->
                word.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
            }
    }

    fun setDeviceName(context: Context, newName: String) {
        val trimmed = newName.trim()
        if (trimmed.isEmpty()) return
        val prefs = context.getSharedPreferences("snowdrop_prefs", Context.MODE_PRIVATE)
        prefs.edit().putString("device_name", trimmed).apply()
        _deviceName.value = trimmed
        restart(context)
    }

    fun getDownloadTreeUri(context: Context): Uri? {
        val prefs = context.getSharedPreferences("snowdrop_prefs", Context.MODE_PRIVATE)
        val uriStr = prefs.getString("custom_download_uri", null) ?: return null
        return try { Uri.parse(uriStr) } catch (_: Exception) { null }
    }

    fun setCustomDownloadTreeUri(context: Context, treeUri: Uri?) {
        val prefs = context.getSharedPreferences("snowdrop_prefs", Context.MODE_PRIVATE)
        if (treeUri == null) {
            prefs.edit().remove("custom_download_uri").remove("custom_download_name").apply()
            _downloadLocationName.value = "Downloads/Snowdrop"
        } else {
            try {
                context.contentResolver.takePersistableUriPermission(
                    treeUri,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (e: Exception) {
                Log.w(TAG, "Could not persist URI permission", e)
            }
            val doc = androidx.documentfile.provider.DocumentFile.fromTreeUri(context, treeUri)
            val name = doc?.name ?: "Custom Folder"
            prefs.edit()
                .putString("custom_download_uri", treeUri.toString())
                .putString("custom_download_name", name)
                .apply()
            _downloadLocationName.value = name
        }
    }

    fun refreshDownloadLocation(context: Context) {
        val prefs = context.getSharedPreferences("snowdrop_prefs", Context.MODE_PRIVATE)
        val customName = prefs.getString("custom_download_name", null)
        _downloadLocationName.value = customName ?: "Downloads/Snowdrop"
    }

    fun restart(context: Context) {
        stop()
        scope.launch(Dispatchers.IO) {
            kotlinx.coroutines.delay(500)
            start()
        }
    }

    fun init(context: Context) {
        appContext = context.applicationContext
        _deviceName.value = getSavedDeviceName(appContext)
        refreshDownloadLocation(appContext)
        migrateLegacyDownloads(appContext)

        val prefs = appContext.getSharedPreferences("snowdrop_prefs", Context.MODE_PRIVATE)
        val reqAppr = prefs.getBoolean("require_approval", true)
        val autoAcc = prefs.getBoolean("auto_accept_trusted", true)
        _requireApproval.value = reqAppr
        _autoAccept.value = autoAcc
        Core.setAndroidApprovalConfig(reqAppr, autoAcc)

        start()
    }

    private fun migrateLegacyDownloads(context: Context) {
        scope.launch(Dispatchers.IO) {
            try {
                val legacyDir = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: return@launch, "Snowdrop")
                if (legacyDir.exists() && legacyDir.isDirectory) {
                    val files = legacyDir.listFiles() ?: return@launch
                    for (file in files) {
                        if (file.isFile) {
                            handleIncomingReceivedFile(context, file.absolutePath)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error migrating legacy downloads", e)
            }
        }
    }

    fun start() {
        if (isRunning) return
        isRunning = true
        _status.value = EngineStatus.Connecting
        Log.i(TAG, "Starting Snowdrop engine...")

        scope.launch(Dispatchers.IO) {
            try {
                val dataDir = appContext.filesDir.absolutePath
                val downloadDir = File(appContext.cacheDir, "incoming").apply { mkdirs() }.absolutePath

                val deviceName = getSavedDeviceName(appContext)
                _deviceName.value = deviceName
                Log.i(TAG, "Calling Core.startAndroidEngine with deviceName=$deviceName")
                Core.startAndroidEngine(dataDir, downloadDir, deviceName, this@SnowdropCoreBridge)
                Log.i(TAG, "Core.startAndroidEngine returned successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed starting Snowdrop engine", e)
                isRunning = false
                _status.value = EngineStatus.Error(e.message ?: "Failed starting engine")
            }
        }
    }

    fun stop() {
        if (!isRunning) return
        isRunning = false
        _status.value = EngineStatus.Disconnected
        _peers.value = emptyList()
        _activeTransfer.value = null

        scope.launch(Dispatchers.IO) {
            try {
                Core.stopAndroidEngine()
            } catch (e: Exception) {
                Log.e(TAG, "Failed stopping engine", e)
            }
        }
    }

    fun sendFile(context: Context, peer: PeerItem, uri: Uri) {
        val ip = peer.primaryIP ?: return
        sendFile(context, ip, uri, peer.displayName)
    }

    fun sendFile(context: Context, peerIP: String, uri: Uri, peerName: String = "") {
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
                val destinationName = if (peerName.isNotEmpty()) peerName else {
                    _peers.value.firstOrNull { it.primaryIP == peerIP }?.displayName ?: peerIP
                }

                val newTransfer = TransferItem(
                    id = transferID,
                    fileName = fileName,
                    peerName = destinationName,
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

    fun sendFiles(context: Context, peer: PeerItem, stagedFiles: List<StagedFile>) {
        val ip = peer.primaryIP ?: return
        sendFiles(context, ip, stagedFiles, peer.displayName)
    }

    fun sendFiles(context: Context, peerIP: String, stagedFiles: List<StagedFile>, peerName: String = "") {
        if (stagedFiles.isEmpty()) return
        if (stagedFiles.size == 1) {
            sendFile(context, peerIP, stagedFiles[0].uri, peerName)
            return
        }

        scope.launch(Dispatchers.IO) {
            try {
                val contentResolver = context.contentResolver
                val batchID = "batch-${UUID.randomUUID().toString().take(8)}"
                val destinationName = if (peerName.isNotEmpty()) peerName else {
                    _peers.value.firstOrNull { it.primaryIP == peerIP }?.displayName ?: peerIP
                }

                val totalBytes = stagedFiles.sumOf { it.size }
                val filesJsonArray = JSONArray()

                for (sf in stagedFiles) {
                    val pfd = contentResolver.openFileDescriptor(sf.uri, "r") ?: continue
                    val fd = pfd.detachFd()
                    val obj = JSONObject().apply {
                        put("fd", fd)
                        put("name", sf.name)
                        put("size", sf.size)
                    }
                    filesJsonArray.put(obj)
                }

                val newTransfer = TransferItem(
                    id = batchID,
                    fileName = "${stagedFiles.size} files",
                    peerName = destinationName,
                    isIncoming = false,
                    bytesTransferred = 0,
                    totalBytes = totalBytes,
                    isCompleted = false,
                    isSuccess = false,
                    isBatch = true,
                    fileIndex = 1,
                    totalFiles = stagedFiles.size,
                    currentFileName = stagedFiles.firstOrNull()?.name ?: "",
                    currentFileBytes = 0,
                    currentFileTotal = stagedFiles.firstOrNull()?.size ?: 0
                )
                _activeTransfer.value = newTransfer

                Core.sendBatchToPeer(peerIP, batchID, filesJsonArray.toString())
            } catch (e: Exception) {
                Log.e(TAG, "Failed sending batch", e)
            }
        }
    }

    fun clearRecentTransfers() {
        _recentTransfers.value = emptyList()
    }

    fun removeRecentTransfer(transferId: String) {
        _recentTransfers.value = _recentTransfers.value.filter { it.id != transferId }
    }

    fun cancelTransfer(transferID: String) {
        Core.cancelAndroidTransfer(transferID)
    }

    // MARK: - AndroidCallback Implementation

    override fun onStatusChange(status: Long, message: String) {
        Log.i(TAG, "onStatusChange: status=$status, message=$message, cachedURL=$cachedAuthURL")
        scope.launch {
            _status.value = when (status) {
                Core.StatusDisconnected -> EngineStatus.Disconnected
                Core.StatusNeedsAuth -> EngineStatus.NeedsAuth(cachedAuthURL)
                Core.StatusConnecting -> {
                    if (cachedAuthURL.isNotEmpty()) EngineStatus.NeedsAuth(cachedAuthURL) else EngineStatus.Connecting
                }
                Core.StatusConnected -> {
                    cachedAuthURL = ""
                    EngineStatus.Connected
                }
                else -> EngineStatus.Error(message)
            }
        }
    }

    override fun onAuthRequired(authURL: String) {
        Log.i(TAG, "onAuthRequired: authURL=$authURL")
        scope.launch {
            if (authURL.isNotEmpty()) {
                cachedAuthURL = authURL
            }
            _status.value = EngineStatus.NeedsAuth(cachedAuthURL)
        }
    }

    override fun onPeersUpdated(peersJSON: String) {
        scope.launch {
            try {
                if (peersJSON.isEmpty() || peersJSON == "null") {
                    _peers.value = emptyList()
                    return@launch
                }
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
                            rawDisplayName = obj.optString("displayName", ""),
                            dnsName = obj.optString("dnsName", ""),
                            os = obj.optString("os", ""),
                            ipAddresses = ips,
                            online = obj.optBoolean("online", false)
                        )
                    )
                }
                _peers.value = list
                Log.i(TAG, "onPeersUpdated: loaded ${list.size} peers: ${list.map { "${it.displayName} (${it.primaryIP})" }}")
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
                val sender = _peers.value.firstOrNull { it.online }?.displayName ?: "Tailnet Peer"
                _activeTransfer.value = TransferItem(
                    id = transferId,
                    fileName = "Receiving File...",
                    peerName = sender,
                    isIncoming = true,
                    bytesTransferred = current,
                    totalBytes = total,
                    isCompleted = false,
                    isSuccess = false
                )
            }
        }
    }

    override fun onBatchProgress(
        batchId: String,
        fileIndex: Long,
        totalFiles: Long,
        fileName: String,
        fileCurrent: Long,
        fileTotal: Long,
        batchCurrent: Long,
        batchTotal: Long
    ) {
        scope.launch {
            val existing = _activeTransfer.value
            val sender = _peers.value.firstOrNull { it.online }?.displayName ?: "Tailnet Peer"
            val baseName = if (totalFiles > 1) "$totalFiles files" else fileName
            val peer = existing?.peerName ?: sender
            val isInc = existing?.isIncoming ?: true

            _activeTransfer.value = (existing ?: TransferItem(
                id = batchId,
                fileName = baseName,
                peerName = peer,
                isIncoming = isInc,
                bytesTransferred = batchCurrent,
                totalBytes = batchTotal,
                isCompleted = false,
                isSuccess = false
            )).copy(
                fileName = baseName,
                bytesTransferred = batchCurrent,
                totalBytes = batchTotal,
                isBatch = totalFiles > 1,
                fileIndex = fileIndex.toInt(),
                totalFiles = totalFiles.toInt(),
                currentFileName = fileName,
                currentFileBytes = fileCurrent,
                currentFileTotal = fileTotal
            )
        }
    }

    override fun onBatchFileComplete(
        batchId: String,
        fileIndex: Long,
        totalFiles: Long,
        fileName: String,
        filePath: String
    ) {
        scope.launch(Dispatchers.IO) {
            if (filePath.isNotEmpty()) {
                val savedUri = handleIncomingReceivedFile(appContext, filePath)
                if (savedUri != null) {
                    showReceivedNotification(appContext, fileName, savedUri)
                }
            }
        }
    }

    override fun onTransferComplete(transferId: String, success: Boolean, errorMsg: String) {
        scope.launch(Dispatchers.IO) {
            var savedUri: Uri? = null
            var finalError: String? = if (errorMsg.isEmpty()) null else errorMsg

            val existing = _activeTransfer.value
            if (success && errorMsg.isNotEmpty()) {
                val sourceFile = File(errorMsg)
                if (sourceFile.exists()) {
                    savedUri = handleIncomingReceivedFile(appContext, errorMsg)
                    finalError = null
                    val displayName = existing?.fileName?.takeIf { it != "Receiving File..." } ?: sourceFile.name
                    if (savedUri != null) {
                        showReceivedNotification(appContext, displayName, savedUri)
                    }
                }
            }

            launch(Dispatchers.Main) {
                val displayName = existing?.fileName?.takeIf { it != "Receiving File..." }
                    ?: (if (errorMsg.isNotEmpty()) File(errorMsg).name else "File")

                val completed = (existing ?: TransferItem(
                    id = transferId,
                    fileName = displayName,
                    peerName = "Peer",
                    isIncoming = true,
                    bytesTransferred = 0,
                    totalBytes = 0,
                    isCompleted = true,
                    isSuccess = success
                )).copy(
                    fileName = displayName,
                    bytesTransferred = existing?.totalBytes ?: 0,
                    isCompleted = true,
                    isSuccess = success,
                    errorMessage = finalError,
                    fileUri = savedUri
                )
                val history = _recentTransfers.value.toMutableList()
                history.add(0, completed)
                if (history.size > 10) history.removeAt(history.lastIndex)
                _recentTransfers.value = history
                _activeTransfer.value = null
            }
        }
    }

    override fun onIncomingApproval(
        transferId: String,
        senderNodeId: String,
        senderName: String,
        fileName: String,
        fileSize: Long
    ) {
        scope.launch {
            val formatted = when {
                fileSize >= 1024 * 1024 * 1024 -> String.format("%.2f GB", fileSize.toDouble() / (1024 * 1024 * 1024))
                fileSize >= 1024 * 1024 -> String.format("%.1f MB", fileSize.toDouble() / (1024 * 1024))
                fileSize >= 1024 -> String.format("%.0f KB", fileSize.toDouble() / 1024)
                fileSize > 0 -> "$fileSize B"
                else -> "Unknown size"
            }
            val req = ApprovalRequest(
                transferId = transferId,
                senderNodeId = senderNodeId,
                senderName = senderName,
                fileName = fileName,
                fileSize = fileSize,
                formattedSize = formatted
            )
            _pendingApproval.value = req
            TransferService.showApprovalNotification(appContext, req)
        }
    }

    fun resolveApproval(transferId: String, decision: Int) {
        scope.launch {
            if (_pendingApproval.value?.transferId == transferId) {
                _pendingApproval.value = null
            }
        }
        Core.resolveAndroidApproval(transferId, decision.toLong())
        refreshTrustedPeers()
    }

    fun refreshTrustedPeers() {
        scope.launch(Dispatchers.IO) {
            try {
                val jsonStr = Core.getAndroidTrustedPeersJSON()
                if (jsonStr.isNullOrEmpty() || jsonStr == "null") {
                    _trustedPeers.value = emptyList()
                    return@launch
                }
                val arr = JSONArray(jsonStr)
                val list = mutableListOf<TrustedPeer>()
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    list.add(
                        TrustedPeer(
                            nodeId = obj.getString("node_id"),
                            deviceName = obj.optString("device_name", "Peer"),
                            autoAccept = obj.optBoolean("auto_accept", true)
                        )
                    )
                }
                _trustedPeers.value = list
            } catch (e: Exception) {
                Log.e(TAG, "Error loading trusted peers", e)
            }
        }
    }

    fun revokeTrustedPeer(nodeId: String) {
        Core.revokeAndroidTrusted(nodeId)
        refreshTrustedPeers()
    }

    fun setApprovalConfig(requireApproval: Boolean, autoAcceptTrusted: Boolean) {
        _requireApproval.value = requireApproval
        _autoAccept.value = autoAcceptTrusted
        Core.setAndroidApprovalConfig(requireApproval, autoAcceptTrusted)
        if (::appContext.isInitialized) {
            val prefs = appContext.getSharedPreferences("snowdrop_prefs", Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean("require_approval", requireApproval)
                .putBoolean("auto_accept_trusted", autoAcceptTrusted)
                .apply()
        }
    }

    private fun handleIncomingReceivedFile(context: Context, filePath: String): Uri? {
        val sourceFile = File(filePath)
        if (!sourceFile.exists()) return null

        val fileName = sourceFile.name
        val mimeType = try {
            val extension = fileName.substringAfterLast('.', "")
            android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase()) ?: "application/octet-stream"
        } catch (_: Exception) {
            "application/octet-stream"
        }

        val treeUri = getDownloadTreeUri(context)
        if (treeUri != null) {
            try {
                val dir = androidx.documentfile.provider.DocumentFile.fromTreeUri(context, treeUri)
                val targetDoc = dir?.createFile(mimeType, fileName)
                if (targetDoc != null) {
                    context.contentResolver.openOutputStream(targetDoc.uri)?.use { out ->
                        sourceFile.inputStream().use { it.copyTo(out) }
                    }
                    sourceFile.delete()
                    Log.i(TAG, "Saved received file to custom tree: ${targetDoc.uri}")
                    return targetDoc.uri
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error saving to custom tree, falling back to MediaStore", e)
            }
        }

        // Default: MediaStore.Downloads (Android 10+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val values = android.content.ContentValues().apply {
                    put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Snowdrop")
                }
                val uri = context.contentResolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (uri != null) {
                    context.contentResolver.openOutputStream(uri)?.use { out ->
                        sourceFile.inputStream().use { it.copyTo(out) }
                    }
                    sourceFile.delete()
                    android.media.MediaScannerConnection.scanFile(context, arrayOf(sourceFile.absolutePath), null, null)
                    Log.i(TAG, "Saved received file to MediaStore Downloads: $uri")
                    return uri
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error saving to MediaStore.Downloads", e)
            }
        } else {
            // Android 9 and below fallback
            try {
                val pubDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Snowdrop")
                pubDir.mkdirs()
                val destFile = File(pubDir, fileName)
                sourceFile.copyTo(destFile, overwrite = true)
                sourceFile.delete()
                android.media.MediaScannerConnection.scanFile(context, arrayOf(destFile.absolutePath), null, null)
                return Uri.fromFile(destFile)
            } catch (e: Exception) {
                Log.e(TAG, "Error saving to public Downloads dir", e)
            }
        }

        return Uri.fromFile(sourceFile)
    }

    private fun showReceivedNotification(context: Context, fileName: String, fileUri: Uri) {
        try {
            val channelId = "snowdrop_transfers"
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = android.app.NotificationChannel(
                    channelId,
                    "File Transfers",
                    android.app.NotificationManager.IMPORTANCE_DEFAULT
                )
                notificationManager.createNotificationChannel(channel)
            }

            val openIntent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                setDataAndType(fileUri, context.contentResolver.getType(fileUri) ?: "*/*")
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            val pendingIntent = android.app.PendingIntent.getActivity(
                context,
                fileUri.hashCode(),
                openIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )

            val largeIcon = try {
                android.graphics.BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)
            } catch (_: Exception) { null }

            val builder = androidx.core.app.NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.drawable.ic_snowdrop_notification)
                .setContentTitle("File Received")
                .setContentText(fileName)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)

            if (largeIcon != null) {
                builder.setLargeIcon(largeIcon)
            }

            val notification = builder.build()

            notificationManager.notify((System.currentTimeMillis() % 100000).toInt(), notification)
        } catch (e: Exception) {
            Log.e(TAG, "Failed posting received notification", e)
        }
    }
}
