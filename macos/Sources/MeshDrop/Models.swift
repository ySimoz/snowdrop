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
    public let dnsName: String
    public let os: String
    public let ipAddresses: [String]
    public let online: Bool

    public var displayName: String {
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
