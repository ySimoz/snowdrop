import CSnowdrop
import Foundation
import os
import SnowdropCore

private final class CallbackBridge: Sendable {
    static let shared = CallbackBridge()

    private struct State {
        var continuation: AsyncStream<BackendEvent>.Continuation?
        var lastProgressTick: [String: ContinuousClock.Instant] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let throttleInterval: Duration = .milliseconds(50)

    func attach(continuation: AsyncStream<BackendEvent>.Continuation) {
        state.withLock {
            $0.continuation = continuation
            $0.lastProgressTick.removeAll()
        }
    }

    func yield(_ event: BackendEvent) {
        let cont = state.withLock { $0.continuation }
        cont?.yield(event)
    }

    func yieldThrottledProgress(transferID: String, current: Int64, total: Int64) {
        let shouldEmit = state.withLock { s -> Bool in
            let now = ContinuousClock.now
            let isEdge = current == 0 || (total > 0 && current >= total)
            if isEdge {
                s.lastProgressTick[transferID] = now
                return true
            }
            if let last = s.lastProgressTick[transferID], now - last < throttleInterval {
                return false
            }
            s.lastProgressTick[transferID] = now
            return true
        }
        if shouldEmit {
            yield(.progress(transferID: transferID, current: current, total: total))
        }
    }

    func yieldThrottledBatchProgress(
        batchID: String,
        fileIndex: Int,
        totalFiles: Int,
        fileName: String,
        fileCurrent: Int64,
        fileTotal: Int64,
        batchCurrent: Int64,
        batchTotal: Int64
    ) {
        let shouldEmit = state.withLock { s -> Bool in
            let now = ContinuousClock.now
            let isEdge = batchCurrent == 0 || (batchTotal > 0 && batchCurrent >= batchTotal) || fileCurrent == 0 || (fileTotal > 0 && fileCurrent >= fileTotal)
            if isEdge {
                s.lastProgressTick[batchID] = now
                return true
            }
            if let last = s.lastProgressTick[batchID], now - last < throttleInterval {
                return false
            }
            s.lastProgressTick[batchID] = now
            return true
        }
        if shouldEmit {
            yield(
                .batchProgress(
                    batchID: batchID,
                    fileIndex: fileIndex,
                    totalFiles: totalFiles,
                    fileName: fileName,
                    fileCurrent: fileCurrent,
                    fileTotal: fileTotal,
                    batchCurrent: batchCurrent,
                    batchTotal: batchTotal
                )
            )
        }
    }

    func clearProgressTick(for transferID: String) {
        state.withLock {
            _ = $0.lastProgressTick.removeValue(forKey: transferID)
        }
    }
}

private func onCStatus(_ status: Int32, _ messagePtr: UnsafePointer<CChar>?) {
    let message = messagePtr.map { String(cString: $0) } ?? ""
    CallbackBridge.shared.yield(.statusChanged(code: Int(status), message: message))
}

private func onCAuthRequired(_ authURLPtr: UnsafePointer<CChar>?) {
    let url = authURLPtr.map { String(cString: $0) } ?? ""
    CallbackBridge.shared.yield(.authRequired(url: url))
}

private func onCPeersUpdated(_ peersJSONPtr: UnsafePointer<CChar>?) {
    let json = peersJSONPtr.map { String(cString: $0) } ?? "[]"
    guard let data = json.data(using: .utf8),
          let decoded = try? JSONDecoder().decode([PeerItem].self, from: data) else {
        return
    }
    CallbackBridge.shared.yield(.peersUpdated(decoded))
}

private func onCProgress(_ transferIDPtr: UnsafePointer<CChar>?, _ current: Int64, _ total: Int64) {
    let id = transferIDPtr.map { String(cString: $0) } ?? ""
    CallbackBridge.shared.yieldThrottledProgress(transferID: id, current: current, total: total)
}

private func onCTransferComplete(_ transferIDPtr: UnsafePointer<CChar>?, _ success: Bool, _ detailPtr: UnsafePointer<CChar>?) {
    let id = transferIDPtr.map { String(cString: $0) } ?? ""
    let detail = detailPtr.map { String(cString: $0) } ?? ""
    CallbackBridge.shared.clearProgressTick(for: id)
    CallbackBridge.shared.yield(.transferComplete(transferID: id, success: success, detail: detail))
}

private func onCApproval(
    _ transferIDPtr: UnsafePointer<CChar>?,
    _ nodeIDPtr: UnsafePointer<CChar>?,
    _ senderNamePtr: UnsafePointer<CChar>?,
    _ fileNamePtr: UnsafePointer<CChar>?,
    _ fileSize: Int64
) {
    let req = IncomingApprovalRequest(
        id: transferIDPtr.map { String(cString: $0) } ?? "",
        nodeID: nodeIDPtr.map { String(cString: $0) } ?? "",
        senderName: senderNamePtr.map { String(cString: $0) } ?? "",
        fileName: fileNamePtr.map { String(cString: $0) } ?? "",
        fileSize: fileSize
    )
    CallbackBridge.shared.yield(.incomingApproval(req))
}

private func onCBatchProgress(
    _ batchIDPtr: UnsafePointer<CChar>?,
    _ fileIndex: Int32,
    _ totalFiles: Int32,
    _ fileNamePtr: UnsafePointer<CChar>?,
    _ fileCur: Int64,
    _ fileTotal: Int64,
    _ batchCur: Int64,
    _ batchTotal: Int64
) {
    let id = batchIDPtr.map { String(cString: $0) } ?? ""
    let name = fileNamePtr.map { String(cString: $0) } ?? ""
    CallbackBridge.shared.yieldThrottledBatchProgress(
        batchID: id,
        fileIndex: Int(fileIndex),
        totalFiles: Int(totalFiles),
        fileName: name,
        fileCurrent: fileCur,
        fileTotal: fileTotal,
        batchCurrent: batchCur,
        batchTotal: batchTotal
    )
}

private func onCBatchFileReceived(
    _ batchIDPtr: UnsafePointer<CChar>?,
    _ fileIndex: Int32,
    _ totalFiles: Int32,
    _ fileNamePtr: UnsafePointer<CChar>?,
    _ filePathPtr: UnsafePointer<CChar>?
) {
    let id = batchIDPtr.map { String(cString: $0) } ?? ""
    let name = fileNamePtr.map { String(cString: $0) } ?? ""
    let path = filePathPtr.map { String(cString: $0) } ?? ""
    CallbackBridge.shared.yield(
        .batchFileReceived(
            batchID: id,
            fileIndex: Int(fileIndex),
            totalFiles: Int(totalFiles),
            fileName: name,
            filePath: path
        )
    )
}

private func onCApprovalDismissed(_ transferIDPtr: UnsafePointer<CChar>?, _ reasonPtr: UnsafePointer<CChar>?) {
    let id = transferIDPtr.map { String(cString: $0) } ?? ""
    let reason = reasonPtr.map { String(cString: $0) } ?? ""
    CallbackBridge.shared.yield(.approvalDismissed(transferID: id, reason: reason))
}

public actor LiveSnowdropBackend: SnowdropBackend {
    public nonisolated let events: AsyncStream<BackendEvent>
    private var isRunning = false
    private var callbacksRegistered = false

    public init() {
        var captured: AsyncStream<BackendEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        if let captured {
            CallbackBridge.shared.attach(continuation: captured)
        }
    }

    public func start(dataDirectory: URL, downloadDirectory: URL, deviceName: String) async throws {
        guard !isRunning else { return }

        registerCallbacksIfNeeded()

        let code = dataDirectory.path.withCString { cData in
            downloadDirectory.path.withCString { cDownloads in
                deviceName.withCString { cName in
                    Int(StartEngine(cData, cDownloads, cName))
                }
            }
        }
        guard code == 0 else {
            throw SnowdropBackendError.initializationFailed(code: code)
        }
        isRunning = true
    }

    public func stop() async {
        guard isRunning else { return }
        StopEngine()
        isRunning = false
    }

    public func restart(dataDirectory: URL, downloadDirectory: URL, deviceName: String) async throws {
        await stop()
        try await start(dataDirectory: dataDirectory, downloadDirectory: downloadDirectory, deviceName: deviceName)
    }

    public func sendFile(to peerIP: String, fileURL: URL, transferID: String) async {
        peerIP.withCString { cIP in
            fileURL.path.withCString { cPath in
                transferID.withCString { cID in
                    SendFile(cIP, cPath, cID)
                }
            }
        }
    }

    public func sendBatch(to peerIP: String, batchID: String, items: [BatchManifestItem]) async {
        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else {
            CallbackBridge.shared.yield(
                .transferComplete(transferID: batchID, success: false, detail: "Failed to encode batch manifest")
            )
            return
        }
        peerIP.withCString { cIP in
            batchID.withCString { cBatchID in
                json.withCString { cJSON in
                    SendBatch(cIP, cBatchID, cJSON)
                }
            }
        }
    }

    public func cancelTransfer(id: String) async {
        id.withCString { cID in
            CancelTransfer(cID)
        }
    }

    public func resolveApproval(transferID: String, decision: ApprovalDecision) async -> Bool {
        transferID.withCString { cID in
            ResolveTransferApproval(cID, decision.rawValue)
        }
    }

    public func trustedPeers() async -> [TrustedPeerItem] {
        guard let ptr = GetTrustedPeers() else { return [] }
        defer { FreeCString(ptr) }
        let json = String(cString: ptr)
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([TrustedPeerItem].self, from: data) else {
            return []
        }
        return list
    }

    public func revokeTrustedPeer(nodeID: String) async -> Bool {
        nodeID.withCString { cNodeID in
            RevokeTrusted(cNodeID)
        }
    }

    public func setApprovalConfig(requireApproval: Bool, autoAcceptTrusted: Bool) async {
        SetApprovalConfig(requireApproval, autoAcceptTrusted)
    }

    public func setDownloadDirectory(_ directory: URL) async -> Bool {
        directory.path.withCString { cPath in
            SetDownloadDir(cPath)
        }
    }

    public func signOut() async -> Bool {
        SnowdropSignOut()
    }

    private func registerCallbacksIfNeeded() {
        guard !callbacksRegistered else { return }
        callbacksRegistered = true
        RegisterCallbacks(onCStatus, onCAuthRequired, onCPeersUpdated, onCProgress, onCTransferComplete)
        RegisterApprovalCallback(onCApproval)
        RegisterBatchProgressCallback(onCBatchProgress)
        RegisterBatchFileReceivedCallback(onCBatchFileReceived)
        RegisterApprovalDismissedCallback(onCApprovalDismissed)
    }
}
