package com.snowdrop.app.ui

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.snowdrop.app.core.EngineStatus
import com.snowdrop.app.core.PeerItem
import com.snowdrop.app.core.SnowdropCoreBridge
import com.snowdrop.app.core.TransferItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SnowdropScreen(
    onPickFileForPeer: (PeerItem) -> Unit
) {
    val context = LocalContext.current
    val status by SnowdropCoreBridge.status.collectAsState()
    val peers by SnowdropCoreBridge.peers.collectAsState()
    val activeTransfer by SnowdropCoreBridge.activeTransfer.collectAsState()
    val recentTransfers by SnowdropCoreBridge.recentTransfers.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.FilterVintage,
                            contentDescription = "Snowdrop",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Snowdrop", fontWeight = FontWeight.Bold)
                    }
                },
                actions = {
                    StatusPill(status = status)
                }
            )
        }
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Auth Banner if required
            if (status is EngineStatus.NeedsAuth) {
                item {
                    val authUrl = (status as EngineStatus.NeedsAuth).url
                    Card(
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text(
                                "Tailscale Sign-in Required",
                                fontWeight = FontWeight.SemiBold,
                                style = MaterialTheme.typography.titleMedium
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                "Authorize this device on your Tailnet to discover and stream files with peers.",
                                style = MaterialTheme.typography.bodyMedium
                            )
                            Spacer(modifier = Modifier.height(12.dp))
                            Button(
                                onClick = {
                                    if (authUrl.isNotEmpty()) {
                                        val customTabs = CustomTabsIntent.Builder().build()
                                        customTabs.launchUrl(context, Uri.parse(authUrl))
                                    }
                                },
                                enabled = authUrl.isNotEmpty(),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Icon(Icons.Default.OpenInNew, contentDescription = null)
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(if (authUrl.isNotEmpty()) "Sign in with Tailscale" else "Obtaining sign-in link...")
                            }
                        }
                    }
                }
            }

            // Active Transfer
            activeTransfer?.let { transfer ->
                item {
                    Text(
                        "ACTIVE TRANSFER",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.secondary
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    ActiveTransferCard(
                        transfer = transfer,
                        onCancel = { SnowdropCoreBridge.cancelTransfer(transfer.id) }
                    )
                }
            }

            // Available Peers
            item {
                Text(
                    "AVAILABLE DEVICES",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.secondary
                )
            }

            if (peers.isEmpty()) {
                item {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(24.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                when {
                                    status is EngineStatus.Connected -> "No online peers detected on Tailnet."
                                    status is EngineStatus.NeedsAuth -> "Sign in with Tailscale above to see peers."
                                    else -> "Connecting to Tailnet..."
                                },
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            } else {
                items(peers) { peer ->
                    PeerCard(peer = peer, onSendFile = { onPickFileForPeer(peer) })
                }
            }

            // Recent Transfers
            if (recentTransfers.isNotEmpty()) {
                item {
                    Text(
                        "RECENT TRANSFERS",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.secondary
                    )
                }
                items(recentTransfers) { recent ->
                    RecentTransferRow(transfer = recent)
                }
            }
        }
    }
}

@Composable
fun StatusPill(status: EngineStatus) {
    val (dotColor, label) = when (status) {
        is EngineStatus.Connected -> Color(0xFF4CAF50) to "Online"
        is EngineStatus.NeedsAuth -> Color(0xFFFF9800) to "Auth"
        is EngineStatus.Connecting -> Color(0xFFFFEB3B) to "Connecting"
        else -> Color(0xFF9E9E9E) to "Offline"
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .padding(end = 12.dp)
            .background(dotColor.copy(alpha = 0.15f), shape = RoundedCornerShape(12.dp))
            .padding(horizontal = 10.dp, vertical = 4.dp)
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(dotColor)
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
fun ActiveTransferCard(transfer: TransferItem, onCancel: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = if (transfer.isIncoming) Icons.Default.ArrowDownward else Icons.Default.ArrowUpward,
                    contentDescription = null,
                    tint = if (transfer.isIncoming) Color(0xFF4CAF50) else Color(0xFF2196F3)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(transfer.fileName, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    Text(
                        if (transfer.isIncoming) "From: ${transfer.peerName}" else "To: ${transfer.peerName}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                TextButton(onClick = { onCancel() }) {
                    Text("Cancel", color = MaterialTheme.colorScheme.error)
                }
            }
            Spacer(modifier = Modifier.height(10.dp))
            LinearProgressIndicator(
                progress = transfer.progress,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(6.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("${(transfer.progress * 100).toInt()}%", fontSize = 11.sp)
                val transferredMb = transfer.bytesTransferred / (1024 * 1024)
                val totalMb = transfer.totalBytes / (1024 * 1024)
                Text("$transferredMb / $totalMb MB", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
fun PeerCard(peer: PeerItem, onSendFile: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = when (peer.os.lowercase()) {
                    "darwin", "macos", "ios" -> Icons.Default.Laptop
                    "android" -> Icons.Default.Smartphone
                    else -> Icons.Default.Computer
                },
                contentDescription = peer.os,
                modifier = Modifier.size(28.dp),
                tint = if (peer.online) MaterialTheme.colorScheme.primary else Color.Gray
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(peer.displayName, fontWeight = FontWeight.Medium)
                peer.primaryIP?.let { ip ->
                    Text(ip, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Button(
                onClick = onSendFile,
                enabled = peer.online,
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
            ) {
                Text("Send", fontSize = 12.sp)
            }
        }
    }
}

@Composable
fun RecentTransferRow(transfer: TransferItem) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = if (transfer.isSuccess) Icons.Default.CheckCircle else Icons.Default.Error,
            contentDescription = null,
            tint = if (transfer.isSuccess) Color(0xFF4CAF50) else Color(0xFFF44336),
            modifier = Modifier.size(16.dp)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(transfer.fileName, modifier = Modifier.weight(1f), maxLines = 1, style = MaterialTheme.typography.bodyMedium)
        Text(
            if (transfer.isSuccess) "Completed" else "Failed",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
