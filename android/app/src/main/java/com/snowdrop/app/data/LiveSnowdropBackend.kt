package com.snowdrop.app.data

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import com.snowdrop.app.domain.ApprovalDecision
import com.snowdrop.app.domain.ApprovalRequest
import com.snowdrop.app.domain.PeerItem
import com.snowdrop.app.domain.StagedFile
import com.snowdrop.app.domain.TrustedPeer
import core.AndroidCallback
import core.Core
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

class LiveSnowdropBackend(
    context: Context
) : SnowdropBackend, AndroidCallback {

    private val appContext = context.applicationContext
    private val lifecycleMutex = Mutex()
    private var isStarted = false

    private val _events = MutableSharedFlow<BackendEvent>(
        replay = 0,
        extraBufferCapacity = 128,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    override val events: Flow<BackendEvent> = _events.asSharedFlow()

    override suspend fun start(dataDir: String, downloadDir: String, deviceName: String) {
        lifecycleMutex.withLock {
            if (isStarted) return
            withContext(Dispatchers.IO) {
                Core.startAndroidEngine(dataDir, downloadDir, deviceName, this@LiveSnowdropBackend)
            }
            isStarted = true
        }
    }

    override suspend fun stop() {
        lifecycleMutex.withLock {
            if (!isStarted) return
            withContext(Dispatchers.IO) {
                Core.stopAndroidEngine()
            }
            isStarted = false
        }
    }

    override suspend fun restart(dataDir: String, downloadDir: String, deviceName: String) {
        lifecycleMutex.withLock {
            withContext(Dispatchers.IO) {
                if (isStarted) {
                    Core.stopAndroidEngine()
                    isStarted = false
                }
                Core.startAndroidEngine(dataDir, downloadDir, deviceName, this@LiveSnowdropBackend)
                isStarted = true
            }
        }
    }

    override suspend fun sendFile(peerIP: String, file: StagedFile, transferId: String) {
        withContext(Dispatchers.IO) {
            val uri = Uri.parse(file.uriString)
            val pfd = appContext.contentResolver.openFileDescriptor(uri, "r")
                ?: throw IllegalStateException("Cannot open file descriptor for ${file.name}")
            val fd = pfd.detachFd()
            Core.sendFileToPeer(peerIP, fd.toLong(), file.name, file.byteSize, transferId)
        }
    }

    override suspend fun sendBatch(peerIP: String, batchId: String, items: List<StagedFile>) {
        withContext(Dispatchers.IO) {
            val detachedFds = mutableListOf<Int>()
            try {
                val jsonArray = JSONArray()
                for (item in items) {
                    val uri = Uri.parse(item.uriString)
                    val pfd = appContext.contentResolver.openFileDescriptor(uri, "r") ?: continue
                    val fd = pfd.detachFd()
                    detachedFds.add(fd)
                    val obj = JSONObject().apply {
                        put("fd", fd)
                        put("name", item.name)
                        put("size", item.byteSize)
                    }
                    jsonArray.put(obj)
                }
                if (detachedFds.isEmpty()) {
                    throw IllegalStateException("No readable files in batch")
                }
                val payload = jsonArray.toString()
                detachedFds.clear()
                Core.sendBatchToPeer(peerIP, batchId, payload)
            } catch (t: Throwable) {
                for (fd in detachedFds) {
                    runCatching { ParcelFileDescriptor.adoptFd(fd).close() }
                }
                throw t
            }
        }
    }

    override suspend fun cancelTransfer(transferId: String) {
        withContext(Dispatchers.IO) {
            Core.cancelAndroidTransfer(transferId)
        }
    }

    override suspend fun resolveApproval(transferId: String, decision: ApprovalDecision): Boolean =
        withContext(Dispatchers.IO) {
            Core.resolveAndroidApproval(transferId, decision.code.toLong())
        }

    override suspend fun trustedPeers(): List<TrustedPeer> =
        withContext(Dispatchers.IO) {
            val raw = Core.getAndroidTrustedPeersJSON()
            parseTrustedPeers(raw)
        }

    override suspend fun revokeTrustedPeer(nodeId: String): Boolean =
        withContext(Dispatchers.IO) {
            Core.revokeAndroidTrusted(nodeId)
        }

    override suspend fun setApprovalConfig(requireApproval: Boolean, autoAcceptTrusted: Boolean) {
        withContext(Dispatchers.IO) {
            Core.setAndroidApprovalConfig(requireApproval, autoAcceptTrusted)
        }
    }

    override suspend fun signOut(): Boolean =
        withContext(Dispatchers.IO) {
            Core.signOutAndroid()
        }

    // MARK: - core.AndroidCallback

    override fun onStatusChange(status: Long, message: String) {
        _events.tryEmit(BackendEvent.StatusChanged(status.toInt(), message))
    }

    override fun onAuthRequired(authURL: String) {
        _events.tryEmit(BackendEvent.AuthRequired(authURL))
    }

    override fun onPeersUpdated(peersJSON: String) {
        _events.tryEmit(BackendEvent.PeersUpdated(parsePeers(peersJSON)))
    }

    override fun onProgress(transferId: String, current: Long, total: Long) {
        _events.tryEmit(BackendEvent.Progress(transferId, current, total))
    }

    override fun onTransferComplete(transferId: String, success: Boolean, errorMsg: String) {
        _events.tryEmit(BackendEvent.TransferCompleted(transferId, success, errorMsg))
    }

    override fun onIncomingApproval(
        transferId: String,
        senderNodeId: String,
        senderName: String,
        fileName: String,
        fileSize: Long
    ) {
        _events.tryEmit(
            BackendEvent.IncomingApproval(
                ApprovalRequest(
                    transferId = transferId,
                    senderNodeId = senderNodeId,
                    senderName = senderName,
                    fileName = fileName,
                    byteSize = fileSize
                )
            )
        )
    }

    override fun onApprovalDismissed(transferId: String, reason: String) {
        _events.tryEmit(BackendEvent.ApprovalDismissed(transferId, reason))
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
        _events.tryEmit(
            BackendEvent.BatchProgress(
                batchId = batchId,
                fileIndex = fileIndex.toInt(),
                totalFiles = totalFiles.toInt(),
                fileName = fileName,
                fileBytes = fileCurrent,
                fileTotal = fileTotal,
                batchBytes = batchCurrent,
                batchTotal = batchTotal
            )
        )
    }

    override fun onBatchFileComplete(
        batchId: String,
        fileIndex: Long,
        totalFiles: Long,
        fileName: String,
        filePath: String
    ) {
        _events.tryEmit(
            BackendEvent.BatchFileReceived(
                batchId = batchId,
                fileIndex = fileIndex.toInt(),
                totalFiles = totalFiles.toInt(),
                fileName = fileName,
                filePath = filePath
            )
        )
    }

    private fun parsePeers(peersJSON: String): List<PeerItem> {
        if (peersJSON.isBlank() || peersJSON == "null") return emptyList()
        return try {
            val array = JSONArray(peersJSON)
            buildList(array.length()) {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    val ipsArr = obj.optJSONArray("ipAddresses")
                    val ips = if (ipsArr != null) {
                        buildList(ipsArr.length()) {
                            for (j in 0 until ipsArr.length()) {
                                add(ipsArr.optString(j))
                            }
                        }
                    } else {
                        emptyList()
                    }
                    add(
                        PeerItem(
                            id = obj.optString("id"),
                            hostName = obj.optString("hostName"),
                            rawDisplayName = obj.optString("displayName"),
                            dnsName = obj.optString("dnsName"),
                            os = obj.optString("os"),
                            ipAddresses = ips,
                            online = obj.optBoolean("online", false)
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed parsing peers JSON", e)
            emptyList()
        }
    }

    private fun parseTrustedPeers(json: String): List<TrustedPeer> {
        if (json.isBlank() || json == "null") return emptyList()
        return try {
            val array = JSONArray(json)
            buildList(array.length()) {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    add(
                        TrustedPeer(
                            nodeId = obj.optString("node_id"),
                            deviceName = obj.optString("device_name", "Peer"),
                            autoAccept = obj.optBoolean("auto_accept", true)
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed parsing trusted peers JSON", e)
            emptyList()
        }
    }

    companion object {
        private const val TAG = "LiveSnowdropBackend"
    }
}
