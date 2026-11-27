import Foundation
import Testing
@testable import SnowdropCore

@Suite("SnowdropStore state transitions")
struct SnowdropStoreTests {
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suite = "com.snowdrop.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @MainActor
    @Test
    func statusAndPeersUpdate() async {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SnowdropStore(
            backend: mock,
            dataDirectory: URL(fileURLWithPath: "/tmp/snowdrop-test-data"),
            downloadDirectory: URL(fileURLWithPath: "/tmp/snowdrop-test-dl"),
            deviceName: "TestMac",
            userDefaults: defaults
        )

        await store.start()
        #expect(store.status == .connecting)

        await store.apply(.authRequired(url: "https://login.tailscale.com/a/123"))
        #expect(store.status == .needsAuth(url: "https://login.tailscale.com/a/123"))

        await store.apply(.statusChanged(code: 3, message: "connected"))
        #expect(store.status == .connected)

        let peer = PeerItem(
            id: "node-1",
            hostName: "pixel-9",
            customDisplayName: "Pixel 9",
            os: "android",
            ipAddresses: ["100.64.0.2"],
            online: true
        )
        await store.apply(.peersUpdated([peer]))
        #expect(store.peers == [peer])

        await store.shutdown()
        #expect(store.status == .disconnected)
        #expect(store.peers.isEmpty)
    }

    @MainActor
    @Test
    func concurrentTransfersAreTrackedIndependently() async {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SnowdropStore(backend: mock, userDefaults: defaults)

        await store.apply(.progress(transferID: "tx-1", current: 50, total: 100))
        await store.apply(.progress(transferID: "tx-2", current: 20, total: 200))

        #expect(store.activeTransfers.count == 2)
        #expect(store.activeTransfers["tx-1"]?.bytesTransferred == 50)
        #expect(store.activeTransfers["tx-2"]?.bytesTransferred == 20)

        await store.apply(.transferComplete(transferID: "tx-1", success: true, detail: "/tmp/a.txt"))
        #expect(store.activeTransfers.count == 1)
        #expect(store.activeTransfers["tx-2"] != nil)
        #expect(store.recentTransfers.first?.id == "tx-1")
        #expect(store.recentTransfers.first?.destinationURLs == [URL(fileURLWithPath: "/tmp/a.txt")])
    }

    @MainActor
    @Test
    func approvalQueueAndDismissal() async {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SnowdropStore(backend: mock, userDefaults: defaults)

        let req1 = IncomingApprovalRequest(id: "a1", nodeID: "n1", senderName: "Phone", fileName: "one.jpg", fileSize: 1024)
        let req2 = IncomingApprovalRequest(id: "a2", nodeID: "n2", senderName: "Tablet", fileName: "two.jpg", fileSize: 2048)

        await store.apply(.incomingApproval(req1))
        await store.apply(.incomingApproval(req2))
        #expect(store.pendingApprovals.count == 2)

        await store.apply(.approvalDismissed(transferID: "a1", reason: "timeout"))
        #expect(store.pendingApprovals == [req2])

        await store.resolveApproval(req2, decision: .alwaysTrust)
        #expect(store.pendingApprovals.isEmpty)
        let recorded = await mock.resolvedApprovals
        #expect(recorded.count == 1)
        #expect(recorded.first?.0 == "a2")
        #expect(recorded.first?.1 == .alwaysTrust)
    }

    @MainActor
    @Test
    func signOutClearsPeersAndAuth() async {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SnowdropStore(backend: mock, userDefaults: defaults)

        await store.apply(.peersUpdated([
            PeerItem(id: "n1", hostName: "phone", os: "android", ipAddresses: ["100.64.0.2"], online: true)
        ]))
        await store.signOut()

        #expect(store.peers.isEmpty)
        #expect(store.status == .needsAuth(url: ""))
    }

    @MainActor
    @Test
    func deviceNameLoadsAndPersistsOnRenameAndRestartsEngine() async {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("PersistedMac", forKey: "SnowdropDeviceName")
        let store = SnowdropStore(backend: mock, userDefaults: defaults)
        #expect(store.deviceName == "PersistedMac")

        let renamed = await store.renameDevice(to: "  StudioMac  ")
        #expect(renamed)
        #expect(store.deviceName == "StudioMac")
        #expect(defaults.string(forKey: "SnowdropDeviceName") == "StudioMac")
        #expect(await mock.restartCount == 1)
        #expect(await mock.lastDeviceName == "StudioMac")
    }

    @MainActor
    @Test
    func renameRejectsEmptyWhitespaceAndUnchangedName() async {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SnowdropStore(backend: mock, deviceName: "MyMac", userDefaults: defaults)

        #expect(await store.renameDevice(to: "   ") == false)
        #expect(await store.renameDevice(to: "MyMac") == false)
        #expect(store.deviceName == "MyMac")
        #expect(await mock.restartCount == 0)
    }

    @MainActor
    @Test
    func authURLReflectsNeedsAuthAndClearsOnConnected() async {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SnowdropStore(backend: mock, userDefaults: defaults)
        #expect(store.authURL == nil)

        await store.apply(.authRequired(url: "https://login.tailscale.com/a/abc"))
        #expect(store.authURL == URL(string: "https://login.tailscale.com/a/abc"))

        await store.apply(.statusChanged(code: 2, message: "starting"))
        #expect(store.authURL == URL(string: "https://login.tailscale.com/a/abc"))

        await store.apply(.statusChanged(code: 3, message: "connected"))
        #expect(store.authURL == nil)
    }

    @MainActor
    @Test
    func signOutFailureSurfacesErrorAndCanBeDismissed() async {
        let mock = MockSnowdropBackend()
        await mock.setSignOutShouldSucceed(false)
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SnowdropStore(backend: mock, userDefaults: defaults)
        await store.signOut()

        #expect(store.lastError == "Unable to sign out")
        store.dismissError()
        #expect(store.lastError == nil)
    }

    @MainActor
    @Test
    func sortedFilteredPeersAndOnlineCount() async {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SnowdropStore(backend: mock, userDefaults: defaults)
        let peers = [
            PeerItem(id: "1", hostName: "z-offline", customDisplayName: "Zed Tablet", os: "android", ipAddresses: ["100.64.0.4"], online: false),
            PeerItem(id: "2", hostName: "b-online", customDisplayName: "Beta Phone", os: "android", ipAddresses: ["100.64.0.2"], online: true),
            PeerItem(id: "3", hostName: "a-online", customDisplayName: "Alpha Mac", os: "darwin", ipAddresses: ["100.64.0.1"], online: true),
            PeerItem(id: "4", hostName: "a-offline", customDisplayName: "Archive PC", os: "windows", ipAddresses: ["100.64.0.3"], online: false)
        ]

        await store.apply(.peersUpdated(peers))
        #expect(store.onlinePeerCount == 2)
        #expect(store.sortedFilteredPeers.map(\.displayName) == ["Alpha Mac", "Beta Phone", "Archive PC", "Zed Tablet"])

        store.searchText = "android"
        #expect(store.sortedFilteredPeers.map(\.displayName) == ["Beta Phone", "Zed Tablet"])

        store.searchText = "alpha"
        #expect(store.sortedFilteredPeers.map(\.displayName) == ["Alpha Mac"])

        store.searchText = "b-online"
        #expect(store.sortedFilteredPeers.map(\.displayName) == ["Beta Phone"])

        // Tie-breaker by id when displayName matches
        let tied = [
            PeerItem(id: "id-b", hostName: "same", customDisplayName: "Same", os: "darwin", online: true),
            PeerItem(id: "id-a", hostName: "same", customDisplayName: "Same", os: "darwin", online: true)
        ]
        await store.apply(.peersUpdated(tied))
        store.searchText = "   "
        #expect(store.sortedFilteredPeers.map(\.id) == ["id-a", "id-b"])

        store.searchText = "nonexistent-device"
        #expect(store.sortedFilteredPeers.isEmpty)

        // Display name fallback chain: customDisplayName -> hostName -> dnsName -> id
        #expect(PeerItem(id: "n1", hostName: "host", customDisplayName: "Custom", dnsName: "dns", online: true).displayName == "Custom")
        #expect(PeerItem(id: "n2", hostName: "host", customDisplayName: "", dnsName: "dns", online: true).displayName == "host")
        #expect(PeerItem(id: "n3", hostName: "", customDisplayName: nil, dnsName: "dns.ts.net", online: true).displayName == "dns.ts.net")
        #expect(PeerItem(id: "n4", hostName: "", customDisplayName: nil, dnsName: "", online: true).displayName == "n4")
    }

    @MainActor
    @Test
    func stageFilesDeduplicatesRemovesClearsAndFlagsRejected() throws {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileA = tempDir.appendingPathComponent("alpha.txt")
        let fileB = tempDir.appendingPathComponent("beta.bin")
        try Data("hello".utf8).write(to: fileA)
        try Data(repeating: 7, count: 12).write(to: fileB)

        let store = SnowdropStore(backend: mock, userDefaults: defaults)
        let added = store.stageFiles([fileA, fileA, fileB, URL(fileURLWithPath: "/etc/hosts")])

        #expect(added == 2)
        #expect(store.stagedFiles.count == 2)
        #expect(store.stagedTotalBytes == 17)
        #expect(store.stagedSummaryText == "2 files staged")
        #expect(store.lastError == "Skipped 1 unsupported or protected item")

        store.removeStagedFile(store.stagedFiles[0])
        #expect(store.stagedFiles.count == 1)
        #expect(store.stagedSummaryText == "beta.bin")

        store.clearStagedFiles()
        #expect(store.stagedFiles.isEmpty)
        #expect(store.stagedTotalBytes == 0)
    }

    @MainActor
    @Test
    func singleAndBatchSendAndGuardsAndCancellation() async throws {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-send-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let f1 = tempDir.appendingPathComponent("doc1.txt")
        let f2 = tempDir.appendingPathComponent("doc2.txt")
        try Data("one".utf8).write(to: f1)
        try Data("two2".utf8).write(to: f2)

        let store = SnowdropStore(backend: mock, userDefaults: defaults)
        let offlinePeer = PeerItem(id: "off", hostName: "off", os: "android", ipAddresses: ["100.64.0.9"], online: false)
        let noIPPeer = PeerItem(id: "noip", hostName: "noip", os: "android", ipAddresses: [], online: true)
        let onlinePeer = PeerItem(id: "ok", hostName: "pixel", customDisplayName: "Pixel 9", os: "android", ipAddresses: ["100.64.0.2"], online: true)

        // Guard: offline / missing IP preserves staged files
        store.stageFiles([f1])
        #expect(await store.sendStagedFiles(to: offlinePeer) == false)
        #expect(await store.sendStagedFiles(to: noIPPeer) == false)
        #expect(store.stagedFiles.count == 1)

        // Single send
        #expect(await store.sendStagedFiles(to: onlinePeer) == true)
        #expect(store.stagedFiles.isEmpty)
        #expect(store.activeTransfers.count == 1)
        let sentSingles = await mock.sentFiles
        #expect(sentSingles.count == 1)
        #expect(sentSingles.first?.peerIP == "100.64.0.2")

        // Cancellation
        await store.cancelAllActiveTransfers()
        let cancelled = await mock.cancelledTransferIDs
        #expect(cancelled.count == 1)
        #expect(cancelled.first == sentSingles.first?.transferID)

        if let id = sentSingles.first?.transferID {
            await store.apply(.transferComplete(transferID: id, success: true, detail: ""))
        }
        #expect(store.activeTransfers.isEmpty)

        // Batch send
        store.stageFiles([f1, f2])
        #expect(await store.sendStagedFiles(to: onlinePeer) == true)
        #expect(store.stagedFiles.isEmpty)
        let sentBatches = await mock.sentBatches
        #expect(sentBatches.count == 1)
        #expect(sentBatches.first?.items.count == 2)
        if let batchID = sentBatches.first?.batchID {
            #expect(store.activeTransfers[batchID]?.isBatch == true)
            #expect(store.activeTransfers[batchID]?.totalFiles == 2)
        }
    }

    @MainActor
    @Test
    func approvalConfigPersistsAndTrustCircleUpdates() async {
        let mock = MockSnowdropBackend()
        let trusted = TrustedPeerItem(node_id: "node-pixel", device_name: "Pixel 9", auto_accept: true)
        await mock.setMockTrustedPeers([trusted])

        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SnowdropStore(backend: mock, userDefaults: defaults)
        #expect(store.requireApproval == true)
        #expect(store.autoAcceptTrusted == true)

        await store.updateApprovalConfig(requireApproval: false, autoAcceptTrusted: false)
        #expect(defaults.bool(forKey: "SnowdropRequireApproval") == false)
        #expect(defaults.bool(forKey: "SnowdropAutoAcceptTrusted") == false)

        let reloaded = SnowdropStore(backend: mock, userDefaults: defaults)
        #expect(reloaded.requireApproval == false)
        #expect(reloaded.autoAcceptTrusted == false)

        let req = IncomingApprovalRequest(id: "app-1", nodeID: "node-pixel", senderName: "Pixel 9", fileName: "photo.jpg", fileSize: 4096)
        await reloaded.apply(.incomingApproval(req))
        await reloaded.resolveApproval(id: "app-1", decision: .alwaysTrust)
        #expect(reloaded.trustedPeers == [trusted])

        await reloaded.revokeTrustedPeer(nodeID: "node-pixel")
        #expect(reloaded.trustedPeers.isEmpty)
        #expect(await mock.revokedPeers == ["node-pixel"])

        #expect(ApprovalDecision(notificationActionIdentifier: "ACTION_ACCEPT") == .accept)
        #expect(ApprovalDecision(notificationActionIdentifier: "ACTION_TRUST") == .alwaysTrust)
        #expect(ApprovalDecision(notificationActionIdentifier: "ACTION_DECLINE") == .decline)
        #expect(ApprovalDecision(notificationActionIdentifier: "OTHER") == nil)
    }

    @MainActor
    @Test
    func incomingMetadataFidelityBatchRevealAndHistoryManagement() async throws {
        let mock = MockSnowdropBackend()
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let dlDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-reveal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dlDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dlDir) }

        let savedSingle = dlDir.appendingPathComponent("report (1).pdf")
        let savedBatch1 = dlDir.appendingPathComponent("a.png")
        let savedBatch2 = dlDir.appendingPathComponent("b.png")
        try Data("pdf".utf8).write(to: savedSingle)
        try Data("a".utf8).write(to: savedBatch1)
        try Data("b".utf8).write(to: savedBatch2)

        let store = SnowdropStore(backend: mock, downloadDirectory: dlDir, userDefaults: defaults)

        // Single incoming transfer preserves senderName and renames to saved path basename
        let singleReq = IncomingApprovalRequest(id: "in-1", nodeID: "n1", senderName: "Pixel 9", fileName: "report.pdf", fileSize: 3)
        await store.apply(.incomingApproval(singleReq))
        await store.resolveApproval(id: "in-1", decision: .accept)
        await store.apply(.progress(transferID: "in-1", current: 1, total: 3))
        #expect(store.activeTransfers["in-1"]?.peerName == "Pixel 9")
        #expect(store.activeTransfers["in-1"]?.fileName == "report.pdf")

        await store.apply(.transferComplete(transferID: "in-1", success: true, detail: savedSingle.path))
        let singleRecent = try #require(store.recentTransfers.first)
        #expect(singleRecent.peerName == "Pixel 9")
        #expect(singleRecent.fileName == "report (1).pdf")
        #expect(store.revealURLs(for: singleRecent) == [savedSingle])

        store.selectedTransferID = singleRecent.id
        #expect(store.selectedRevealableTransfer?.id == singleRecent.id)

        // Batch incoming transfer collects all received URLs
        let batchReq = IncomingApprovalRequest(id: "in-batch", nodeID: "n1", senderName: "Pixel 9", fileName: "2 files", fileSize: 2)
        await store.apply(.incomingApproval(batchReq))
        await store.resolveApproval(id: "in-batch", decision: .accept)
        await store.apply(.batchProgress(batchID: "in-batch", fileIndex: 1, totalFiles: 2, fileName: "a.png", fileCurrent: 1, fileTotal: 1, batchCurrent: 1, batchTotal: 2))
        await store.apply(.batchFileReceived(batchID: "in-batch", fileIndex: 1, totalFiles: 2, fileName: "a.png", filePath: savedBatch1.path))
        await store.apply(.batchFileReceived(batchID: "in-batch", fileIndex: 2, totalFiles: 2, fileName: "b.png", filePath: savedBatch2.path))
        await store.apply(.transferComplete(transferID: "in-batch", success: true, detail: savedBatch2.path))

        let batchRecent = try #require(store.recentTransfers.first)
        #expect(batchRecent.id == "in-batch")
        #expect(store.revealURLs(for: batchRecent) == [savedBatch1, savedBatch2])

        // Partial deletion keeps surviving destination file
        try FileManager.default.removeItem(at: savedBatch1)
        #expect(store.revealURLs(for: batchRecent) == [savedBatch2])

        // Full deletion falls back to downloadDirectory
        try FileManager.default.removeItem(at: savedBatch2)
        #expect(store.revealURLs(for: batchRecent) == [dlDir])

        // 0-byte incoming file completion without prior progress event
        let zeroByteFile = dlDir.appendingPathComponent("empty.txt")
        try Data().write(to: zeroByteFile)
        let zeroReq = IncomingApprovalRequest(id: "in-zero", nodeID: "n1", senderName: "Pixel 9", fileName: "empty.txt", fileSize: 0)
        await store.apply(.incomingApproval(zeroReq))
        await store.resolveApproval(id: "in-zero", decision: .accept)
        await store.apply(.transferComplete(transferID: "in-zero", success: true, detail: zeroByteFile.path))
        #expect(store.recentTransfers.first?.id == "in-zero")
        #expect(store.recentTransfers.first?.destinationURLs == [zeroByteFile])

        // Non-revealable cases: failed incoming, outgoing, and active transfers
        let failReq = IncomingApprovalRequest(id: "in-fail", nodeID: "n1", senderName: "Pixel 9", fileName: "bad.bin", fileSize: 10)
        await store.apply(.incomingApproval(failReq))
        await store.apply(.transferComplete(transferID: "in-fail", success: false, detail: "hash mismatch"))
        #expect(store.recentTransfers.first?.direction == .incoming)
        store.selectedTransferID = "in-fail"
        #expect(store.selectedRevealableTransfer == nil)

        let peer = PeerItem(id: "p1", hostName: "p1", os: "android", ipAddresses: ["100.64.0.2"], online: true)
        store.stageFiles([savedSingle])
        #expect(await store.sendStagedFiles(to: peer) == true)
        if let activeID = store.orderedActiveTransfers.first?.id {
            store.selectedTransferID = activeID
            #expect(store.selectedRevealableTransfer == nil)
            await store.apply(.transferComplete(transferID: activeID, success: true, detail: ""))
            store.selectedTransferID = activeID
            #expect(store.selectedRevealableTransfer == nil)
        }

        // Remove and clear history
        store.removeRecentTransfer(id: "in-batch")
        #expect(store.recentTransfers.contains(where: { $0.id == "in-batch" }) == false)
        store.clearRecentTransfers()
        #expect(store.recentTransfers.isEmpty)
        #expect(store.selectedTransferID == nil)
    }
}
