package com.snowdrop.app.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.snowdrop.app.data.ReceivedFileStorage
import com.snowdrop.app.domain.SnowdropUiState
import com.snowdrop.app.ui.theme.SnowdropThemeTokens

@Composable
fun SettingsScreen(
    uiState: SnowdropUiState,
    bottomPadding: Dp,
    onRequestRename: () -> Unit,
    onChooseFolder: () -> Unit,
    onResetFolder: () -> Unit,
    onApprovalConfigChange: (Boolean, Boolean) -> Unit,
    onRestartEngine: () -> Unit,
    onSignOut: () -> Unit
) {
    val palette = SnowdropThemeTokens.palette

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = bottomPadding),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item(key = "settings_device") {
            SettingsGroupCard(title = "Device") {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = uiState.deviceName,
                        style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                        color = palette.textPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(
                        onClick = onRequestRename,
                        enabled = !uiState.isRestarting
                    ) {
                        Text("Rename", style = MaterialTheme.typography.labelMedium, color = palette.accent)
                    }
                }
            }
        }

        item(key = "settings_downloads") {
            SettingsGroupCard(title = "Downloads") {
                Text(
                    text = uiState.downloadLocationName,
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = onChooseFolder,
                        shape = RoundedCornerShape(10.dp),
                        border = BorderStroke(1.dp, palette.hairline)
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.FolderOpen,
                            contentDescription = null,
                            tint = palette.textSecondary,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Choose Folder", style = MaterialTheme.typography.labelMedium, color = palette.textPrimary)
                    }

                    if (uiState.downloadLocationName != ReceivedFileStorage.DEFAULT_LOCATION_NAME) {
                        OutlinedButton(
                            onClick = onResetFolder,
                            shape = RoundedCornerShape(10.dp),
                            border = BorderStroke(1.dp, palette.hairline)
                        ) {
                            Text("Reset", style = MaterialTheme.typography.labelMedium, color = palette.textSecondary)
                        }
                    }
                }
            }
        }

        item(key = "settings_approvals") {
            SettingsGroupCard(title = "Approvals") {
                SettingToggleRow(
                    label = "Require approval for new devices",
                    checked = uiState.requireApproval,
                    onCheckedChange = { onApprovalConfigChange(it, uiState.autoAcceptTrusted) }
                )
                SettingToggleRow(
                    label = "Auto-accept from trusted",
                    checked = uiState.autoAcceptTrusted,
                    onCheckedChange = { onApprovalConfigChange(uiState.requireApproval, it) }
                )
            }
        }

        item(key = "settings_network_account") {
            SettingsGroupCard(title = "Network & account") {
                OutlinedButton(
                    onClick = onRestartEngine,
                    enabled = !uiState.isRestarting,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(40.dp),
                    shape = RoundedCornerShape(10.dp),
                    border = BorderStroke(1.dp, palette.hairline)
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Refresh,
                        contentDescription = null,
                        tint = palette.textSecondary,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = if (uiState.isRestarting) "Restarting Network Stack" else "Restart Network Stack",
                        style = MaterialTheme.typography.labelMedium,
                        color = palette.textPrimary
                    )
                }

                OutlinedButton(
                    onClick = onSignOut,
                    enabled = !uiState.isSigningOut,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(40.dp),
                    shape = RoundedCornerShape(10.dp),
                    border = BorderStroke(1.dp, palette.critical.copy(alpha = 0.45f)),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = palette.critical)
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Outlined.Logout,
                        contentDescription = null,
                        tint = palette.critical,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Sign Out",
                        style = MaterialTheme.typography.labelMedium,
                        color = palette.critical
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingsGroupCard(
    title: String,
    content: @Composable ColumnScope.() -> Unit
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
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                color = palette.textSecondary
            )
            content()
        }
    }
}

@Composable
private fun SettingToggleRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    val palette = SnowdropThemeTokens.palette
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
            modifier = Modifier.weight(1f)
        )
        Spacer(modifier = Modifier.width(12.dp))
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange
        )
    }
}
