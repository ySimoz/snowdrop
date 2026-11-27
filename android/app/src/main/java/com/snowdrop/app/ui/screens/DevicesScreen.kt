package com.snowdrop.app.ui.screens

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.snowdrop.app.domain.EngineStatus
import com.snowdrop.app.domain.PeerItem
import com.snowdrop.app.domain.SnowdropUiState
import com.snowdrop.app.domain.TransferItem
import com.snowdrop.app.ui.components.TransferProgressBlock
import com.snowdrop.app.ui.components.peerOsIcon
import com.snowdrop.app.ui.theme.SnowdropThemeTokens
import com.snowdrop.app.ui.theme.tabular

@Composable
fun DevicesScreen(
    uiState: SnowdropUiState,
    bottomPadding: Dp,
    onSearchQueryChange: (String) -> Unit,
    onChooseFiles: () -> Unit,
    onSendToPeer: (PeerItem) -> Unit,
    onCancelTransfer: (String) -> Unit
) {
    val palette = SnowdropThemeTokens.palette
    val context = LocalContext.current

    val peerActiveMap: Map<String, List<TransferItem>> = uiState.filteredPeers.associate { peer ->
        peer.id to uiState.activeTransfers.filter { tx -> matchesPeer(tx, peer) }
    }
    val matchedTransferIds = peerActiveMap.values.flatten().mapTo(HashSet()) { it.id }
    val unmatchedTransfers = uiState.activeTransfers.filterNot { it.id in matchedTransferIds }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = bottomPadding),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        val needsAuth = uiState.status as? EngineStatus.NeedsAuth
        if (needsAuth != null) {
            item(key = "auth_banner") {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = palette.surface),
                    border = BorderStroke(1.dp, palette.warning.copy(alpha = 0.45f))
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = "Tailscale sign-in required",
                            style = MaterialTheme.typography.titleSmall,
                            color = palette.textPrimary
                        )
                        Text(
                            text = "Sign in to discover devices on your Tailnet.",
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.textSecondary
                        )
                        Button(
                            onClick = {
                                if (needsAuth.url.isNotEmpty()) {
                                    CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(needsAuth.url))
                                }
                            },
                            enabled = needsAuth.url.isNotEmpty(),
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(10.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = palette.accent,
                                contentColor = palette.onAccent
                            )
                        ) {
                            Text(
                                text = if (needsAuth.url.isEmpty()) "Preparing sign-in link" else "Sign in with Tailscale",
                                style = MaterialTheme.typography.labelMedium
                            )
                        }
                    }
                }
            }
        }

        if (unmatchedTransfers.isNotEmpty()) {
            items(unmatchedTransfers, key = { "unmatched_${it.id}" }) { transfer ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = palette.surface),
                    border = BorderStroke(1.dp, palette.hairline)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = transfer.fileName,
                                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                                color = palette.textPrimary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = transfer.peerName,
                                style = MaterialTheme.typography.bodySmall,
                                color = palette.textSecondary
                            )
                        }
                        TransferProgressBlock(
                            transfer = transfer,
                            onCancel = { onCancelTransfer(transfer.id) }
                        )
                    }
                }
            }
        }

        if (uiState.stagedFiles.isEmpty()) {
            item(key = "choose_files") {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onChooseFiles),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = palette.surface),
                    border = BorderStroke(1.dp, palette.hairline)
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.AttachFile,
                            contentDescription = null,
                            tint = palette.accent,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "Choose Files",
                            style = MaterialTheme.typography.titleSmall,
                            color = palette.textPrimary
                        )
                    }
                }
            }
        }

        if (uiState.peers.isNotEmpty()) {
            item(key = "search_bar") {
                OutlinedTextField(
                    value = uiState.searchQuery,
                    onValueChange = onSearchQueryChange,
                    placeholder = { Text("Search", style = MaterialTheme.typography.bodyMedium) },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Outlined.Search,
                            contentDescription = null,
                            tint = palette.textSecondary,
                            modifier = Modifier.size(18.dp)
                        )
                    },
                    trailingIcon = if (uiState.searchQuery.isNotEmpty()) {
                        {
                            IconButton(onClick = { onSearchQueryChange("") }) {
                                Icon(
                                    imageVector = Icons.Outlined.Close,
                                    contentDescription = "Clear search",
                                    tint = palette.textSecondary,
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                        }
                    } else null,
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = palette.accent,
                        unfocusedBorderColor = palette.hairline,
                        focusedContainerColor = palette.surface,
                        unfocusedContainerColor = palette.surface
                    ),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        item(key = "devices_header") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Devices (${uiState.filteredPeers.size})",
                    style = MaterialTheme.typography.titleSmall.tabular(),
                    color = palette.textSecondary
                )
                if (uiState.peers.isNotEmpty()) {
                    Text(
                        text = "${uiState.onlinePeerCount} online",
                        style = MaterialTheme.typography.bodySmall.tabular(),
                        color = palette.textMuted
                    )
                }
            }
        }

        if (uiState.filteredPeers.isEmpty()) {
            item(key = "empty_devices") {
                SectionEmptyCard(
                    icon = Icons.Outlined.Devices,
                    title = if (uiState.searchQuery.isNotBlank()) "No matching devices" else "No devices found",
                    subtitle = when {
                        uiState.searchQuery.isNotBlank() -> "Try a different search filter"
                        uiState.status is EngineStatus.NeedsAuth -> "Sign in with Tailscale to discover your devices"
                        uiState.status is EngineStatus.Connected -> "Waiting for peers on your Tailnet"
                        else -> "Connecting to Tailnet"
                    }
                )
            }
        } else {
            items(uiState.filteredPeers, key = { it.id }) { peer ->
                val peerTransfers = peerActiveMap[peer.id].orEmpty()
                PeerCard(
                    peer = peer,
                    canSend = peer.online && peer.primaryIP != null && uiState.stagedFiles.isNotEmpty(),
                    transfers = peerTransfers,
                    onSend = { onSendToPeer(peer) },
                    onCancelTransfer = onCancelTransfer
                )
            }
        }
    }
}

private fun matchesPeer(transfer: TransferItem, peer: PeerItem): Boolean =
    transfer.peerName == peer.displayName ||
        transfer.peerName == peer.hostName ||
        peer.ipAddresses.contains(transfer.peerName)

@Composable
private fun PeerCard(
    peer: PeerItem,
    canSend: Boolean,
    transfers: List<TransferItem>,
    onSend: () -> Unit,
    onCancelTransfer: (String) -> Unit
) {
    val palette = SnowdropThemeTokens.palette

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = palette.surface),
        border = BorderStroke(1.dp, palette.hairline)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(palette.surfaceElevated),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = peerOsIcon(peer.os),
                        contentDescription = null,
                        tint = if (peer.online) palette.accent else palette.textMuted,
                        modifier = Modifier.size(18.dp)
                    )
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = peer.displayName,
                        style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                        color = palette.textPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .clip(CircleShape)
                                .background(if (peer.online) palette.positive else palette.textMuted)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = if (peer.online) "Online" else "Offline",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (peer.online) palette.textSecondary else palette.textMuted
                        )
                    }
                }

                Spacer(modifier = Modifier.width(8.dp))

                Button(
                    onClick = onSend,
                    enabled = canSend,
                    modifier = Modifier.height(36.dp),
                    shape = RoundedCornerShape(10.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.accent,
                        contentColor = palette.onAccent,
                        disabledContainerColor = palette.surfaceElevated,
                        disabledContentColor = palette.textMuted
                    ),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 0.dp)
                ) {
                    Text(
                        text = "Send",
                        style = MaterialTheme.typography.labelMedium
                    )
                }
            }

            transfers.forEach { transfer ->
                TransferProgressBlock(
                    transfer = transfer,
                    onCancel = { onCancelTransfer(transfer.id) }
                )
            }
        }
    }
}
