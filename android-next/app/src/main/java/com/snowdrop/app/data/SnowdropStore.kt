package com.snowdrop.app.data

import com.snowdrop.app.domain.AppTab
import com.snowdrop.app.domain.ApprovalDecision
import com.snowdrop.app.domain.ApprovalRequest
import com.snowdrop.app.domain.EngineStatus
import com.snowdrop.app.domain.PeerItem
import com.snowdrop.app.domain.SnowdropUiState
import com.snowdrop.app.domain.StagedFile
import com.snowdrop.app.domain.TransferDirection
import com.snowdrop.app.domain.TransferItem
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

class SnowdropStore(
    private val backend: SnowdropBackend,
    private val dataDir: String,
    private val downloadDir: String,
    initialDeviceName: String,
    initialDownloadLocation: String = "Downloads/Snowdrop",
    initialRequireApproval: Boolean = true,
    initialAutoAcceptTrusted: Boolean = true,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
    private val clockMs: () -> Long = { System.currentTimeMillis() },
    private val onPersistDeviceName: ((String) -> Unit)? = null,
    private val onPersistApprovalConfig: ((Boolean, Boolean) -> Unit)? = null,
    private val onIncomingFileSave: (suspend (transferId: String, filePath: String) -> String?)? = null,
    private val onIncomingApprovalNotification: ((ApprovalRequest) -> Unit)? = null,
    private val onApprovalNotificationCleared: ((String) -> Unit)? = null,
    private val onTransferReceivedNotification: ((fileName: String, contentUri: String) -> Unit)? = null
) {
    private val _uiState = MutableStateFlow(
        SnowdropUiState(
            deviceName = initialDeviceName.ifBlank { "Android" },
            downloadLocationName = initialDownloadLocation,
            requireApproval = initialRequireApproval,
            autoAcceptTrusted = initialAutoAcceptTrusted
        )
    )
    val uiState: StateFlow<SnowdropUiState> = _uiState.asStateFlow()

    private val activeTransferMap = LinkedHashMap<String, TransferItem>()
    private val incomingMetadata = mutableMapOf<String, Pair<String, String>>()
    private val batchSavedUris = mutableMapOf<String, String>()
    private val progressSamples = mutableMapOf<String, Pair<Long, Long>>()
    private var cachedAuthUrl = ""
    private var isStarted = false
    private var eventJob: Job? = null

    fun start(): Job {
        startListening()
        return scope.launch {
            if (isStarted) return@launch
            isStarted = true
            _uiState.update { it.copy(status = EngineStatus.Connecting, lastError = null) }
            try {
                val state = _uiState.value
                backend.start(dataDir, downloadDir, state.deviceName)
                backend.setApprovalConfig(state.requireApproval, state.autoAcceptTrusted)
                val trusted = backend.trustedPeers()
                _uiState.update { it.copy(trustedPeers = trusted) }
            } catch (t: Throwable) {
                isStarted = false
                val msg = t.message ?: "Unable to start Snowdrop engine"
                _uiState.update { it.copy(status = EngineStatus.Error(msg), lastError = msg) }
            }
        }
    }

    fun stop(): Job = scope.launch {
        eventJob?.cancel()
        eventJob = null
        backend.stop()
        isStarted = false
        activeTransferMap.clear()
        progressSamples.clear()
        _uiState.update {
            it.copy(
                status = EngineStatus.Disconnected,
                peers = emptyList(),
                filteredPeers = emptyList(),
                activeTransfers = emptyList(),
                pendingApprovals = emptyList()
            )
        }
    }

    fun restart(): Job = scope.launch {
        if (_uiState.value.isRestarting) return@launch
        _uiState.update { it.copy(isRestarting = true, status = EngineStatus.Connecting, lastError = null) }
        try {
            startListening()
            val state = _uiState.value
            backend.restart(dataDir, downloadDir, state.deviceName)
            isStarted = true
            backend.setApprovalConfig(state.requireApproval, state.autoAcceptTrusted)
            val trusted = backend.trustedPeers()
            _uiState.update { it.copy(trustedPeers = trusted, isRestarting = false) }
        } catch (t: Throwable) {
            isStarted = false
            val msg = t.message ?: "Unable to restart network stack"
            _uiState.update {
                it.copy(
                    isRestarting = false,
                    status = EngineStatus.Error(msg),
                    lastError = msg
                )
            }
        }
    }

    fun renameDevice(newName: String): Job = scope.launch {
        val trimmed = newName.trim()
        if (trimmed.isEmpty() || trimmed == _uiState.value.deviceName) return@launch
        _uiState.update { it.copy(deviceName = trimmed) }
        onPersistDeviceName?.invoke(trimmed)
        restart().join()
    }

    fun signOut(): Job = scope.launch {
        if (_uiState.value.isSigningOut) return@launch
        _uiState.update { it.copy(isSigningOut = true) }
        val ok = runCatching { backend.signOut() }.getOrDefault(false)
        if (ok) {
            cachedAuthUrl = ""
            _uiState.update {
                it.copy(
                    isSigningOut = false,
                    peers = emptyList(),
                    filteredPeers = emptyList(),
                    status = EngineStatus.NeedsAuth(""),
                    lastError = null
                )
            }
        } else {
            _uiState.update { it.copy(isSigningOut = false, lastError = "Unable to sign out") }
        }
    }

    fun selectTab(tab: AppTab) {
        _uiState.update { it.copy(selectedTab = tab) }
    }

    fun setSearchQuery(query: String) {
        _uiState.update { current ->
            current.copy(
                searchQuery = query,
                filteredPeers = filterAndSortPeers(current.peers, query)
            )
        }
    }

    fun setDownloadLocationName(name: String) {
        _uiState.update { it.copy(downloadLocationName = name) }
    }

    fun stageFiles(files: List<StagedFile>): Int {
        if (files.isEmpty()) return 0
        var added = 0
        _uiState.update { current ->
            val existing = current.stagedFiles.map { it.uriString }.toSet()
            val fresh = files.distinctBy { it.uriString }.filter { it.uriString !in existing }
            added = fresh.size
            if (fresh.isEmpty()) current else current.copy(stagedFiles = current.stagedFiles + fresh)
        }
        return added
    }

    fun removeStagedFile(uriString: String) {
        _uiState.update { current ->
            current.copy(stagedFiles = current.stagedFiles.filterNot { it.uriString == uriString })
        }
    }

    fun clearStagedFiles() {
        _uiState.update { it.copy(stagedFiles = emptyList()) }
    }

    fun sendStagedFiles(peer: PeerItem): Job {
        val current = _uiState.value
        val files = current.stagedFiles
        if (!peer.online || peer.primaryIP == null || files.isEmpty()) {
            return scope.launch {}
        }
        clearStagedFiles()
        return enqueueTransfer(peer, files)
    }

    fun sendDirectFiles(peer: PeerItem, files: List<StagedFile>): Job {
        if (!peer.online || peer.primaryIP == null || files.isEmpty()) {
            return scope.launch {}
        }
        return enqueueTransfer(peer, files)
    }

    private fun enqueueTransfer(peer: PeerItem, files: List<StagedFile>): Job = scope.launch {
        val peerIP = peer.primaryIP ?: return@launch

        if (files.size == 1) {
            val file = files.first()
            val txId = "tx-${UUID.randomUUID().toString().take(8)}"
            activeTransferMap[txId] = TransferItem(
                id = txId,
                fileName = file.name,
                peerName = peer.displayName,
                direction = TransferDirection.OUTGOING,
                bytesTransferred = 0L,
                totalBytes = file.byteSize,
                startTimeMs = clockMs()
            )
            publishActiveTransfers()
            runCatching { backend.sendFile(peerIP, file, txId) }.onFailure { err ->
                activeTransferMap.remove(txId)
                publishActiveTransfers()
                reportError(err.message ?: "Failed sending ${file.name}")
            }
            return@launch
        }

        val batchId = "batch-${UUID.randomUUID().toString().take(8)}"
        val totalBytes = files.sumOf { it.byteSize }
        activeTransferMap[batchId] = TransferItem(
            id = batchId,
            fileName = "${files.size} files",
            peerName = peer.displayName,
            direction = TransferDirection.OUTGOING,
            bytesTransferred = 0L,
            totalBytes = totalBytes,
            startTimeMs = clockMs(),
            isBatch = true,
            fileIndex = 1,
            totalFiles = files.size,
            currentFileName = files.first().name,
            currentFileBytes = 0L,
            currentFileTotal = files.first().byteSize
        )
        publishActiveTransfers()
        runCatching { backend.sendBatch(peerIP, batchId, files) }.onFailure { err ->
            activeTransferMap.remove(batchId)
            publishActiveTransfers()
            reportError(err.message ?: "Failed sending batch")
        }
    }

    fun cancelTransfer(transferId: String): Job = scope.launch {
        backend.cancelTransfer(transferId)
    }

    fun resolveApproval(transferId: String, decision: ApprovalDecision): Job = scope.launch {
        _uiState.update { current ->
            current.copy(pendingApprovals = current.pendingApprovals.filterNot { it.transferId == transferId })
        }
        if (decision == ApprovalDecision.DECLINE) {
            incomingMetadata.remove(transferId)
        }
        onApprovalNotificationCleared?.invoke(transferId)
        backend.resolveApproval(transferId, decision)
        if (decision == ApprovalDecision.ALWAYS_TRUST) {
            val trusted = backend.trustedPeers()
            _uiState.update { it.copy(trustedPeers = trusted) }
        }
    }

    fun revokeTrustedPeer(nodeId: String): Job = scope.launch {
        if (backend.revokeTrustedPeer(nodeId)) {
            val trusted = backend.trustedPeers()
            _uiState.update { it.copy(trustedPeers = trusted) }
        }
    }

    fun updateApprovalConfig(requireApproval: Boolean, autoAcceptTrusted: Boolean): Job = scope.launch {
        _uiState.update {
            it.copy(requireApproval = requireApproval, autoAcceptTrusted = autoAcceptTrusted)
        }
        onPersistApprovalConfig?.invoke(requireApproval, autoAcceptTrusted)
        backend.setApprovalConfig(requireApproval, autoAcceptTrusted)
    }

    fun removeRecentTransfer(id: String) {
        _uiState.update { current ->
            current.copy(recentTransfers = current.recentTransfers.filterNot { it.id == id })
        }
    }

    fun clearRecentTransfers() {
        _uiState.update { it.copy(recentTransfers = emptyList()) }
    }

    fun reportError(message: String) {
        _uiState.update { it.copy(lastError = message) }
    }

    fun dismissError() {
        _uiState.update { it.copy(lastError = null) }
    }

    private fun startListening() {
        if (eventJob != null) return
        eventJob = scope.launch {
            backend.events.collect { event ->
                apply(event)
            }
        }
    }

    suspend fun apply(event: BackendEvent) {
        when (event) {
            is BackendEvent.StatusChanged -> handleStatusChanged(event)
            is BackendEvent.AuthRequired -> handleAuthRequired(event)
            is BackendEvent.PeersUpdated -> {
                _uiState.update { current ->
                    current.copy(
                        peers = event.peers,
                        filteredPeers = filterAndSortPeers(event.peers, current.searchQuery)
                    )
                }
            }
            is BackendEvent.Progress -> handleProgress(event)
            is BackendEvent.BatchProgress -> handleBatchProgress(event)
            is BackendEvent.BatchFileReceived -> {
                if (event.filePath.isNotBlank()) {
                    val savedUri = onIncomingFileSave?.invoke(event.batchId, event.filePath)
                    if (savedUri != null) {
                        batchSavedUris[event.batchId] = savedUri
                        onTransferReceivedNotification?.invoke(event.fileName, savedUri)
                    }
                }
            }
            is BackendEvent.TransferCompleted -> handleTransferCompleted(event)
            is BackendEvent.IncomingApproval -> handleIncomingApproval(event.request)
            is BackendEvent.ApprovalDismissed -> {
                incomingMetadata.remove(event.transferId)
                _uiState.update { current ->
                    current.copy(
                        pendingApprovals = current.pendingApprovals.filterNot {
                            it.transferId == event.transferId
                        }
                    )
                }
                onApprovalNotificationCleared?.invoke(event.transferId)
            }
        }
    }

    private suspend fun handleStatusChanged(event: BackendEvent.StatusChanged) {
        when (event.code) {
            0 -> _uiState.update { it.copy(status = EngineStatus.Disconnected) }
            1 -> _uiState.update { it.copy(status = EngineStatus.NeedsAuth(cachedAuthUrl)) }
            2 -> {
                val next = if (cachedAuthUrl.isEmpty()) EngineStatus.Connecting else EngineStatus.NeedsAuth(cachedAuthUrl)
                _uiState.update { it.copy(status = next) }
            }
            3 -> {
                cachedAuthUrl = ""
                val trusted = runCatching { backend.trustedPeers() }.getOrDefault(_uiState.value.trustedPeers)
                _uiState.update {
                    it.copy(
                        status = EngineStatus.Connected,
                        lastError = null,
                        trustedPeers = trusted
                    )
                }
            }
            4 -> _uiState.update { it.copy(status = EngineStatus.Error(event.message), lastError = event.message) }
        }
    }

    private fun handleAuthRequired(event: BackendEvent.AuthRequired) {
        if (event.url.isNotEmpty()) {
            cachedAuthUrl = event.url
        }
        _uiState.update { it.copy(status = EngineStatus.NeedsAuth(cachedAuthUrl)) }
    }

    private fun handleProgress(event: BackendEvent.Progress) {
        val nowMs = clockMs()
        val existing = activeTransferMap[event.transferId]
        val base = existing ?: run {
            val meta = incomingMetadata[event.transferId]
            val peerName = meta?.first ?: (_uiState.value.peers.firstOrNull { it.online }?.displayName ?: "Tailnet peer")
            val fileName = meta?.second ?: "Incoming transfer"
            TransferItem(
                id = event.transferId,
                fileName = fileName,
                peerName = peerName,
                direction = TransferDirection.INCOMING,
                bytesTransferred = event.bytesTransferred,
                totalBytes = event.totalBytes,
                startTimeMs = nowMs
            )
        }
        val (speed, eta) = computeSpeedAndEta(event.transferId, event.bytesTransferred, event.totalBytes, nowMs)
        activeTransferMap[event.transferId] = base.copy(
            bytesTransferred = event.bytesTransferred,
            totalBytes = event.totalBytes,
            speedBytesPerSec = speed,
            etaSeconds = eta
        )
        publishActiveTransfers()
    }

    private fun handleBatchProgress(event: BackendEvent.BatchProgress) {
        val nowMs = clockMs()
        val existing = activeTransferMap[event.batchId]
        val meta = incomingMetadata[event.batchId]
        val peerName = existing?.peerName ?: meta?.first ?: (_uiState.value.peers.firstOrNull { it.online }?.displayName ?: "Tailnet peer")
        val direction = existing?.direction ?: TransferDirection.INCOMING
        val title = if (event.totalFiles > 1) "${event.totalFiles} files" else event.fileName
        val (speed, eta) = computeSpeedAndEta(event.batchId, event.batchBytes, event.batchTotal, nowMs)
        activeTransferMap[event.batchId] = (existing ?: TransferItem(
            id = event.batchId,
            fileName = title,
            peerName = peerName,
            direction = direction,
            bytesTransferred = event.batchBytes,
            totalBytes = event.batchTotal,
            startTimeMs = nowMs
        )).copy(
            fileName = title,
            bytesTransferred = event.batchBytes,
            totalBytes = event.batchTotal,
            speedBytesPerSec = speed,
            etaSeconds = eta,
            isBatch = event.totalFiles > 1,
            fileIndex = event.fileIndex,
            totalFiles = event.totalFiles,
            currentFileName = event.fileName,
            currentFileBytes = event.fileBytes,
            currentFileTotal = event.fileTotal
        )
        publishActiveTransfers()
    }

    private suspend fun handleTransferCompleted(event: BackendEvent.TransferCompleted) {
        val existing = activeTransferMap.remove(event.transferId)
        val meta = incomingMetadata.remove(event.transferId)
        progressSamples.remove(event.transferId)
        publishActiveTransfers()

        var savedUri: String? = null
        var errorMsg: String? = null
        val batchLastUri = batchSavedUris.remove(event.transferId)
        val resolvedName = existing?.fileName
            ?: meta?.second
            ?: event.detail.substringAfterLast('/').ifBlank { "File" }
        if (event.success) {
            if (event.detail.isNotBlank() && onIncomingFileSave != null) {
                savedUri = onIncomingFileSave.invoke(event.transferId, event.detail)
                if (savedUri != null) {
                    onTransferReceivedNotification?.invoke(resolvedName, savedUri)
                }
            } else if (batchLastUri != null) {
                savedUri = batchLastUri
            }
        } else {
            errorMsg = event.detail.ifBlank { "Transfer failed" }
        }

        val resolvedPeer = existing?.peerName ?: meta?.first ?: "Tailnet peer"
        val resolvedDirection = existing?.direction ?: TransferDirection.INCOMING

        val completed = (existing ?: TransferItem(
            id = event.transferId,
            fileName = resolvedName,
            peerName = resolvedPeer,
            direction = resolvedDirection,
            bytesTransferred = 0L,
            totalBytes = 0L,
            startTimeMs = clockMs()
        )).copy(
            fileName = resolvedName,
            bytesTransferred = existing?.totalBytes ?: existing?.bytesTransferred ?: 0L,
            isCompleted = true,
            isSuccess = event.success,
            errorMessage = errorMsg,
            destinationUriString = savedUri ?: existing?.destinationUriString
        )

        _uiState.update { current ->
            val nextHistory = (listOf(completed) + current.recentTransfers.filterNot { it.id == completed.id }).take(20)
            current.copy(
                recentTransfers = nextHistory,
                lastError = if (!event.success && errorMsg != null) errorMsg else current.lastError
            )
        }
    }

    private fun handleIncomingApproval(request: ApprovalRequest) {
        incomingMetadata[request.transferId] = request.senderName to request.fileName
        _uiState.update { current ->
            val deduped = current.pendingApprovals.filterNot { it.transferId == request.transferId }
            val next = (deduped + request).takeLast(MAX_PENDING_APPROVALS)
            current.copy(pendingApprovals = next)
        }
        onIncomingApprovalNotification?.invoke(request)
    }

    private fun computeSpeedAndEta(
        transferId: String,
        bytesTransferred: Long,
        totalBytes: Long,
        nowMs: Long
    ): Pair<Double, Double> {
        val prev = progressSamples[transferId]
        if (prev == null) {
            progressSamples[transferId] = nowMs to bytesTransferred
            return 0.0 to 0.0
        }
        val elapsedSec = (nowMs - prev.first).toDouble() / 1000.0
        if (elapsedSec < 0.25) {
            val existing = activeTransferMap[transferId]
            return (existing?.speedBytesPerSec ?: 0.0) to (existing?.etaSeconds ?: 0.0)
        }
        val deltaBytes = (bytesTransferred - prev.second).coerceAtLeast(0L)
        progressSamples[transferId] = nowMs to bytesTransferred
        val instantSpeed = deltaBytes.toDouble() / elapsedSec
        val priorSpeed = activeTransferMap[transferId]?.speedBytesPerSec ?: instantSpeed
        val smoothed = if (priorSpeed > 0.0) (priorSpeed * 0.6 + instantSpeed * 0.4) else instantSpeed
        val remaining = (totalBytes - bytesTransferred).coerceAtLeast(0L)
        val eta = if (smoothed > 10.0) remaining.toDouble() / smoothed else 0.0
        return smoothed to eta
    }

    private fun publishActiveTransfers() {
        _uiState.update { it.copy(activeTransfers = activeTransferMap.values.toList()) }
    }

    private fun filterAndSortPeers(peers: List<PeerItem>, query: String): List<PeerItem> {
        val needle = query.trim().lowercase()
        val filtered = if (needle.isEmpty()) {
            peers
        } else {
            peers.filter { peer ->
                peer.displayName.lowercase().contains(needle) ||
                    peer.hostName.lowercase().contains(needle) ||
                    peer.os.lowercase().contains(needle) ||
                    peer.ipAddresses.any { it.contains(needle) }
            }
        }
        return filtered.sortedWith(
            compareByDescending<PeerItem> { it.online }
                .thenBy { it.displayName.lowercase() }
        )
    }

    companion object {
        private const val MAX_PENDING_APPROVALS = 3
    }
}
