import Foundation

public enum NavigationSection: String, CaseIterable, Identifiable, Sendable {
    case devices
    case transfers
    case trusted

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .devices: "Devices"
        case .transfers: "Transfers"
        case .trusted: "Trusted Devices"
        }
    }

    public var systemImage: String {
        switch self {
        case .devices: "laptopcomputer.and.iphone"
        case .transfers: "arrow.up.arrow.down"
        case .trusted: "checkmark.shield"
        }
    }
}

public enum EngineStatus: Equatable, Sendable {
    case disconnected
    case needsAuth(url: String)
    case connecting
    case connected
    case error(message: String)

    public var title: String {
        switch self {
        case .disconnected: "Disconnected"
        case .needsAuth: "Sign in required"
        case .connecting: "Connecting"
        case .connected: "Ready"
        case .error(let msg): "Error: \(msg)"
        }
    }
}

public struct PeerItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let hostName: String
    public let customDisplayName: String?
    public let dnsName: String
    public let os: String
    public let ipAddresses: [String]
    public let online: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case hostName
        case customDisplayName = "displayName"
        case dnsName
        case os
        case ipAddresses
        case online
    }

    public init(
        id: String,
        hostName: String,
        customDisplayName: String? = nil,
        dnsName: String = "",
        os: String = "",
        ipAddresses: [String] = [],
        online: Bool
    ) {
        self.id = id
        self.hostName = hostName
        self.customDisplayName = customDisplayName
        self.dnsName = dnsName
        self.os = os
        self.ipAddresses = ipAddresses
        self.online = online
    }

    public var displayName: String {
        if let customDisplayName, !customDisplayName.isEmpty { return customDisplayName }
        if !hostName.isEmpty { return hostName }
        if !dnsName.isEmpty { return dnsName }
        return id
    }

    public var primaryIP: String? {
        ipAddresses.first
    }

    public var osSymbolName: String {
        switch os.lowercased() {
        case "darwin", "macos": "laptopcomputer"
        case "ios": "iphone"
        case "android": "smartphone"
        case "linux": "terminal"
        case "windows": "pc"
        default: "desktopcomputer"
        }
    }
}

public enum TransferDirection: String, Codable, Sendable {
    case incoming
    case outgoing
}

public struct TransferItem: Identifiable, Equatable, Sendable {
    public let id: String
    public var fileName: String
    public var peerName: String
    public var direction: TransferDirection
    public var bytesTransferred: Int64
    public var totalBytes: Int64
    public var speedBytesPerSec: Double
    public var isCompleted: Bool
    public var isSuccess: Bool
    public var errorMessage: String?
    public var startTime: Date
    public var isBatch: Bool
    public var fileIndex: Int
    public var totalFiles: Int
    public var currentFileName: String
    public var currentFileBytes: Int64
    public var currentFileTotal: Int64
    public var destinationURLs: [URL]

    public init(
        id: String,
        fileName: String,
        peerName: String,
        direction: TransferDirection,
        bytesTransferred: Int64,
        totalBytes: Int64,
        speedBytesPerSec: Double = 0,
        isCompleted: Bool = false,
        isSuccess: Bool = false,
        errorMessage: String? = nil,
        startTime: Date = Date(),
        isBatch: Bool = false,
        fileIndex: Int = 1,
        totalFiles: Int = 1,
        currentFileName: String = "",
        currentFileBytes: Int64 = 0,
        currentFileTotal: Int64 = 0,
        destinationURLs: [URL] = []
    ) {
        self.id = id
        self.fileName = fileName
        self.peerName = peerName
        self.direction = direction
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.speedBytesPerSec = speedBytesPerSec
        self.isCompleted = isCompleted
        self.isSuccess = isSuccess
        self.errorMessage = errorMessage
        self.startTime = startTime
        self.isBatch = isBatch
        self.fileIndex = fileIndex
        self.totalFiles = totalFiles
        self.currentFileName = currentFileName
        self.currentFileBytes = currentFileBytes
        self.currentFileTotal = currentFileTotal
        self.destinationURLs = destinationURLs
    }

    public var progress: Double {
        guard totalBytes > 0 else { return isCompleted && isSuccess ? 1.0 : 0.0 }
        return min(1.0, max(0.0, Double(bytesTransferred) / Double(totalBytes)))
    }

    public var speedFormatted: String {
        let mb = speedBytesPerSec / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB/s", mb)
        }
        return String(format: "%.0f KB/s", speedBytesPerSec / 1024)
    }

    public var remainingTimeFormatted: String {
        guard speedBytesPerSec > 1024, totalBytes > bytesTransferred else { return "--" }
        let seconds = Double(totalBytes - bytesTransferred) / speedBytesPerSec
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remSec = Int(seconds) % 60
        return "\(minutes)m \(remSec)s"
    }
}

public struct IncomingApprovalRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let nodeID: String
    public let senderName: String
    public let fileName: String
    public let fileSize: Int64

    public init(id: String, nodeID: String, senderName: String, fileName: String, fileSize: Int64) {
        self.id = id
        self.nodeID = nodeID
        self.senderName = senderName
        self.fileName = fileName
        self.fileSize = fileSize
    }

    public var formattedSize: String {
        SnowdropFormat.bytes(fileSize)
    }
}

public struct TrustedPeerItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String { node_id }
    public let node_id: String
    public let device_name: String
    public let added_at: String?
    public let auto_accept: Bool

    public init(node_id: String, device_name: String, added_at: String? = nil, auto_accept: Bool = true) {
        self.node_id = node_id
        self.device_name = device_name
        self.added_at = added_at
        self.auto_accept = auto_accept
    }
}

public enum ApprovalDecision: Int32, Sendable {
    case accept = 1
    case alwaysTrust = 2
    case decline = 3

    public static let acceptActionIdentifier = "ACTION_ACCEPT"
    public static let trustActionIdentifier = "ACTION_TRUST"
    public static let declineActionIdentifier = "ACTION_DECLINE"

    public init?(notificationActionIdentifier: String) {
        switch notificationActionIdentifier {
        case Self.acceptActionIdentifier: self = .accept
        case Self.trustActionIdentifier: self = .alwaysTrust
        case Self.declineActionIdentifier: self = .decline
        default: return nil
        }
    }
}

public struct BatchManifestItem: Codable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let size: Int64

    public init(name: String, path: String, size: Int64) {
        self.name = name
        self.path = path
        self.size = size
    }
}

public struct StagedFileItem: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let byteSize: Int64

    public init(url: URL, name: String, byteSize: Int64) {
        self.url = url
        self.name = name
        self.byteSize = byteSize
    }
}

public enum BackendEvent: Sendable {
    case statusChanged(code: Int, message: String)
    case authRequired(url: String)
    case peersUpdated([PeerItem])
    case progress(transferID: String, current: Int64, total: Int64)
    case batchProgress(
        batchID: String,
        fileIndex: Int,
        totalFiles: Int,
        fileName: String,
        fileCurrent: Int64,
        fileTotal: Int64,
        batchCurrent: Int64,
        batchTotal: Int64
    )
    case batchFileReceived(batchID: String, fileIndex: Int, totalFiles: Int, fileName: String, filePath: String)
    case transferComplete(transferID: String, success: Bool, detail: String)
    case incomingApproval(IncomingApprovalRequest)
    case approvalDismissed(transferID: String, reason: String)
}

public enum SnowdropFormat {
    public static func bytes(_ size: Int64) -> String {
        guard size > 0 else { return "0 B" }
        if size >= 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", Double(size) / (1024 * 1024 * 1024))
        } else if size >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(size) / (1024 * 1024))
        } else if size >= 1024 {
            return String(format: "%.0f KB", Double(size) / 1024)
        }
        return "\(size) B"
    }
}
