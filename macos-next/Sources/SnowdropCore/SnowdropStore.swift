import Foundation
import Observation

@MainActor
@Observable
public final class SnowdropStore {
    private static let deviceNameDefaultsKey = "SnowdropDeviceName"
    private static let requireApprovalDefaultsKey = "SnowdropRequireApproval"
    private static let autoAcceptDefaultsKey = "SnowdropAutoAcceptTrusted"

    public private(set) var status: EngineStatus = .disconnected
    public private(set) var peers: [PeerItem] = []
    public private(set) var activeTransfers: [String: TransferItem] = [:]
    public private(set) var recentTransfers: [TransferItem] = []
    public private(set) var pendingApprovals: [IncomingApprovalRequest] = []
    public private(set) var trustedPeers: [TrustedPeerItem] = []
    public private(set) var lastError: String?
    public private(set) var isRestarting = false
    public private(set) var isSigningOut = false

    public var showRenameSheet = false
    public var showFileImporter = false
    public private(set) var stagedFiles: [StagedFileItem] = []
    public var stagedFileURLs: [URL] { stagedFiles.map(\.url) }
    public var selectedSection: NavigationSection = .devices
    public var selectedTransferID: String?
    public var searchText: String = ""
    public var deviceName: String
    public var downloadDirectory: URL
    public var requireApproval: Bool
    public var autoAcceptTrusted: Bool

    public var onIncomingApproval: (@MainActor (IncomingApprovalRequest) -> Void)?
    public var onApprovalCleared: (@MainActor (String) -> Void)?
    public var onTransferCompleted: (@MainActor (TransferItem) -> Void)?
    public var onRequestMainWindow: (@MainActor () -> Void)?

    private let backend: any SnowdropBackend
    private let userDefaults: UserDefaults
    private let dataDirectory: URL
    public let defaultDownloadDirectory: URL
    private let hasExplicitDownloadDirectory: Bool
    private let bookmarkStore: BookmarkStore
    private let securityScopeTracker = SecurityScopedAccessTracker()
    private var eventTask: Task<Void, Never>?
    private var cachedAuthURL: String = ""
    private var isStarted = false
    private var progressSamples: [String: (date: Date, bytes: Int64)] = [:]
    private var incomingMetadata: [String: (senderName: String, fileName: String)] = [:]
    private var batchReceivedURLs: [String: [URL]] = [:]
    private var transferScopedURLs: [String: [URL]] = [:]

    public init(
        backend: any SnowdropBackend,
        dataDirectory: URL? = nil,
        downloadDirectory: URL? = nil,
        deviceName: String? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.backend = backend
        self.userDefaults = userDefaults

        let resolvedData = dataDirectory ?? (
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Snowdrop", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Snowdrop", isDirectory: true)
        )
        self.dataDirectory = resolvedData

        let fallbackDownloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.defaultDownloadDirectory = fallbackDownloads

        let bookmarks = BookmarkStore(userDefaults: userDefaults)
        self.bookmarkStore = bookmarks
        self.hasExplicitDownloadDirectory = downloadDirectory != nil
        self.downloadDirectory = downloadDirectory ?? fallbackDownloads

        let savedName = userDefaults.string(forKey: Self.deviceNameDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let deviceName {
            self.deviceName = deviceName
        } else if let savedName, !savedName.isEmpty {
            self.deviceName = savedName
        } else {
            self.deviceName = Host.current().localizedName ?? "Mac"
        }

        self.requireApproval = (userDefaults.object(forKey: Self.requireApprovalDefaultsKey) as? Bool) ?? true
        self.autoAcceptTrusted = (userDefaults.object(forKey: Self.autoAcceptDefaultsKey) as? Bool) ?? true
    }

    public var authURL: URL? {
        let raw: String
        if case .needsAuth(let url) = status, !url.isEmpty {
            raw = url
        } else {
            raw = cachedAuthURL
        }
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    public var filteredPeers: [PeerItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return peers }
        return peers.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.hostName.localizedCaseInsensitiveContains(query) ||
            $0.os.localizedCaseInsensitiveContains(query)
        }
    }

    public var sortedFilteredPeers: [PeerItem] {
        filteredPeers.sorted { lhs, rhs in
            if lhs.online != rhs.online {
                return lhs.online && !rhs.online
            }
            let cmp = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    public var onlinePeerCount: Int {
        peers.count(where: \.online)
    }

    public func activeTransfers(for peer: PeerItem) -> [TransferItem] {
        orderedActiveTransfers.filter { transfer in
            transfer.peerName == peer.displayName ||
            transfer.peerName == peer.hostName ||
            peer.ipAddresses.contains(transfer.peerName)
        }
    }

    public var orderedActiveTransfers: [TransferItem] {
        activeTransfers.values.sorted { $0.startTime > $1.startTime }
    }

    public var selectedRevealableTransfer: TransferItem? {
        guard let selectedTransferID else { return nil }
        return recentTransfers.first {
            $0.id == selectedTransferID && $0.isSuccess && $0.direction == .incoming
        }
    }

    public func start() async {
        guard !isStarted else { return }
        isStarted = true
        lastError = nil
        startListeningForEvents()

        if !hasExplicitDownloadDirectory {
            downloadDirectory = await bookmarkStore.restoreDownloadDirectory(defaultURL: defaultDownloadDirectory)
        }

        status = .connecting
        do {
            try await backend.start(
                dataDirectory: dataDirectory,
                downloadDirectory: downloadDirectory,
                deviceName: deviceName
            )
            await backend.setApprovalConfig(
                requireApproval: requireApproval,
                autoAcceptTrusted: autoAcceptTrusted
            )
            trustedPeers = await backend.trustedPeers()
        } catch {
            isStarted = false
            status = .error(message: error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    public var stagedTotalBytes: Int64 {
        stagedFiles.reduce(0) { $0 + $1.byteSize }
    }

    public var stagedSummaryText: String {
        if stagedFiles.count == 1, let first = stagedFiles.first {
            return first.name
        }
        return "\(stagedFiles.count) files staged"
    }

    public func shutdown() async {
        isStarted = false
        await backend.stop()
        eventTask?.cancel()
        eventTask = nil
        clearStagedFiles()
        securityScopeTracker.releaseAll()
        bookmarkStore.stopAccessing()
        status = .disconnected
        peers = []
        activeTransfers.removeAll()
        pendingApprovals.removeAll()
        progressSamples.removeAll()
        transferScopedURLs.removeAll()
        incomingMetadata.removeAll()
        batchReceivedURLs.removeAll()
    }

    @discardableResult
    public func renameDevice(to newName: String) async -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRestarting, !trimmed.isEmpty, trimmed != deviceName else { return false }
        userDefaults.set(trimmed, forKey: Self.deviceNameDefaultsKey)
        deviceName = trimmed
        await restartEngine()
        return true
    }

    public func restartEngine() async {
        guard !isRestarting else { return }
        isRestarting = true
        defer { isRestarting = false }

        lastError = nil
        status = .connecting
        do {
            try await backend.restart(
                dataDirectory: dataDirectory,
                downloadDirectory: downloadDirectory,
                deviceName: deviceName
            )
            await backend.setApprovalConfig(
                requireApproval: requireApproval,
                autoAcceptTrusted: autoAcceptTrusted
            )
            trustedPeers = await backend.trustedPeers()
        } catch {
            status = .error(message: error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    public func updateApprovalConfig(requireApproval: Bool, autoAcceptTrusted: Bool) async {
        self.requireApproval = requireApproval
        self.autoAcceptTrusted = autoAcceptTrusted
        userDefaults.set(requireApproval, forKey: Self.requireApprovalDefaultsKey)
        userDefaults.set(autoAcceptTrusted, forKey: Self.autoAcceptDefaultsKey)
        await backend.setApprovalConfig(
            requireApproval: requireApproval,
            autoAcceptTrusted: autoAcceptTrusted
        )
    }

    public var isDefaultDownloadDirectory: Bool {
        downloadDirectory.standardizedFileURL.path == defaultDownloadDirectory.standardizedFileURL.path
    }

    @discardableResult
    public func updateDownloadDirectory(_ url: URL) async -> Bool {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ok = await backend.setDownloadDirectory(url)
        if ok {
            await bookmarkStore.saveDownloadDirectory(url)
            downloadDirectory = url
        } else {
            lastError = "Unable to update download folder"
        }
        return ok
    }

    @discardableResult
    public func resetDownloadDirectory() async -> Bool {
        let ok = await backend.setDownloadDirectory(defaultDownloadDirectory)
        if ok {
            bookmarkStore.clearCustomDownloadDirectory()
            downloadDirectory = defaultDownloadDirectory
        } else {
            lastError = "Unable to reset download folder"
        }
        return ok
    }

    public func resolveApproval(_ request: IncomingApprovalRequest, decision: ApprovalDecision) async {
        await resolveApproval(id: request.id, decision: decision)
    }

    public func resolveApproval(id: String, decision: ApprovalDecision) async {
        pendingApprovals.removeAll { $0.id == id }
        if decision == .decline {
            incomingMetadata.removeValue(forKey: id)
        }
        onApprovalCleared?(id)
        _ = await backend.resolveApproval(transferID: id, decision: decision)
        if decision == .alwaysTrust {
            trustedPeers = await backend.trustedPeers()
        }
    }

    public func revokeTrustedPeer(nodeID: String) async {
        if await backend.revokeTrustedPeer(nodeID: nodeID) {
            trustedPeers = await backend.trustedPeers()
        }
    }

    public func cancelTransfer(id: String) async {
        await backend.cancelTransfer(id: id)
    }

    public func cancelAllActiveTransfers() async {
        let ids = Array(activeTransfers.keys)
        for id in ids {
            await backend.cancelTransfer(id: id)
        }
    }

    public func removeRecentTransfer(id: String) {
        recentTransfers.removeAll { $0.id == id }
        if selectedTransferID == id {
            selectedTransferID = nil
        }
    }

    public func clearRecentTransfers() {
        let recentIDs = Set(recentTransfers.map(\.id))
        recentTransfers.removeAll()
        if let selectedTransferID, recentIDs.contains(selectedTransferID) {
            self.selectedTransferID = nil
        }
    }

    public func revealURLs(for transfer: TransferItem) -> [URL] {
        let existing = transfer.destinationURLs.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        return existing.isEmpty ? [downloadDirectory] : existing
    }

    @discardableResult
    public func sendStagedFiles(to peer: PeerItem) async -> Bool {
        guard peer.online, let peerIP = peer.primaryIP, !stagedFiles.isEmpty else {
            return false
        }

        let files = stagedFiles
        let scopedURLs = files.map(\.url)

        if files.count == 1, let file = files.first {
            let transferID = "tx-\(UUID().uuidString.prefix(8))"
            for url in scopedURLs {
                securityScopeTracker.retain(url)
            }
            transferScopedURLs[transferID] = scopedURLs
            clearStagedFiles()

            activeTransfers[transferID] = TransferItem(
                id: transferID,
                fileName: file.name,
                peerName: peer.displayName,
                direction: .outgoing,
                bytesTransferred: 0,
                totalBytes: file.byteSize,
                startTime: Date()
            )

            await backend.sendFile(to: peerIP, fileURL: file.url, transferID: transferID)
            return true
        }

        let batchID = "batch-\(UUID().uuidString.prefix(8))"
        let totalBytes = files.reduce(Int64(0)) { $0 + $1.byteSize }
        for url in scopedURLs {
            securityScopeTracker.retain(url)
        }
        transferScopedURLs[batchID] = scopedURLs
        clearStagedFiles()

        activeTransfers[batchID] = TransferItem(
            id: batchID,
            fileName: "\(files.count) files",
            peerName: peer.displayName,
            direction: .outgoing,
            bytesTransferred: 0,
            totalBytes: totalBytes,
            startTime: Date(),
            isBatch: true,
            fileIndex: 1,
            totalFiles: files.count,
            currentFileName: files.first?.name ?? "",
            currentFileBytes: 0,
            currentFileTotal: files.first?.byteSize ?? 0
        )

        let manifestItems = files.map {
            BatchManifestItem(name: $0.name, path: $0.url.path, size: $0.byteSize)
        }
        await backend.sendBatch(to: peerIP, batchID: batchID, items: manifestItems)
        return true
    }

    public func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        if await backend.signOut() {
            peers = []
            cachedAuthURL = ""
            lastError = nil
            status = .needsAuth(url: "")
        } else {
            lastError = "Unable to sign out"
        }
    }

    public func dismissError() {
        lastError = nil
    }

    public func reportError(_ message: String) {
        lastError = message
    }

    @discardableResult
    public func stageFiles(_ urls: [URL]) -> Int {
        var added = 0
        var rejected = 0

        for url in urls {
            securityScopeTracker.retain(url)
            switch FilePathValidator.validate(url) {
            case .success(let resolved):
                let alreadyStaged = stagedFiles.contains {
                    $0.url.path == url.path || $0.url.resolvingSymlinksInPath().standardizedFileURL.path == resolved.path
                }
                if alreadyStaged {
                    securityScopeTracker.release(url)
                    continue
                }

                let size = Int64((try? resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                stagedFiles.append(StagedFileItem(url: url, name: resolved.lastPathComponent, byteSize: size))
                added += 1
            case .failure:
                securityScopeTracker.release(url)
                rejected += 1
            }
        }

        if rejected > 0 {
            lastError = rejected == 1
                ? "Skipped 1 unsupported or protected item"
                : "Skipped \(rejected) unsupported or protected items"
        }
        return added
    }

    public func removeStagedFile(_ item: StagedFileItem) {
        stagedFiles.removeAll { $0.id == item.id }
        securityScopeTracker.release(item.url)
    }

    public func clearStagedFiles() {
        for item in stagedFiles {
            securityScopeTracker.release(item.url)
        }
        stagedFiles.removeAll()
    }

    // MARK: - Event Handling

    private func startListeningForEvents() {
        guard eventTask == nil else { return }
        let stream = backend.events
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                await self.apply(event)
            }
        }
    }

    public func apply(_ event: BackendEvent) async {
        switch event {
        case .statusChanged(let code, let message):
            switch code {
            case 0:
                status = .disconnected
            case 1:
                status = .needsAuth(url: cachedAuthURL)
            case 2:
                status = cachedAuthURL.isEmpty ? .connecting : .needsAuth(url: cachedAuthURL)
            case 3:
                cachedAuthURL = ""
                lastError = nil
                status = .connected
                trustedPeers = await backend.trustedPeers()
            case 4:
                status = .error(message: message)
                lastError = message
            default:
                break
            }

        case .authRequired(let url):
            if !url.isEmpty {
                cachedAuthURL = url
            }
            status = .needsAuth(url: cachedAuthURL)

        case .peersUpdated(let updated):
            peers = updated

        case .progress(let transferID, let current, let total):
            updateSingleProgress(transferID: transferID, current: current, total: total)

        case .batchProgress(let batchID, let fileIndex, let totalFiles, let fileName, let fileCur, let fileTotal, let batchCur, let batchTotal):
            updateBatchProgress(
                batchID: batchID,
                fileIndex: fileIndex,
                totalFiles: totalFiles,
                fileName: fileName,
                fileCurrent: fileCur,
                fileTotal: fileTotal,
                batchCurrent: batchCur,
                batchTotal: batchTotal
            )

        case .batchFileReceived(let batchID, _, _, _, let filePath):
            guard !filePath.isEmpty else { return }
            let url = URL(fileURLWithPath: filePath)
            batchReceivedURLs[batchID, default: []].append(url)

        case .transferComplete(let transferID, let success, let detail):
            completeTransfer(transferID: transferID, success: success, detail: detail)

        case .incomingApproval(let request):
            incomingMetadata[request.id] = (senderName: request.senderName, fileName: request.fileName)
            if !pendingApprovals.contains(where: { $0.id == request.id }) {
                pendingApprovals.append(request)
                onIncomingApproval?(request)
            }

        case .approvalDismissed(let transferID, _):
            pendingApprovals.removeAll { $0.id == transferID }
            incomingMetadata.removeValue(forKey: transferID)
            onApprovalCleared?(transferID)
        }
    }

    private func updateSingleProgress(transferID: String, current: Int64, total: Int64) {
        let now = Date()
        let speed = computeSpeed(transferID: transferID, currentBytes: current, now: now)

        if var item = activeTransfers[transferID] {
            item.bytesTransferred = current
            item.totalBytes = total
            if let speed {
                item.speedBytesPerSec = speed
            }
            activeTransfers[transferID] = item
        } else {
            let meta = incomingMetadata[transferID]
            activeTransfers[transferID] = TransferItem(
                id: transferID,
                fileName: meta?.fileName ?? "Incoming file",
                peerName: meta?.senderName ?? "Tailnet peer",
                direction: .incoming,
                bytesTransferred: current,
                totalBytes: total,
                speedBytesPerSec: speed ?? 0,
                startTime: now
            )
        }
    }

    private func updateBatchProgress(
        batchID: String,
        fileIndex: Int,
        totalFiles: Int,
        fileName: String,
        fileCurrent: Int64,
        fileTotal: Int64,
        batchCurrent: Int64,
        batchTotal: Int64
    ) {
        let now = Date()
        let speed = computeSpeed(transferID: batchID, currentBytes: batchCurrent, now: now)

        if var item = activeTransfers[batchID] {
            item.bytesTransferred = batchCurrent
            item.totalBytes = batchTotal
            item.isBatch = totalFiles > 1
            item.fileIndex = fileIndex
            item.totalFiles = totalFiles
            item.currentFileName = fileName
            item.currentFileBytes = fileCurrent
            item.currentFileTotal = fileTotal
            if let speed {
                item.speedBytesPerSec = speed
            }
            activeTransfers[batchID] = item
        } else {
            let meta = incomingMetadata[batchID]
            activeTransfers[batchID] = TransferItem(
                id: batchID,
                fileName: meta?.fileName ?? "\(totalFiles) files",
                peerName: meta?.senderName ?? "Tailnet peer",
                direction: .incoming,
                bytesTransferred: batchCurrent,
                totalBytes: batchTotal,
                speedBytesPerSec: speed ?? 0,
                startTime: now,
                isBatch: totalFiles > 1,
                fileIndex: fileIndex,
                totalFiles: totalFiles,
                currentFileName: fileName,
                currentFileBytes: fileCurrent,
                currentFileTotal: fileTotal
            )
        }
    }

    private func completeTransfer(transferID: String, success: Bool, detail: String) {
        progressSamples.removeValue(forKey: transferID)
        let meta = incomingMetadata.removeValue(forKey: transferID)
        let receivedBatchURLs = batchReceivedURLs.removeValue(forKey: transferID)
        if let scopedURLs = transferScopedURLs.removeValue(forKey: transferID) {
            for url in scopedURLs {
                securityScopeTracker.release(url)
            }
        }

        guard var item = activeTransfers.removeValue(forKey: transferID) else {
            let inferredDirection: TransferDirection = (meta != nil || receivedBatchURLs != nil) ? .incoming : .outgoing
            if success {
                guard inferredDirection == .incoming else { return }
                let destURLs: [URL]
                let resolvedName: String
                if let receivedBatchURLs, !receivedBatchURLs.isEmpty {
                    destURLs = receivedBatchURLs
                    resolvedName = meta?.fileName ?? "\(receivedBatchURLs.count) files"
                } else if !detail.isEmpty {
                    let url = URL(fileURLWithPath: detail)
                    destURLs = [url]
                    resolvedName = url.lastPathComponent
                } else {
                    destURLs = []
                    resolvedName = meta?.fileName ?? "Incoming file"
                }
                let completed = TransferItem(
                    id: transferID,
                    fileName: resolvedName,
                    peerName: meta?.senderName ?? "Tailnet peer",
                    direction: .incoming,
                    bytesTransferred: 0,
                    totalBytes: 0,
                    isCompleted: true,
                    isSuccess: true,
                    isBatch: (receivedBatchURLs?.count ?? 0) > 1,
                    destinationURLs: destURLs
                )
                insertRecent(completed)
                onTransferCompleted?(completed)
            } else {
                let failed = TransferItem(
                    id: transferID,
                    fileName: meta?.fileName ?? "Transfer",
                    peerName: meta?.senderName ?? "Tailnet peer",
                    direction: inferredDirection,
                    bytesTransferred: 0,
                    totalBytes: 0,
                    isCompleted: true,
                    isSuccess: false,
                    errorMessage: detail.isEmpty ? "Transfer failed" : detail
                )
                insertRecent(failed)
                lastError = failed.errorMessage
                onTransferCompleted?(failed)
            }
            return
        }

        item.isCompleted = true
        item.isSuccess = success
        if success {
            item.errorMessage = nil
            item.bytesTransferred = item.totalBytes
            if let receivedBatchURLs, !receivedBatchURLs.isEmpty {
                item.destinationURLs = receivedBatchURLs
            } else if item.direction == .incoming, !detail.isEmpty {
                let url = URL(fileURLWithPath: detail)
                item.destinationURLs = [url]
                if !item.isBatch {
                    item.fileName = url.lastPathComponent
                }
            }
        } else {
            item.errorMessage = detail.isEmpty ? "Transfer failed" : detail
            lastError = item.errorMessage
        }

        insertRecent(item)
        onTransferCompleted?(item)
    }

    private func insertRecent(_ item: TransferItem) {
        recentTransfers.insert(item, at: 0)
        if recentTransfers.count > 50 {
            recentTransfers.removeLast(recentTransfers.count - 50)
        }
    }

    private func computeSpeed(transferID: String, currentBytes: Int64, now: Date) -> Double? {
        guard let prev = progressSamples[transferID] else {
            progressSamples[transferID] = (now, currentBytes)
            return nil
        }
        let dt = now.timeIntervalSince(prev.date)
        guard dt >= 0.5 else { return nil }
        let delta = max(0, currentBytes - prev.bytes)
        progressSamples[transferID] = (now, currentBytes)
        return Double(delta) / dt
    }
}
