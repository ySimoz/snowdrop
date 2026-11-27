import Foundation

public actor MockSnowdropBackend: SnowdropBackend {
    public nonisolated let events: AsyncStream<BackendEvent>
    private let continuation: AsyncStream<BackendEvent>.Continuation

    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    public private(set) var restartCount = 0
    public private(set) var signOutCount = 0
    public private(set) var lastDeviceName: String?
    public private(set) var lastDownloadDirectory: URL?
    public private(set) var approvalConfigHistory: [(Bool, Bool)] = []
    public private(set) var resolvedApprovals: [(String, ApprovalDecision)] = []
    public private(set) var revokedPeers: [String] = []
    public private(set) var sentFiles: [(peerIP: String, fileURL: URL, transferID: String)] = []
    public private(set) var sentBatches: [(peerIP: String, batchID: String, items: [BatchManifestItem])] = []
    public private(set) var cancelledTransferIDs: [String] = []
    public var mockTrustedPeers: [TrustedPeerItem] = []
    public var signOutShouldSucceed = true
    public var setDownloadDirectoryShouldSucceed = true

    public init() {
        var capturedContinuation: AsyncStream<BackendEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    public func emit(_ event: BackendEvent) {
        continuation.yield(event)
    }

    public func setMockTrustedPeers(_ peers: [TrustedPeerItem]) {
        mockTrustedPeers = peers
    }

    public func setSignOutShouldSucceed(_ value: Bool) {
        signOutShouldSucceed = value
    }

    public func setDownloadDirectoryShouldSucceed(_ value: Bool) {
        setDownloadDirectoryShouldSucceed = value
    }

    public func start(dataDirectory: URL, downloadDirectory: URL, deviceName: String) async throws {
        startCount += 1
        lastDeviceName = deviceName
        lastDownloadDirectory = downloadDirectory
    }

    public func stop() async {
        stopCount += 1
    }

    public func restart(dataDirectory: URL, downloadDirectory: URL, deviceName: String) async throws {
        restartCount += 1
        stopCount += 1
        startCount += 1
        lastDeviceName = deviceName
        lastDownloadDirectory = downloadDirectory
    }

    public func sendFile(to peerIP: String, fileURL: URL, transferID: String) async {
        sentFiles.append((peerIP, fileURL, transferID))
    }

    public func sendBatch(to peerIP: String, batchID: String, items: [BatchManifestItem]) async {
        sentBatches.append((peerIP, batchID, items))
    }

    public func cancelTransfer(id: String) async {
        cancelledTransferIDs.append(id)
    }

    public func resolveApproval(transferID: String, decision: ApprovalDecision) async -> Bool {
        resolvedApprovals.append((transferID, decision))
        return true
    }

    public func trustedPeers() async -> [TrustedPeerItem] {
        mockTrustedPeers
    }

    public func revokeTrustedPeer(nodeID: String) async -> Bool {
        revokedPeers.append(nodeID)
        mockTrustedPeers.removeAll { $0.node_id == nodeID }
        return true
    }

    public func setApprovalConfig(requireApproval: Bool, autoAcceptTrusted: Bool) async {
        approvalConfigHistory.append((requireApproval, autoAcceptTrusted))
    }

    public func setDownloadDirectory(_ directory: URL) async -> Bool {
        guard setDownloadDirectoryShouldSucceed else { return false }
        lastDownloadDirectory = directory
        return true
    }

    public func signOut() async -> Bool {
        signOutCount += 1
        return signOutShouldSucceed
    }
}
