package com.snowdrop.app.ui.screens

import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.snowdrop.app.R
import com.snowdrop.app.SnowdropApplication
import com.snowdrop.app.data.FileMetadataResolver
import com.snowdrop.app.data.SnowdropStore
import com.snowdrop.app.domain.AppTab
import com.snowdrop.app.domain.EngineStatus
import com.snowdrop.app.domain.SnowdropUiState
import com.snowdrop.app.ui.components.FloatingApprovalHud
import com.snowdrop.app.ui.components.FloatingStagedBar
import com.snowdrop.app.ui.components.RenameDeviceDialog
import com.snowdrop.app.ui.components.SnowdropGlassSurface
import com.snowdrop.app.ui.components.StagedFilesSheet
import com.snowdrop.app.ui.theme.SnowdropThemeTokens
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.haze
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun MainShellScreen(store: SnowdropStore) {
    val uiState by store.uiState.collectAsStateWithLifecycle()
    val palette = SnowdropThemeTokens.palette
    val context = LocalContext.current
    val app = context.applicationContext as SnowdropApplication
    val hazeState = remember { HazeState() }
    val coroutineScope = rememberCoroutineScope()

    var showRenameDialog by remember { mutableStateOf(false) }
    var showStagedSheet by remember { mutableStateOf(false) }

    LaunchedEffect(uiState.stagedFiles.isEmpty()) {
        if (uiState.stagedFiles.isEmpty()) {
            showStagedSheet = false
        }
    }

    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetMultipleContents()
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) {
            coroutineScope.launch {
                val resolved = withContext(Dispatchers.IO) {
                    FileMetadataResolver.resolveAll(context, uris)
                }
                store.stageFiles(resolved)
                store.selectTab(AppTab.DEVICES)
            }
        }
    }

    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? ->
        if (uri != null) {
            val location = app.storage.setCustomDownloadTreeUri(uri)
            store.setDownloadLocationName(location)
        }
    }

    if (showRenameDialog) {
        RenameDeviceDialog(
            currentName = uiState.deviceName,
            onDismiss = { showRenameDialog = false },
            onSave = { updated ->
                showRenameDialog = false
                store.renameDevice(updated)
            }
        )
    }

    if (showStagedSheet && uiState.stagedFiles.isNotEmpty()) {
        StagedFilesSheet(
            files = uiState.stagedFiles,
            totalBytes = uiState.stagedTotalBytes,
            onRemove = store::removeStagedFile,
            onDismiss = { showStagedSheet = false }
        )
    }

    val hasExtraChrome = uiState.pendingApprovals.isNotEmpty() ||
        uiState.stagedFiles.isNotEmpty() ||
        uiState.lastError != null
    val listBottomPadding = if (hasExtraChrome) 168.dp else 104.dp

    Scaffold(
        containerColor = palette.background,
        contentWindowInsets = WindowInsets(0, 0, 0, 0)
    ) { _ ->
        Box(modifier = Modifier.fillMaxSize()) {
            // Layer 1: Solid neutral content canvas feeding the Haze backdrop source
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .haze(state = hazeState)
                    .background(palette.background)
                    .statusBarsPadding()
            ) {
                TopHeaderBar(uiState = uiState)

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                ) {
                    when (uiState.selectedTab) {
                        AppTab.DEVICES -> DevicesScreen(
                            uiState = uiState,
                            bottomPadding = listBottomPadding,
                            onSearchQueryChange = store::setSearchQuery,
                            onChooseFiles = { filePickerLauncher.launch("*/*") },
                            onSendToPeer = { peer -> store.sendStagedFiles(peer) },
                            onCancelTransfer = store::cancelTransfer
                        )
                        AppTab.TRANSFERS -> TransfersScreen(
                            uiState = uiState,
                            bottomPadding = listBottomPadding,
                            onCancelTransfer = store::cancelTransfer,
                            onRemoveRecent = store::removeRecentTransfer,
                            onClearRecent = store::clearRecentTransfers,
                            onOpenError = store::reportError
                        )
                        AppTab.TRUSTED -> TrustedScreen(
                            uiState = uiState,
                            bottomPadding = listBottomPadding,
                            onRevoke = store::revokeTrustedPeer
                        )
                        AppTab.SETTINGS -> SettingsScreen(
                            uiState = uiState,
                            bottomPadding = listBottomPadding,
                            onRequestRename = { showRenameDialog = true },
                            onChooseFolder = { folderPickerLauncher.launch(null) },
                            onResetFolder = {
                                val defaultName = app.storage.setCustomDownloadTreeUri(null)
                                store.setDownloadLocationName(defaultName)
                            },
                            onApprovalConfigChange = store::updateApprovalConfig,
                            onRestartEngine = {
                                store.restart()
                                Toast.makeText(context, "Restarting network stack", Toast.LENGTH_SHORT).show()
                            },
                            onSignOut = {
                                store.signOut()
                                Toast.makeText(context, "Signed out", Toast.LENGTH_SHORT).show()
                            }
                        )
                    }
                }
            }

            // Layer 2: Floating Liquid Glass chrome anchored cleanly at bottom edge
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                val pending = uiState.pendingApprovals.firstOrNull()
                if (pending != null) {
                    FloatingApprovalHud(
                        hazeState = hazeState,
                        request = pending,
                        totalCount = uiState.pendingApprovals.size,
                        onDecision = { decision -> store.resolveApproval(pending.transferId, decision) }
                    )
                }

                if (uiState.lastError != null) {
                    SnowdropGlassSurface(
                        hazeState = hazeState,
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = Icons.Outlined.ErrorOutline,
                                contentDescription = null,
                                tint = palette.critical,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = uiState.lastError.orEmpty(),
                                style = MaterialTheme.typography.bodySmall,
                                color = palette.textPrimary,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f)
                            )
                            TextButton(
                                onClick = { store.dismissError() },
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp)
                            ) {
                                Text(
                                    text = "Dismiss",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = palette.accent
                                )
                            }
                        }
                    }
                }

                if (uiState.stagedFiles.isNotEmpty()) {
                    FloatingStagedBar(
                        hazeState = hazeState,
                        summaryText = uiState.stagedSummaryText,
                        totalBytes = uiState.stagedTotalBytes,
                        fileCount = uiState.stagedFiles.size,
                        onInspect = { showStagedSheet = true },
                        onAddMore = { filePickerLauncher.launch("*/*") },
                        onClear = store::clearStagedFiles
                    )
                }

                FloatingGlassNavBar(
                    hazeState = hazeState,
                    selectedTab = uiState.selectedTab,
                    hasActiveTransfers = uiState.activeTransfers.isNotEmpty(),
                    onSelectTab = store::selectTab
                )
            }
        }
    }
}

@Composable
private fun TopHeaderBar(uiState: SnowdropUiState) {
    val palette = SnowdropThemeTokens.palette
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.weight(1f)
        ) {
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(palette.surfaceElevated)
                    .border(1.dp, palette.hairline, RoundedCornerShape(8.dp)),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_snowdrop_flower),
                    contentDescription = "Snowdrop",
                    modifier = Modifier.size(20.dp)
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    text = "Snowdrop",
                    style = MaterialTheme.typography.titleMedium,
                    color = palette.textPrimary,
                    maxLines = 1
                )
                Text(
                    text = uiState.deviceName,
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        Spacer(modifier = Modifier.width(12.dp))
        StatusBadge(status = uiState.status)
    }
}

@Composable
private fun StatusBadge(status: EngineStatus) {
    val palette = SnowdropThemeTokens.palette
    val dotColor = when (status) {
        is EngineStatus.Connected -> palette.positive
        is EngineStatus.NeedsAuth -> palette.warning
        is EngineStatus.Connecting -> palette.accent
        is EngineStatus.Disconnected -> palette.textMuted
        is EngineStatus.Error -> palette.critical
    }

    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(palette.surface)
            .border(1.dp, palette.hairline, CircleShape)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(6.dp)
                .clip(CircleShape)
                .background(dotColor)
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = status.title,
            style = MaterialTheme.typography.labelSmall,
            color = palette.textSecondary
        )
    }
}

@Composable
fun SectionEmptyCard(
    icon: ImageVector,
    title: String,
    subtitle: String
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
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = palette.textSecondary,
                modifier = Modifier.size(24.dp)
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                color = palette.textPrimary
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary
            )
        }
    }
}

@Composable
private fun FloatingGlassNavBar(
    hazeState: HazeState,
    selectedTab: AppTab,
    hasActiveTransfers: Boolean,
    onSelectTab: (AppTab) -> Unit
) {
    val palette = SnowdropThemeTokens.palette

    SnowdropGlassSurface(
        hazeState = hazeState,
        shape = CircleShape,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            AppTab.entries.forEach { tab ->
                val isSelected = tab == selectedTab
                val icon = when (tab) {
                    AppTab.DEVICES -> Icons.Outlined.Devices
                    AppTab.TRANSFERS -> Icons.Outlined.SwapVert
                    AppTab.TRUSTED -> Icons.Outlined.Shield
                    AppTab.SETTINGS -> Icons.Outlined.Settings
                }
                val tint = if (isSelected) palette.accent else palette.textSecondary
                val pillColor = if (isSelected) palette.accent.copy(alpha = 0.12f) else Color.Transparent

                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .background(pillColor)
                        .clickable { onSelectTab(tab) }
                        .padding(vertical = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Box {
                        Icon(
                            imageVector = icon,
                            contentDescription = tab.label,
                            tint = tint,
                            modifier = Modifier.size(18.dp)
                        )
                        if (tab == AppTab.TRANSFERS && hasActiveTransfers) {
                            Box(
                                modifier = Modifier
                                    .align(Alignment.TopEnd)
                                    .size(6.dp)
                                    .clip(CircleShape)
                                    .background(palette.accent)
                            )
                        }
                    }
                    Text(
                        text = tab.label,
                        style = MaterialTheme.typography.labelSmall,
                        color = tint,
                        maxLines = 1
                    )
                }
            }
        }
    }
}
