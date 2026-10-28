import Foundation
import Combine
import AppKit
import UserNotifications
import CSnowdrop

public final class SnowdropEngine: ObservableObject {
    public static let shared = SnowdropEngine()

    @Published public private(set) var status: EngineStatus = .disconnected
    @Published public private(set) var peers: [PeerItem] = []
    @Published public private(set) var activeTransfer: TransferItem?
    @Published public private(set) var recentTransfers: [TransferItem] = []
    @Published public var downloadDirectory: URL
    @Published public var autoAccept: Bool = true
    @Published public var deviceName: String

    private var isEngineRunning = false
    private var lastProgressCheck: Date = Date()
    private var lastBytesCount: Int64 = 0

    private init() {
        let defaultDownloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        self.downloadDirectory = defaultDownloads
        self.deviceName = Host.current().localizedName ?? "Mac"

        setupNotifications()
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

            let code = StartEngine(dataDir, dlDir, devName)
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
        StopEngine()
        isEngineRunning = false
        DispatchQueue.main.async {
            self.status = .disconnected
            self.peers = []
            self.activeTransfer = nil
        }
    }

    public func openAuthURL() {
        if case .needsAuth(let urlString) = status, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    public func sendFile(to peer: PeerItem, fileURL: URL) {
        guard let peerIP = peer.primaryIP else { return }
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

    // MARK: - Internal Callback Handlers

    func handleStatusChange(status: Int, message: String) {
        DispatchQueue.main.async {
            switch status {
            case 0:
                self.status = .disconnected
            case 1:
                if case .needsAuth = self.status {
                    // retain current auth url
                } else {
                    self.status = .needsAuth(url: "")
                }
            case 2:
                self.status = .connecting
            case 3:
                self.status = .connected
            case 4:
                self.status = .error(message: message)
            default:
                break
            }
        }
    }

    func handleAuthRequired(url: String) {
        DispatchQueue.main.async {
            self.status = .needsAuth(url: url)
        }
    }

    func handlePeersUpdated(json: String) {
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

    private func setupNotifications() {
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
