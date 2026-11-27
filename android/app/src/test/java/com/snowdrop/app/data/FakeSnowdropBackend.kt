package com.snowdrop.app.data

import com.snowdrop.app.domain.ApprovalDecision
import com.snowdrop.app.domain.StagedFile
import com.snowdrop.app.domain.TrustedPeer
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

class FakeSnowdropBackend : SnowdropBackend {
    private val _events = MutableSharedFlow<BackendEvent>(
        replay = 0,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    override val events: Flow<BackendEvent> = _events

    var startCount = 0
    var stopCount = 0
    var restartCount = 0
    var lastSentFile: Pair<String, StagedFile>? = null
    var lastSentBatch: Pair<String, List<StagedFile>>? = null
    val resolvedApprovals = mutableListOf<Pair<String, ApprovalDecision>>()
    val canceledTransfers = mutableListOf<String>()
    var trustedList: List<TrustedPeer> = emptyList()
    var signOutResult = true
    var failOnStart: Throwable? = null

    suspend fun emit(event: BackendEvent) {
        _events.emit(event)
    }

    override suspend fun start(dataDir: String, downloadDir: String, deviceName: String) {
        failOnStart?.let { throw it }
        startCount++
    }

    override suspend fun stop() {
        stopCount++
    }

    override suspend fun restart(dataDir: String, downloadDir: String, deviceName: String) {
        failOnStart?.let { throw it }
        restartCount++
    }

    override suspend fun sendFile(peerIP: String, file: StagedFile, transferId: String) {
        lastSentFile = peerIP to file
    }

    override suspend fun sendBatch(peerIP: String, batchId: String, items: List<StagedFile>) {
        lastSentBatch = peerIP to items
    }

    override suspend fun cancelTransfer(transferId: String) {
        canceledTransfers.add(transferId)
    }

    override suspend fun resolveApproval(transferId: String, decision: ApprovalDecision): Boolean {
        resolvedApprovals.add(transferId to decision)
        return true
    }

    override suspend fun trustedPeers(): List<TrustedPeer> = trustedList

    override suspend fun revokeTrustedPeer(nodeId: String): Boolean {
        trustedList = trustedList.filterNot { it.nodeId == nodeId }
        return true
    }

    override suspend fun setApprovalConfig(requireApproval: Boolean, autoAcceptTrusted: Boolean) {}

    override suspend fun signOut(): Boolean = signOutResult
}
