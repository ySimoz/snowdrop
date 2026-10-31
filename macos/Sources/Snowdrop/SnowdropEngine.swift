import Foundation
import Combine
import AppKit
import UserNotifications
import CSnowdrop

public struct IncomingApprovalRequest: Identifiable {
    public let id: String
    public let nodeID: String
    public let senderName: String
    public let fileName: String
    public let fileSize: Int64
    public let formattedSize: String
}

public struct TrustedPeerItem: Codable, Identifiable {
    public var id: String { node_id }
    public let node_id: String
    public let device_name: String
    public let auto_accept: Bool
}

public final class SnowdropEngine: ObservableObject {
    public static let shared = SnowdropEngine()

    @Published public private(set) var status: EngineStatus = .disconnected
    @Published public private(set) var peers: [PeerItem] = []
    @Published public private(set) var activeTransfer: TransferItem?
    @Published public private(set) var recentTransfers: [TransferItem] = []
    @Published public private(set) var pendingApproval: IncomingApprovalRequest?
    @Published public private(set) var trustedPeers: [TrustedPeerItem] = []
    @Published public var requireApproval: Bool = true {
        didSet {
            SetApprovalConfig(requireApproval, autoAccept)
        }
    }
    @Published public var downloadDirectory: URL
    @Published public var autoAccept: Bool = true {
        didSet {
            SetApprovalConfig(requireApproval, autoAccept)
        }
    }
    @Published public var deviceName: String
    @Published public var stagedFileURLs: [URL] = []

    public var stagedFileURL: URL? { stagedFileURLs.first }
    public var stagedFileName: String {
        if stagedFileURLs.count == 1 {
            return stagedFileURLs[0].lastPathComponent
        } else if stagedFileURLs.count > 1 {
            return "\(stagedFileURLs.count) files staged"
        }
        return ""
    }
    public var stagedTotalBytes: Int64 {
        stagedFileURLs.reduce(0) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            return total + size
        }
    }
    public var stagedFileSizeFormatted: String {
        let size = stagedTotalBytes
        guard size > 0 else { return stagedFileURLs.isEmpty ? "" : "0 B" }
        if size >= 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", Double(size) / (1024 * 1024 * 1024))
        } else if size >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(size) / (1024 * 1024))
        } else if size >= 1024 {
            return String(format: "%.0f KB", Double(size) / 1024)
        } else {
            return "\(size) B"
        }
    }

    private var isEngineRunning = false
    private var cachedAuthURL: String = ""
    private var lastProgressCheck: Date = Date()
    private var lastBytesCount: Int64 = 0

    public func stageFiles(_ urls: [URL]) {
        let existingPaths = Set(stagedFileURLs.map { $0.path })
        let unique = urls.filter { !existingPaths.contains($0.path) }
        stagedFileURLs.append(contentsOf: unique)
    }

    public func stageFile(_ url: URL) {
        stageFiles([url])
    }

    public func clearStagedFiles() {
        stagedFileURLs.removeAll()
    }

    public func clearStagedFile() {
        clearStagedFiles()
    }

    public func clearRecentTransfers() {
        recentTransfers.removeAll()
    }

    public func removeRecentTransfer(transferID: String) {
        recentTransfers.removeAll { $0.id == transferID }
    }

    private init() {
        let defaultDownloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        self.downloadDirectory = defaultDownloads
        let savedName = UserDefaults.standard.string(forKey: "SnowdropDeviceName")
        self.deviceName = savedName ?? (Host.current().localizedName ?? "Mac")

        setupNotifications()
    }

    public func setDeviceName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: "SnowdropDeviceName")
        self.deviceName = trimmed
        restart()
    }

    public func start() {
        guard !isEngineRunning else { return }
        isEngineRunning = true

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dataDir = appSupport.appendingPathComponent("Snowdrop").path
        let dlDir = downloadDirectory.path
        let devName = deviceName

        DispatchQueue.global(qos: .userInitiated).async {
            RegisterCallbacks(
                { status, msg in
                    let message = msg != nil ? String(cString: msg!) : ""
                    SnowdropEngine.shared.handleStatusChange(status: Int(status), message: message)
                },
                { url in
                    let authURL = url != nil ? String(cString: url!) : ""
                    SnowdropEngine.shared.handleAuthRequired(url: authURL)
                },
                { json in
                    let jsonStr = json != nil ? String(cString: json!) : ""
                    SnowdropEngine.shared.handlePeersUpdated(json: jsonStr)
                },
                { id, current, total in
                    let transferID = id != nil ? String(cString: id!) : ""
                    SnowdropEngine.shared.handleProgress(transferID: transferID, current: current, total: total)
                },
                { id, success, err in
                    let transferID = id != nil ? String(cString: id!) : ""
                    let errorMsg = err != nil ? String(cString: err!) : ""
                    SnowdropEngine.shared.handleTransferComplete(transferID: transferID, success: success, errorMsg: errorMsg)
                }
            )

            RegisterApprovalCallback { id, node, sender, file, size in
                let transferID = id != nil ? String(cString: id!) : ""
                let nodeID = node != nil ? String(cString: node!) : ""
                let senderName = sender != nil ? String(cString: sender!) : ""
                let fileName = file != nil ? String(cString: file!) : ""
                SnowdropEngine.shared.handleIncomingApproval(
                    transferID: transferID,
                    nodeID: nodeID,
                    senderName: senderName,
                    fileName: fileName,
                    fileSize: size
                )
            }

            RegisterBatchProgressCallback { bID, idx, total, name, fCur, fTotal, bCur, bTotal in
                let batchID = bID != nil ? String(cString: bID!) : ""
                let fileName = name != nil ? String(cString: name!) : ""
                SnowdropEngine.shared.handleBatchProgress(
                    batchID: batchID,
                    fileIndex: Int(idx),
                    totalFiles: Int(total),
                    fileName: fileName,
                    fileCur: fCur,
                    fileTotal: fTotal,
                    batchCur: bCur,
                    batchTotal: bTotal
                )
            }

            let code = StartEngine(dataDir, dlDir, devName)
            NSLog("[Snowdrop] StartEngine returned code: %d", code)
            DispatchQueue.main.async {
                if code == 0 {
                    self.status = .connecting
                } else {
                    self.isEngineRunning = false
                    self.status = .error(message: "Failed to initialize engine (code \(code))")
                }
            }
        }
    }

    public func stop() {
        guard isEngineRunning else { return }
        isEngineRunning = false
        DispatchQueue.main.async {
            self.status = .disconnected
            self.peers = []
            self.activeTransfer = nil
        }

        DispatchQueue.global(qos: .userInitiated).async {
            StopEngine()
        }
    }

    public func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.start()
        }
    }

    public func openAuthURL() {
        let urlString: String
        if case .needsAuth(let url) = status, !url.isEmpty {
            urlString = url
        } else if !cachedAuthURL.isEmpty {
            urlString = cachedAuthURL
        } else {
            return
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    public func sendFile(to peer: PeerItem, fileURL: URL) {
        sendFiles(to: peer, fileURLs: [fileURL])
    }

    public struct FileManifestItem: Codable {
        public let name: String
        public let path: String
        public let size: Int64
    }

    public func sendFiles(to peer: PeerItem, fileURLs: [URL]) {
        guard let peerIP = peer.primaryIP, !fileURLs.isEmpty else { return }

        if fileURLs.count == 1 {
            let fileURL = fileURLs[0]
            let transferID = "tx-\(UUID().uuidString.prefix(8))"
            let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

            let transfer = TransferItem(
                id: transferID,
                fileName: fileURL.lastPathComponent,
                peerName: peer.displayName,
                direction: .outgoing,
                bytesTransferred: 0,
                totalBytes: Int64(fileSize),
                speedBytesPerSec: 0,
                isCompleted: false,
                isSuccess: false,
                errorMessage: nil,
                startTime: Date()
            )

            DispatchQueue.main.async {
                self.activeTransfer = transfer
                self.lastProgressCheck = Date()
                self.lastBytesCount = 0
            }

            SendFile(peerIP, fileURL.path, transferID)
            return
        }

        let batchID = "batch-\(UUID().uuidString.prefix(8))"
        let totalSize = fileURLs.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }

        let firstSize = Int64((try? fileURLs.first?.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        let transfer = TransferItem(
            id: batchID,
            fileName: "\(fileURLs.count) files",
            peerName: peer.displayName,
            direction: .outgoing,
            bytesTransferred: 0,
            totalBytes: totalSize,
            speedBytesPerSec: 0,
            isCompleted: false,
            isSuccess: false,
            errorMessage: nil,
            startTime: Date(),
            isBatch: true,
            fileIndex: 1,
            totalFiles: fileURLs.count,
            currentFileName: fileURLs.first?.lastPathComponent ?? "",
            currentFileBytes: 0,
            currentFileTotal: firstSize
        )

        DispatchQueue.main.async {
            self.activeTransfer = transfer
            self.lastProgressCheck = Date()
            self.lastBytesCount = 0
        }

        var items: [FileManifestItem] = []
        for u in fileURLs {
            let size = Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            items.append(FileManifestItem(name: u.lastPathComponent, path: u.path, size: size))
        }

        guard let jsonData = try? JSONEncoder().encode(items),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            return
        }

        peerIP.withCString { cIP in
            batchID.withCString { cBatchID in
                jsonStr.withCString { cJSON in
                    SendBatch(cIP, cBatchID, cJSON)
                }
            }
        }
    }

    public func cancelActiveTransfer() {
        guard let active = activeTransfer else { return }
        CancelTransfer(active.id)
    }

    public func selectDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Destination"

        if panel.runModal() == .OK, let selected = panel.url {
            self.downloadDirectory = selected
        }
    }

    public var defaultDownloadDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    public var isDefaultDownloadDirectory: Bool {
        downloadDirectory.path == defaultDownloadDirectory.path
    }

    public func resetDownloadFolder() {
        self.downloadDirectory = defaultDownloadDirectory
    }

    // MARK: - Internal Callback Handlers

    func handleStatusChange(status: Int, message: String) {
        NSLog("[Snowdrop] handleStatusChange: %d, msg: %@", status, message)
        DispatchQueue.main.async {
            switch status {
            case 0:
                self.status = .disconnected
            case 1:
                self.status = .needsAuth(url: self.cachedAuthURL)
            case 2:
                if self.cachedAuthURL.isEmpty {
                    self.status = .connecting
                } else {
                    self.status = .needsAuth(url: self.cachedAuthURL)
                }
            case 3:
                self.cachedAuthURL = ""
                self.status = .connected
            case 4:
                self.status = .error(message: message)
            default:
                break
            }
        }
    }

    func handleAuthRequired(url: String) {
        NSLog("[Snowdrop] handleAuthRequired: %@", url)
        DispatchQueue.main.async {
            if !url.isEmpty {
                self.cachedAuthURL = url
            }
            self.status = .needsAuth(url: self.cachedAuthURL)
        }
    }

    func handlePeersUpdated(json: String) {
        NSLog("[Snowdrop] handlePeersUpdated: %@", json)
        guard let data = json.data(using: .utf8) else { return }
        do {
            let decoded = try JSONDecoder().decode([PeerItem].self, from: data)
            DispatchQueue.main.async {
                self.peers = decoded
            }
        } catch {
            // peer parsing error ignored
        }
    }

    func handleProgress(transferID: String, current: Int64, total: Int64) {
        DispatchQueue.main.async {
            guard var currentTransfer = self.activeTransfer, currentTransfer.id == transferID else {
                let newTransfer = TransferItem(
                    id: transferID,
                    fileName: "Receiving File...",
                    peerName: "Tailnet Peer",
                    direction: .incoming,
                    bytesTransferred: current,
                    totalBytes: total,
                    speedBytesPerSec: 0,
                    isCompleted: false,
                    isSuccess: false,
                    errorMessage: nil,
                    startTime: Date()
                )
                self.activeTransfer = newTransfer
                self.lastProgressCheck = Date()
                self.lastBytesCount = current
                return
            }

            let now = Date()
            let timeDiff = now.timeIntervalSince(self.lastProgressCheck)
            if timeDiff >= 0.5 {
                let bytesDiff = current - self.lastBytesCount
                currentTransfer.speedBytesPerSec = max(0, Double(bytesDiff) / timeDiff)
                self.lastProgressCheck = now
                self.lastBytesCount = current
            }

            currentTransfer.bytesTransferred = current
            currentTransfer.totalBytes = total
            self.activeTransfer = currentTransfer
        }
    }

    func handleBatchProgress(
        batchID: String,
        fileIndex: Int,
        totalFiles: Int,
        fileName: String,
        fileCur: Int64,
        fileTotal: Int64,
        batchCur: Int64,
        batchTotal: Int64
    ) {
        DispatchQueue.main.async {
            guard var currentTransfer = self.activeTransfer, currentTransfer.id == batchID else {
                let newTransfer = TransferItem(
                    id: batchID,
                    fileName: "\(totalFiles) files",
                    peerName: "Tailnet Peer",
                    direction: .incoming,
                    bytesTransferred: batchCur,
                    totalBytes: batchTotal,
                    speedBytesPerSec: 0,
                    isCompleted: false,
                    isSuccess: false,
                    errorMessage: nil,
                    startTime: Date(),
                    isBatch: totalFiles > 1,
                    fileIndex: fileIndex,
                    totalFiles: totalFiles,
                    currentFileName: fileName,
                    currentFileBytes: fileCur,
                    currentFileTotal: fileTotal
                )
                self.activeTransfer = newTransfer
                self.lastProgressCheck = Date()
                self.lastBytesCount = batchCur
                return
            }

            let now = Date()
            let timeDiff = now.timeIntervalSince(self.lastProgressCheck)
            if timeDiff >= 0.5 {
                let bytesDiff = batchCur - self.lastBytesCount
                currentTransfer.speedBytesPerSec = max(0, Double(bytesDiff) / timeDiff)
                self.lastProgressCheck = now
                self.lastBytesCount = batchCur
            }

            currentTransfer.bytesTransferred = batchCur
            currentTransfer.totalBytes = batchTotal
            currentTransfer.isBatch = totalFiles > 1
            currentTransfer.fileIndex = fileIndex
            currentTransfer.totalFiles = totalFiles
            currentTransfer.currentFileName = fileName
            currentTransfer.currentFileBytes = fileCur
            currentTransfer.currentFileTotal = fileTotal
            self.activeTransfer = currentTransfer
        }
    }

    func handleTransferComplete(transferID: String, success: Bool, errorMsg: String) {
        DispatchQueue.main.async {
            guard var transfer = self.activeTransfer, transfer.id == transferID else { return }
            transfer.isCompleted = true
            transfer.isSuccess = success
            transfer.errorMessage = errorMsg.isEmpty ? nil : errorMsg
            transfer.bytesTransferred = transfer.totalBytes

            self.recentTransfers.insert(transfer, at: 0)
            if self.recentTransfers.count > 5 {
                self.recentTransfers.removeLast()
            }
            self.activeTransfer = nil

            let title = success ? "Transfer Complete" : "Transfer Failed"
            let body = success
                ? "\(transfer.fileName) transferred successfully."
                : "Failed to transfer \(transfer.fileName): \(errorMsg)"
            self.postNotification(title: title, body: body)
        }
    }

    func handleIncomingApproval(transferID: String, nodeID: String, senderName: String, fileName: String, fileSize: Int64) {
        DispatchQueue.main.async {
            let formattedSize: String
            if fileSize >= 1024 * 1024 * 1024 {
                formattedSize = String(format: "%.2f GB", Double(fileSize) / (1024 * 1024 * 1024))
            } else if fileSize >= 1024 * 1024 {
                formattedSize = String(format: "%.1f MB", Double(fileSize) / (1024 * 1024))
            } else {
                formattedSize = String(format: "%.0f KB", Double(fileSize) / 1024)
            }

            let req = IncomingApprovalRequest(
                id: transferID,
                nodeID: nodeID,
                senderName: senderName,
                fileName: fileName,
                fileSize: fileSize,
                formattedSize: formattedSize
            )
            self.pendingApproval = req

            let content = UNMutableNotificationContent()
            content.title = "Incoming File Transfer"
            content.body = "\(senderName) wants to send \(fileName) (\(formattedSize))"
            content.sound = .default
            content.categoryIdentifier = "TRANSFER_APPROVAL"
            content.userInfo = ["transferID": transferID]

            let notifReq = UNNotificationRequest(identifier: transferID, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(notifReq, withCompletionHandler: nil)
        }
    }

    public func resolveApproval(transferID: String, decision: Int) {
        DispatchQueue.main.async {
            if self.pendingApproval?.id == transferID {
                self.pendingApproval = nil
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [transferID])
        }
        _ = transferID.withCString { cID in
            ResolveTransferApproval(cID, Int32(decision))
        }
        refreshTrustedPeers()
    }

    public func refreshTrustedPeers() {
        if let jsonPtr = GetTrustedPeers() {
            defer { free(jsonPtr) }
            let jsonStr = String(cString: jsonPtr)
            if let data = jsonStr.data(using: .utf8),
               let list = try? JSONDecoder().decode([TrustedPeerItem].self, from: data) {
                DispatchQueue.main.async {
                    self.trustedPeers = list
                }
            }
        }
    }

    public func revokeTrustedPeer(nodeID: String) {
        _ = nodeID.withCString { cNode in
            RevokeTrusted(cNode)
        }
        refreshTrustedPeers()
    }

    public func signOut() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = SnowdropSignOut()
            DispatchQueue.main.async {
                self.peers = []
                self.status = .needsAuth(url: "")
            }
        }
    }

    private func setupNotifications() {
        let acceptAction = UNNotificationAction(identifier: "ACTION_ACCEPT", title: "Accept", options: [.foreground])
        let trustAction = UNNotificationAction(identifier: "ACTION_TRUST", title: "Always Trust", options: [])
        let declineAction = UNNotificationAction(identifier: "ACTION_DECLINE", title: "Decline", options: [.destructive])

        let category = UNNotificationCategory(
            identifier: "TRANSFER_APPROVAL",
            actions: [acceptAction, trustAction, declineAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
