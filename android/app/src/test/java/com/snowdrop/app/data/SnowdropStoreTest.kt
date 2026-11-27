package com.snowdrop.app.data

import com.snowdrop.app.domain.ApprovalDecision
import com.snowdrop.app.domain.ApprovalRequest
import com.snowdrop.app.domain.EngineStatus
import com.snowdrop.app.domain.PeerItem
import com.snowdrop.app.domain.StagedFile
import com.snowdrop.app.domain.TransferDirection
import com.snowdrop.app.domain.TrustedPeer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SnowdropStoreTest {

    private fun createStore(
        backend: FakeSnowdropBackend = FakeSnowdropBackend(),
        scope: CoroutineScope,
        clockMs: () -> Long = { 1_000L },
        onPersistName: ((String) -> Unit)? = null,
        onApprovalCleared: ((String) -> Unit)? = null,
        onIncomingFileSave: (suspend (String, String) -> String?)? = null,
        onReceivedNotification: ((String, String) -> Unit)? = null
    ): SnowdropStore = SnowdropStore(
        backend = backend,
        dataDir = "/tmp/data",
        downloadDir = "/tmp/dl",
        initialDeviceName = "Pixel 9",
        scope = scope,
        clockMs = clockMs,
        onPersistDeviceName = onPersistName,
        onApprovalNotificationCleared = onApprovalCleared,
        onIncomingFileSave = onIncomingFileSave,
        onTransferReceivedNotification = onReceivedNotification
    )

    @Test
    fun authUrlReflectsNeedsAuthAndClearsOnConnected() = runTest(UnconfinedTestDispatcher()) {
        val backend = FakeSnowdropBackend()
        val store = createStore(backend, backgroundScope)

        store.start()
        backend.emit(BackendEvent.AuthRequired("https://login.tailscale.com/a/123"))
        assertEquals(EngineStatus.NeedsAuth("https://login.tailscale.com/a/123"), store.uiState.value.status)

        backend.emit(BackendEvent.StatusChanged(code = 2, message = "Starting"))
        assertEquals(EngineStatus.NeedsAuth("https://login.tailscale.com/a/123"), store.uiState.value.status)

        backend.emit(BackendEvent.StatusChanged(code = 3, message = "Connected"))
        assertEquals(EngineStatus.Connected, store.uiState.value.status)
    }

    @Test
    fun renameDevicePersistsAndRestartsWhileIgnoringBlankOrUnchanged() = runTest(UnconfinedTestDispatcher()) {
        val backend = FakeSnowdropBackend()
        var persisted: String? = null
        val store = createStore(backend, backgroundScope, onPersistName = { persisted = it })
        store.start()

        store.renameDevice("   ")
        store.renameDevice("Pixel 9")
        assertEquals(0, backend.restartCount)
        assertNull(persisted)

        store.renameDevice("Work Pixel")
        assertEquals("Work Pixel", store.uiState.value.deviceName)
        assertEquals("Work Pixel", persisted)
        assertEquals(1, backend.restartCount)
    }

    @Test
    fun signOutClearsPeersOnSuccessAndReportsErrorOnFailure() = runTest(UnconfinedTestDispatcher()) {
        val backend = FakeSnowdropBackend()
        val store = createStore(backend, backgroundScope)
        store.start()
        backend.emit(BackendEvent.PeersUpdated(listOf(PeerItem("1", "mac", online = true))))

        backend.signOutResult = false
        store.signOut()
        assertEquals("Unable to sign out", store.uiState.value.lastError)
        assertEquals(1, store.uiState.value.peers.size)

        backend.signOutResult = true
        store.signOut()
        assertNull(store.uiState.value.lastError)
        assertTrue(store.uiState.value.peers.isEmpty())
        assertEquals(EngineStatus.NeedsAuth(""), store.uiState.value.status)
    }

    @Test
    fun peerSortingAndSearchFilteringWorks() = runTest(UnconfinedTestDispatcher()) {
        val backend = FakeSnowdropBackend()
        val store = createStore(backend, backgroundScope)
        store.start()

        backend.emit(
            BackendEvent.PeersUpdated(
                listOf(
                    PeerItem("1", "z-offline", os = "linux", online = false),
                    PeerItem("2", "macbook", os = "darwin", ipAddresses = listOf("100.64.0.2"), online = true),
                    PeerItem("3", "alpha-pc", os = "windows", ipAddresses = listOf("100.64.0.3"), online = true)
                )
            )
        )

        assertEquals(listOf("alpha-pc", "macbook", "z-offline"), store.uiState.value.filteredPeers.map { it.displayName })

        store.setSearchQuery("darwin")
        assertEquals(listOf("macbook"), store.uiState.value.filteredPeers.map { it.displayName })

        store.setSearchQuery("")
        assertEquals(3, store.uiState.value.filteredPeers.size)
    }

    @Test
    fun singleBatchAndDirectSendWorkAndRemoveClearStaging() = runTest(UnconfinedTestDispatcher()) {
        val backend = FakeSnowdropBackend()
        val store = createStore(backend, backgroundScope)
        val onlinePeer = PeerItem("p1", "macbook", ipAddresses = listOf("100.64.0.2"), online = true)
        val f1 = StagedFile("content://1", "a.txt", 500)
        val f2 = StagedFile("content://2", "b.txt", 1000)

        store.stageFiles(listOf(f1, f2))
        store.removeStagedFile("content://1")
        assertEquals(listOf(f2), store.uiState.value.stagedFiles)

        // Single send consumes staging
        store.sendStagedFiles(onlinePeer)
        assertEquals("100.64.0.2" to f2, backend.lastSentFile)
        assertTrue(store.uiState.value.stagedFiles.isEmpty())

        // Direct batch send does not disturb staged files
        store.stageFiles(listOf(f1))
        store.sendDirectFiles(onlinePeer, listOf(f1, f2))
        assertEquals("100.64.0.2" to listOf(f1, f2), backend.lastSentBatch)
        assertEquals(listOf(f1), store.uiState.value.stagedFiles)

        store.clearStagedFiles()
        assertTrue(store.uiState.value.stagedFiles.isEmpty())
    }

    @Test
    fun concurrentTransfersComputeSpeedAndEta() = runTest(UnconfinedTestDispatcher()) {
        var now = 1_000L
        val backend = FakeSnowdropBackend()
        val store = createStore(backend, backgroundScope, clockMs = { now })
        store.start()

        store.apply(BackendEvent.Progress("tx-a", 0, 10_000))
        now = 2_000L
        store.apply(BackendEvent.Progress("tx-a", 5_000, 10_000))
        store.apply(BackendEvent.Progress("tx-b", 250, 2_000))

        assertEquals(2, store.uiState.value.activeTransfers.size)
        val txA = store.uiState.value.activeTransfers.first { it.id == "tx-a" }
        assertTrue(txA.speedBytesPerSec > 0.0)
        assertTrue(txA.etaSeconds > 0.0)

        store.apply(BackendEvent.TransferCompleted("tx-a", success = true, detail = ""))
        assertEquals(listOf("tx-b"), store.uiState.value.activeTransfers.map { it.id })
        assertEquals(1, store.uiState.value.recentTransfers.size)
    }

    @Test
    fun approvalQueueCapsAtThreeClearsNotificationAndUpdatesTrust() = runTest(UnconfinedTestDispatcher()) {
        val backend = FakeSnowdropBackend()
        backend.trustedList = listOf(TrustedPeer("n2", "MacBook", autoAccept = true))
        val cleared = mutableListOf<String>()
        val store = createStore(backend, backgroundScope, onApprovalCleared = { cleared.add(it) })
        store.start()

        for (i in 1..4) {
            store.apply(
                BackendEvent.IncomingApproval(
                    ApprovalRequest("tx-$i", "n$i", "Sender $i", "doc$i.pdf", 1024L * i)
                )
            )
        }

        assertEquals(listOf("tx-2", "tx-3", "tx-4"), store.uiState.value.pendingApprovals.map { it.transferId })

        store.apply(BackendEvent.ApprovalDismissed("tx-3", "timeout"))
        assertEquals(listOf("tx-2", "tx-4"), store.uiState.value.pendingApprovals.map { it.transferId })
        assertTrue(cleared.contains("tx-3"))

        store.resolveApproval("tx-2", ApprovalDecision.ALWAYS_TRUST)
        assertEquals(listOf("tx-4"), store.uiState.value.pendingApprovals.map { it.transferId })
        assertEquals(1, store.uiState.value.trustedPeers.size)

        store.revokeTrustedPeer("n2")
        assertTrue(store.uiState.value.trustedPeers.isEmpty())
    }

    @Test
    fun batchSavedUriAndHistoryManagementWorkCleanly() = runTest(UnconfinedTestDispatcher()) {
        val backend = FakeSnowdropBackend()
        val notified = mutableListOf<Pair<String, String>>()
        val store = createStore(
            backend = backend,
            scope = backgroundScope,
            onIncomingFileSave = { _, path -> "content://media/downloads/${path.substringAfterLast('/')}" },
            onReceivedNotification = { name, uri -> notified.add(name to uri) }
        )
        store.start()

        store.apply(BackendEvent.BatchProgress("b-1", 1, 2, "one.png", 100, 100, 100, 200))
        store.apply(BackendEvent.BatchFileReceived("b-1", 1, 2, "one.png", "/tmp/one.png"))
        store.apply(BackendEvent.BatchFileReceived("b-1", 2, 2, "two.png", "/tmp/two.png"))
        store.apply(BackendEvent.TransferCompleted("b-1", success = true, detail = ""))

        assertEquals(2, notified.size)
        val completed = store.uiState.value.recentTransfers.single()
        assertEquals("content://media/downloads/two.png", completed.destinationUriString)

        store.removeRecentTransfer("b-1")
        assertTrue(store.uiState.value.recentTransfers.isEmpty())
    }

    @Test
    fun incomingMetadataFidelityPreservedAcrossProgressAndComplete() = runTest(UnconfinedTestDispatcher()) {
        val backend = FakeSnowdropBackend()
        val store = createStore(backend, backgroundScope)
        store.start()

        store.apply(
            BackendEvent.IncomingApproval(
                ApprovalRequest("rx-9", "node-9", "Alice Mac", "notes.txt", 4096L)
            )
        )
        store.apply(BackendEvent.Progress("rx-9", 2048L, 4096L))

        val active = store.uiState.value.activeTransfers.single()
        assertEquals("Alice Mac", active.peerName)
        assertEquals("notes.txt", active.fileName)
        assertEquals(TransferDirection.INCOMING, active.direction)

        store.apply(BackendEvent.TransferCompleted("rx-9", success = true, detail = "/tmp/notes.txt"))
        val recent = store.uiState.value.recentTransfers.single()
        assertEquals("Alice Mac", recent.peerName)
        assertEquals("notes.txt", recent.fileName)
        assertTrue(recent.isSuccess)
    }

    @Test
    fun stagingDeduplicatesAndErrorBannerDismisses() = runTest(UnconfinedTestDispatcher()) {
        val backend = FakeSnowdropBackend()
        val store = createStore(backend, backgroundScope)

        val f1 = StagedFile("content://1", "photo.jpg", 1200)
        val f2 = StagedFile("content://2", "video.mp4", 4800)
        assertEquals(2, store.stageFiles(listOf(f1, f1, f2)))
        assertEquals(6000L, store.uiState.value.stagedTotalBytes)

        store.reportError("Disk full")
        assertEquals("Disk full", store.uiState.value.lastError)
        store.dismissError()
        assertNull(store.uiState.value.lastError)
    }
}
