package com.snowdrop.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.snowdrop.app.domain.SnowdropFormat
import com.snowdrop.app.domain.SnowdropUiState
import com.snowdrop.app.domain.TransferDirection
import com.snowdrop.app.domain.TransferItem
import com.snowdrop.app.ui.components.TransferProgressBlock
import com.snowdrop.app.ui.theme.SnowdropThemeTokens
import com.snowdrop.app.ui.theme.tabular

@Composable
fun TransfersScreen(
    uiState: SnowdropUiState,
    bottomPadding: Dp,
    onCancelTransfer: (String) -> Unit,
    onRemoveRecent: (String) -> Unit,
    onClearRecent: () -> Unit,
    onOpenError: (String) -> Unit
) {
    val palette = SnowdropThemeTokens.palette
    val context = LocalContext.current

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = bottomPadding),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (uiState.activeTransfers.isNotEmpty()) {
            item(key = "active_header") {
                Text(
                    text = "Active (${uiState.activeTransfers.size})",
                    style = MaterialTheme.typography.titleSmall.tabular(),
                    color = palette.textSecondary
                )
            }
            items(uiState.activeTransfers, key = { "active_${it.id}" }) { transfer ->
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
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = if (transfer.direction == TransferDirection.INCOMING) {
                                    Icons.Outlined.ArrowDownward
                                } else {
                                    Icons.Outlined.ArrowUpward
                                },
                                contentDescription = null,
                                tint = if (transfer.direction == TransferDirection.INCOMING) palette.positive else palette.accent,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = transfer.fileName,
                                    style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                                    color = palette.textPrimary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = if (transfer.direction == TransferDirection.INCOMING) {
                                        "From ${transfer.peerName}"
                                    } else {
                                        "To ${transfer.peerName}"
                                    },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = palette.textSecondary
                                )
                            }
                        }

                        TransferProgressBlock(
                            transfer = transfer,
                            onCancel = { onCancelTransfer(transfer.id) }
                        )
                    }
                }
            }
        }

        item(key = "recent_header") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Recent (${uiState.recentTransfers.size})",
                    style = MaterialTheme.typography.titleSmall.tabular(),
                    color = palette.textSecondary
                )
                if (uiState.recentTransfers.isNotEmpty()) {
                    TextButton(onClick = onClearRecent) {
                        Text(
                            text = "Clear All",
                            style = MaterialTheme.typography.labelMedium,
                            color = palette.critical
                        )
                    }
                }
            }
        }

        if (uiState.activeTransfers.isEmpty() && uiState.recentTransfers.isEmpty()) {
            item(key = "empty_transfers") {
                SectionEmptyCard(
                    icon = Icons.Outlined.SwapVert,
                    title = "No transfers yet",
                    subtitle = "Sent and received files appear here"
                )
            }
        } else {
            items(uiState.recentTransfers, key = { "recent_${it.id}" }) { transfer ->
                val dismissState = rememberSwipeToDismissBoxState(
                    confirmValueChange = { value ->
                        if (value == SwipeToDismissBoxValue.EndToStart || value == SwipeToDismissBoxValue.StartToEnd) {
                            onRemoveRecent(transfer.id)
                            true
                        } else {
                            false
                        }
                    }
                )
                SwipeToDismissBox(
                    state = dismissState,
                    backgroundContent = {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .clip(RoundedCornerShape(16.dp))
                                .background(palette.critical.copy(alpha = 0.14f))
                                .padding(horizontal = 16.dp),
                            contentAlignment = if (dismissState.dismissDirection == SwipeToDismissBoxValue.StartToEnd) {
                                Alignment.CenterStart
                            } else {
                                Alignment.CenterEnd
                            }
                        ) {
                            Icon(
                                imageVector = Icons.Outlined.Delete,
                                contentDescription = "Remove transfer",
                                tint = palette.critical,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                ) {
                    RecentTransferCard(
                        transfer = transfer,
                        onOpen = { uriStr ->
                            runCatching {
                                val uri = Uri.parse(uriStr)
                                val mime = context.contentResolver.getType(uri) ?: "*/*"
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, mime)
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                                }
                                context.startActivity(intent)
                            }.onFailure {
                                onOpenError("No app available to open ${transfer.fileName}")
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun RecentTransferCard(
    transfer: TransferItem,
    onOpen: (String) -> Unit
) {
    val palette = SnowdropThemeTokens.palette
    val directionLabel = if (transfer.direction == TransferDirection.INCOMING) "From ${transfer.peerName}" else "To ${transfer.peerName}"
    val metaLine = if (transfer.totalBytes > 0L) {
        "$directionLabel · ${SnowdropFormat.bytes(transfer.totalBytes)}"
    } else {
        directionLabel
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = palette.surface),
        border = BorderStroke(1.dp, palette.hairline)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = if (transfer.isSuccess) Icons.Outlined.CheckCircle else Icons.Outlined.ErrorOutline,
                contentDescription = null,
                tint = if (transfer.isSuccess) palette.positive else palette.critical,
                modifier = Modifier.size(18.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = transfer.fileName,
                    style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                    color = palette.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = transfer.errorMessage?.takeIf { !transfer.isSuccess } ?: metaLine,
                    style = MaterialTheme.typography.bodySmall.tabular(),
                    color = if (transfer.isSuccess) palette.textSecondary else palette.critical,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Spacer(modifier = Modifier.width(8.dp))
            val uri = transfer.destinationUriString
            if (transfer.isSuccess && transfer.direction == TransferDirection.INCOMING && uri != null) {
                Button(
                    onClick = { onOpen(uri) },
                    modifier = Modifier.height(32.dp),
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = palette.accent.copy(alpha = 0.14f),
                        contentColor = palette.accent
                    ),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp)
                ) {
                    Text("Open", style = MaterialTheme.typography.labelMedium)
                }
            } else {
                Text(
                    text = if (transfer.isSuccess) "Done" else "Failed",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (transfer.isSuccess) palette.positive else palette.critical
                )
            }
        }
    }
}
