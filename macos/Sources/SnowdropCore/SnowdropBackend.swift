import Foundation

public enum SnowdropBackendError: Error, LocalizedError, Sendable {
    case initializationFailed(code: Int)

    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let code):
            "Failed to initialize backend engine (code \(code))"
        }
    }
}

public protocol SnowdropBackend: Sendable {
    var events: AsyncStream<BackendEvent> { get }

    func start(dataDirectory: URL, downloadDirectory: URL, deviceName: String) async throws
    func stop() async
    func restart(dataDirectory: URL, downloadDirectory: URL, deviceName: String) async throws
    func sendFile(to peerIP: String, fileURL: URL, transferID: String) async
    func sendBatch(to peerIP: String, batchID: String, items: [BatchManifestItem]) async
    func cancelTransfer(id: String) async
    func resolveApproval(transferID: String, decision: ApprovalDecision) async -> Bool
    func trustedPeers() async -> [TrustedPeerItem]
    func revokeTrustedPeer(nodeID: String) async -> Bool
    func setApprovalConfig(requireApproval: Bool, autoAcceptTrusted: Bool) async
    func setDownloadDirectory(_ directory: URL) async -> Bool
    func signOut() async -> Bool
}
