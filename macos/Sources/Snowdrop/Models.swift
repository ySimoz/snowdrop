import Foundation

public enum EngineStatus: Equatable {
    case disconnected
    case needsAuth(url: String)
    case connecting
    case connected
    case error(message: String)

    public var title: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .needsAuth: return "Sign in required"
        case .connecting: return "Connecting..."
        case .connected: return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

public struct PeerItem: Identifiable, Codable, Hashable {
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

    public var displayName: String {
        if let d = customDisplayName, !d.isEmpty { return d }
        if !hostName.isEmpty { return hostName }
        if !dnsName.isEmpty { return dnsName }
        return id
    }

    public var primaryIP: String? {
        return ipAddresses.first
    }

    public var osIcon: String {
        switch os.lowercased() {
        case "darwin", "macos", "ios":
            return "apple.logo"
        case "android", "linux":
            return "antenna.radiowaves.left.and.right"
        case "windows":
            return "pc"
        default:
            return "desktopcomputer"
        }
    }
}

public enum TransferDirection: String, Codable {
    case incoming
    case outgoing
}

public struct TransferItem: Identifiable, Equatable {
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
    public var isBatch: Bool = false
    public var fileIndex: Int = 1
    public var totalFiles: Int = 1
    public var currentFileName: String = ""
    public var currentFileBytes: Int64 = 0
    public var currentFileTotal: Int64 = 0

    public init(
        id: String,
        fileName: String,
        peerName: String,
        direction: TransferDirection,
        bytesTransferred: Int64,
        totalBytes: Int64,
        speedBytesPerSec: Double,
        isCompleted: Bool,
        isSuccess: Bool,
        errorMessage: String? = nil,
        startTime: Date = Date(),
        isBatch: Bool = false,
        fileIndex: Int = 1,
        totalFiles: Int = 1,
        currentFileName: String = "",
        currentFileBytes: Int64 = 0,
        currentFileTotal: Int64 = 0
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
    }

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(bytesTransferred) / Double(totalBytes)))
    }

    public var speedFormatted: String {
        let mb = speedBytesPerSec / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB/s", mb)
        }
        let kb = speedBytesPerSec / 1024
        return String(format: "%.0f KB/s", kb)
    }

    public var remainingTimeFormatted: String {
        guard speedBytesPerSec > 1024, totalBytes > bytesTransferred else { return "--" }
        let remainingBytes = totalBytes - bytesTransferred
        let seconds = Double(remainingBytes) / speedBytesPerSec
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remSec = Int(seconds) % 60
        return "\(minutes)m \(remSec)s"
    }
}
