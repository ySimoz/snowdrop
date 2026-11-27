package com.snowdrop.app.domain

import java.util.Locale

sealed interface EngineStatus {
    val title: String

    data object Disconnected : EngineStatus {
        override val title: String = "Disconnected"
    }

    data class NeedsAuth(val url: String) : EngineStatus {
        override val title: String = "Sign in required"
    }

    data object Connecting : EngineStatus {
        override val title: String = "Connecting"
    }

    data object Connected : EngineStatus {
        override val title: String = "Online"
    }

    data class Error(val message: String) : EngineStatus {
        override val title: String = "Error"
    }
}

data class PeerItem(
    val id: String,
    val hostName: String,
    val rawDisplayName: String = "",
    val dnsName: String = "",
    val os: String = "",
    val ipAddresses: List<String> = emptyList(),
    val online: Boolean = false
) {
    val displayName: String
        get() = when {
            rawDisplayName.isNotBlank() -> rawDisplayName
            hostName.isNotBlank() -> hostName
            dnsName.isNotBlank() -> dnsName
            else -> id
        }

    val primaryIP: String?
        get() = ipAddresses.firstOrNull()
}

data class StagedFile(
    val uriString: String,
    val name: String,
    val byteSize: Long
) {
    val formattedSize: String
        get() = SnowdropFormat.bytes(byteSize)
}

enum class TransferDirection {
    OUTGOING,
    INCOMING
}

data class TransferItem(
    val id: String,
    val fileName: String,
    val peerName: String,
    val direction: TransferDirection,
    val bytesTransferred: Long = 0L,
    val totalBytes: Long = 0L,
    val startTimeMs: Long = 0L,
    val speedBytesPerSec: Double = 0.0,
    val etaSeconds: Double = 0.0,
    val isCompleted: Boolean = false,
    val isSuccess: Boolean = false,
    val errorMessage: String? = null,
    val destinationUriString: String? = null,
    val isBatch: Boolean = false,
    val fileIndex: Int = 1,
    val totalFiles: Int = 1,
    val currentFileName: String = "",
    val currentFileBytes: Long = 0L,
    val currentFileTotal: Long = 0L
) {
    val progress: Float
        get() = if (totalBytes > 0L) (bytesTransferred.toFloat() / totalBytes.toFloat()).coerceIn(0f, 1f) else 0f

    val fileProgress: Float
        get() = if (currentFileTotal > 0L) (currentFileBytes.toFloat() / currentFileTotal.toFloat()).coerceIn(0f, 1f) else 0f
}

data class ApprovalRequest(
    val transferId: String,
    val senderNodeId: String,
    val senderName: String,
    val fileName: String,
    val byteSize: Long
) {
    val formattedSize: String
        get() = SnowdropFormat.bytes(byteSize)
}

enum class ApprovalDecision(val code: Int) {
    ACCEPT(1),
    ALWAYS_TRUST(2),
    DECLINE(3)
}

data class TrustedPeer(
    val nodeId: String,
    val deviceName: String,
    val autoAccept: Boolean
)

enum class AppTab(val label: String) {
    DEVICES("Devices"),
    TRANSFERS("Transfers"),
    TRUSTED("Trusted"),
    SETTINGS("Settings")
}

data class SnowdropUiState(
    val status: EngineStatus = EngineStatus.Disconnected,
    val deviceName: String = "",
    val downloadLocationName: String = "Downloads/Snowdrop",
    val peers: List<PeerItem> = emptyList(),
    val filteredPeers: List<PeerItem> = emptyList(),
    val activeTransfers: List<TransferItem> = emptyList(),
    val recentTransfers: List<TransferItem> = emptyList(),
    val pendingApprovals: List<ApprovalRequest> = emptyList(),
    val trustedPeers: List<TrustedPeer> = emptyList(),
    val stagedFiles: List<StagedFile> = emptyList(),
    val requireApproval: Boolean = true,
    val autoAcceptTrusted: Boolean = true,
    val searchQuery: String = "",
    val selectedTab: AppTab = AppTab.DEVICES,
    val lastError: String? = null,
    val isRestarting: Boolean = false,
    val isSigningOut: Boolean = false
) {
    val stagedTotalBytes: Long
        get() = stagedFiles.sumOf { it.byteSize }

    val stagedSummaryText: String
        get() = when {
            stagedFiles.isEmpty() -> ""
            stagedFiles.size == 1 -> stagedFiles.first().name
            else -> "${stagedFiles.size} files"
        }

    val onlinePeerCount: Int
        get() = peers.count { it.online }
}

object SnowdropFormat {
    fun bytes(count: Long): String = when {
        count >= 1024L * 1024L * 1024L -> String.format(Locale.US, "%.2f GB", count.toDouble() / (1024.0 * 1024.0 * 1024.0))
        count >= 1024L * 1024L -> String.format(Locale.US, "%.1f MB", count.toDouble() / (1024.0 * 1024.0))
        count >= 1024L -> String.format(Locale.US, "%.0f KB", count.toDouble() / 1024.0)
        count > 0L -> "$count B"
        else -> "0 B"
    }

    fun speed(bytesPerSec: Double): String {
        if (bytesPerSec <= 0.0) return ""
        return "${bytes(bytesPerSec.toLong())}/s"
    }

    fun eta(seconds: Double): String {
        if (seconds <= 0.5) return ""
        val total = seconds.toInt()
        val mins = total / 60
        val secs = total % 60
        return if (mins > 0) "${mins}m ${secs}s" else "${secs}s"
    }
}
