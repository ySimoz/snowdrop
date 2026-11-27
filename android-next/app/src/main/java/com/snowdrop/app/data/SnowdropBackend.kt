package com.snowdrop.app.data

import com.snowdrop.app.domain.ApprovalDecision
import com.snowdrop.app.domain.ApprovalRequest
import com.snowdrop.app.domain.PeerItem
import com.snowdrop.app.domain.StagedFile
import com.snowdrop.app.domain.TrustedPeer
import kotlinx.coroutines.flow.Flow

sealed interface BackendEvent {
    data class StatusChanged(val code: Int, val message: String) : BackendEvent
    data class AuthRequired(val url: String) : BackendEvent
    data class PeersUpdated(val peers: List<PeerItem>) : BackendEvent
    data class Progress(val transferId: String, val bytesTransferred: Long, val totalBytes: Long) : BackendEvent
    data class BatchProgress(
        val batchId: String,
        val fileIndex: Int,
        val totalFiles: Int,
        val fileName: String,
        val fileBytes: Long,
        val fileTotal: Long,
        val batchBytes: Long,
        val batchTotal: Long
    ) : BackendEvent
    data class BatchFileReceived(
        val batchId: String,
        val fileIndex: Int,
        val totalFiles: Int,
        val fileName: String,
        val filePath: String
    ) : BackendEvent
    data class TransferCompleted(val transferId: String, val success: Boolean, val detail: String) : BackendEvent
    data class IncomingApproval(val request: ApprovalRequest) : BackendEvent
    data class ApprovalDismissed(val transferId: String, val reason: String) : BackendEvent
}

interface SnowdropBackend {
    val events: Flow<BackendEvent>

    suspend fun start(dataDir: String, downloadDir: String, deviceName: String)
    suspend fun stop()
    suspend fun restart(dataDir: String, downloadDir: String, deviceName: String)
    suspend fun sendFile(peerIP: String, file: StagedFile, transferId: String)
    suspend fun sendBatch(peerIP: String, batchId: String, items: List<StagedFile>)
    suspend fun cancelTransfer(transferId: String)
    suspend fun resolveApproval(transferId: String, decision: ApprovalDecision): Boolean
    suspend fun trustedPeers(): List<TrustedPeer>
    suspend fun revokeTrustedPeer(nodeId: String): Boolean
    suspend fun setApprovalConfig(requireApproval: Boolean, autoAcceptTrusted: Boolean)
    suspend fun signOut(): Boolean
}
