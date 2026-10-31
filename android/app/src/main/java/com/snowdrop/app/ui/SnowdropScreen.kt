package com.snowdrop.app.ui

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.snowdrop.app.R
import com.snowdrop.app.core.EngineStatus
import com.snowdrop.app.core.PeerItem
import com.snowdrop.app.core.SnowdropCoreBridge
import com.snowdrop.app.core.TransferItem
import com.snowdrop.app.service.TransferService
import com.snowdrop.app.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SnowdropScreen() {
    val context = LocalContext.current
    val status by SnowdropCoreBridge.status.collectAsState()
    val peers by SnowdropCoreBridge.peers.collectAsState()
    val activeTransfer by SnowdropCoreBridge.activeTransfer.collectAsState()
    val recentTransfers by SnowdropCoreBridge.recentTransfers.collectAsState()
    val currentDeviceName by SnowdropCoreBridge.deviceName.collectAsState()
    val downloadLocationName by SnowdropCoreBridge.downloadLocationName.collectAsState()
    val pendingApproval by SnowdropCoreBridge.pendingApproval.collectAsState()
    val trustedPeers by SnowdropCoreBridge.trustedPeers.collectAsState()
    val requireApproval by SnowdropCoreBridge.requireApproval.collectAsState()
    val autoAccept by SnowdropCoreBridge.autoAccept.collectAsState()

    var stagedFiles by remember { mutableStateOf<List<SnowdropCoreBridge.StagedFile>>(emptyList()) }
    var showRenameDialog by remember { mutableStateOf(false) }
    var showSettingsSheet by remember { mutableStateOf(false) }
    var renameInputText by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        SnowdropCoreBridge.refreshTrustedPeers()
    }

    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetMultipleContents()
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) {
            val existing = stagedFiles.map { it.uri }.toSet()
            val newFiles = uris.filter { it !in existing }.map { SnowdropCoreBridge.getFileInfo(context, it) }
            stagedFiles = stagedFiles + newFiles
        }
    }

    val directoryPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? ->
        if (uri != null) {
            SnowdropCoreBridge.setCustomDownloadTreeUri(context, uri)
        }
    }

    if (showRenameDialog) {
        AlertDialog(
            onDismissRequest = { showRenameDialog = false },
            containerColor = FrostSlate800,
            title = {
                Text(
                    "Rename Device",
                    color = FrostSlate100,
                    fontWeight = FontWeight.Bold
                )
            },
            text = {
                OutlinedTextField(
                    value = renameInputText,
                    onValueChange = { renameInputText = it },
                    label = { Text("Device Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = FrostSlate100,
                        unfocusedTextColor = FrostSlate100,
                        focusedBorderColor = FrostIceBlue,
                        unfocusedBorderColor = FrostSlate600,
                        focusedLabelColor = FrostIceBlue,
                        unfocusedLabelColor = FrostSlate400
                    )
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        SnowdropCoreBridge.setDeviceName(context, renameInputText)
                        showRenameDialog = false
                    },
                    enabled = renameInputText.isNotBlank(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = FrostIceBlue,
                        contentColor = FrostSlate950
                    )
                ) {
                    Text("Save", fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { showRenameDialog = false }) {
                    Text("Cancel", color = FrostSlate400)
                }
            }
        )
    }

    Scaffold(
        containerColor = FrostSlate900,
        topBar = {
            TopAppBar(
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = FrostSlate900,
                    titleContentColor = FrostSlate100
                ),
                title = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(start = 2.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(34.dp)
                                .clip(RoundedCornerShape(9.dp))
                                .background(FrostIceBlue.copy(alpha = 0.15f))
                                .border(1.dp, FrostIceBlue.copy(alpha = 0.3f), RoundedCornerShape(9.dp)),
                            contentAlignment = Alignment.Center
                        ) {
                            Image(
                                painter = painterResource(id = R.drawable.ic_snowdrop_flower),
                                contentDescription = "Snowdrop",
                                modifier = Modifier.size(22.dp)
                            )
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Column {
                            Text(
                                "Snowdrop",
                                fontWeight = FontWeight.Bold,
                                fontSize = 18.sp,
                                color = FrostSlate100
                            )
                            Text(
                                currentDeviceName.ifEmpty { "Android" },
                                fontSize = 12.sp,
                                color = FrostSlate400,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                },
                actions = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(end = 6.dp)
                    ) {
                        StatusPill(status = status)
                        Spacer(modifier = Modifier.width(4.dp))
                        IconButton(
                            onClick = { showSettingsSheet = true },
                            modifier = Modifier.size(38.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.Settings,
                                contentDescription = "Settings",
                                tint = FrostSlate400,
                                modifier = Modifier.size(22.dp)
                            )
                        }
                    }
                }
            )
        }
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = 20.dp,
                end = 20.dp,
                top = paddingValues.calculateTopPadding() + 18.dp,
                bottom = paddingValues.calculateBottomPadding() + 28.dp
            ),
            verticalArrangement = Arrangement.spacedBy(26.dp)
        ) {
            // Incoming Approval Banner
            if (pendingApproval != null) {
                item {
                    val req = pendingApproval!!
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(14.dp),
                        colors = CardDefaults.cardColors(containerColor = FrostSlate800),
                        border = BorderStroke(1.dp, FrostIceBlue.copy(alpha = 0.5f))
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(14.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    modifier = Modifier
                                        .size(26.dp)
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(FrostIceBlue.copy(alpha = 0.15f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.Security,
                                        contentDescription = null,
                                        tint = FrostIceBlue,
                                        modifier = Modifier.size(15.dp)
                                    )
                                }
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    "Transfer Request",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = FrostSlate100
                                )
                            }
                            Text(
                                "${req.senderName} wants to send ${req.fileName} (${req.formattedSize})",
                                style = MaterialTheme.typography.bodyMedium,
                                color = FrostSlate400
                            )
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 2.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Button(
                                    onClick = { SnowdropCoreBridge.resolveApproval(req.transferId, 1) },
                                    modifier = Modifier
                                        .weight(1f)
                                        .height(36.dp),
                                    shape = RoundedCornerShape(8.dp),
                                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp),
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = FrostIceBlue,
                                        contentColor = FrostSlate950
                                    )
                                ) {
                                    Text(
                                        "Accept",
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 12.sp,
                                        maxLines = 1
                                    )
                                }

                                OutlinedButton(
                                    onClick = { SnowdropCoreBridge.resolveApproval(req.transferId, 2) },
                                    modifier = Modifier
                                        .weight(1.25f)
                                        .height(36.dp),
                                    shape = RoundedCornerShape(8.dp),
                                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp),
                                    border = BorderStroke(1.dp, FrostIceBlue.copy(alpha = 0.4f)),
                                    colors = ButtonDefaults.outlinedButtonColors(
                                        containerColor = FrostIceBlue.copy(alpha = 0.12f),
                                        contentColor = FrostIceBlue
                                    )
                                ) {
                                    Text(
                                        "Always Trust",
                                        fontWeight = FontWeight.SemiBold,
                                        fontSize = 12.sp,
                                        maxLines = 1
                                    )
                                }

                                OutlinedButton(
                                    onClick = { SnowdropCoreBridge.resolveApproval(req.transferId, 3) },
                                    modifier = Modifier
                                        .weight(1f)
                                        .height(36.dp),
                                    shape = RoundedCornerShape(8.dp),
                                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp),
                                    border = BorderStroke(1.dp, FrostRose.copy(alpha = 0.4f)),
                                    colors = ButtonDefaults.outlinedButtonColors(
                                        containerColor = FrostRose.copy(alpha = 0.12f),
                                        contentColor = FrostRose
                                    )
                                ) {
                                    Text(
                                        "Decline",
                                        fontWeight = FontWeight.SemiBold,
                                        fontSize = 12.sp,
                                        color = FrostRose,
                                        maxLines = 1
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Tailscale Auth Banner
            if (status is EngineStatus.NeedsAuth) {
                item {
                    val authUrl = (status as EngineStatus.NeedsAuth).url
                    Card(
                        colors = CardDefaults.cardColors(containerColor = FrostAmber.copy(alpha = 0.15f)),
                        border = BorderStroke(1.dp, FrostAmber.copy(alpha = 0.35f)),
                        shape = RoundedCornerShape(14.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(14.dp)) {
                            Text(
                                "Tailscale Sign-in Required",
                                fontWeight = FontWeight.Bold,
                                style = MaterialTheme.typography.titleSmall,
                                color = FrostAmber
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                "Sign in to discover devices on your Tailnet.",
                                style = MaterialTheme.typography.bodySmall,
                                color = FrostSlate400
                            )
                            Spacer(modifier = Modifier.height(10.dp))
                            Button(
                                onClick = {
                                    if (authUrl.isNotEmpty()) {
                                        val customTabs = CustomTabsIntent.Builder().build()
                                        customTabs.launchUrl(context, Uri.parse(authUrl))
                                    }
                                },
                                enabled = authUrl.isNotEmpty(),
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(10.dp),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = FrostAmber,
                                    contentColor = FrostSlate950
                                )
                            ) {
                                Text("Sign in with Tailscale", fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }

            // Standalone Active Transfer Card (only when peer is not in visible list)
            activeTransfer?.let { transfer ->
                val isMatchedToVisiblePeer = peers.any { p ->
                    p.displayName == transfer.peerName ||
                    p.hostName == transfer.peerName ||
                    p.ipAddresses.contains(transfer.peerName)
                }
                if (!isMatchedToVisiblePeer) {
                    item {
                        Text(
                            "TRANSFERRING",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = FrostIceBlue,
                            fontSize = 11.sp
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        ActiveTransferCard(
                            transfer = transfer,
                            onCancel = { SnowdropCoreBridge.cancelTransfer(transfer.id) }
                        )
                    }
                }
            }

            // Staged File Section
            item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        "FILE",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = FrostSlate400,
                        fontSize = 11.sp,
                        letterSpacing = 0.8.sp
                    )

                    if (stagedFiles.isEmpty()) {
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { filePickerLauncher.launch("*/*") },
                            shape = RoundedCornerShape(16.dp),
                            colors = CardDefaults.cardColors(containerColor = GlassCardBg),
                            border = BorderStroke(1.dp, GlassBorderMuted)
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 24.dp, horizontal = 20.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(46.dp)
                                        .clip(CircleShape)
                                        .background(FrostIceBlue.copy(alpha = 0.12f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.AttachFile,
                                        contentDescription = null,
                                        tint = FrostIceBlue,
                                        modifier = Modifier.size(24.dp)
                                    )
                                }
                                Spacer(modifier = Modifier.height(10.dp))
                                Text(
                                    "Choose Files",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    color = FrostSlate100
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    "Tap to select one or more files to send",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = FrostSlate400
                                )
                            }
                        }
                    } else {
                        val totalBytes = stagedFiles.sumOf { it.size }
                        val formattedTotal = when {
                            totalBytes >= 1024 * 1024 * 1024 -> String.format("%.2f GB", totalBytes.toDouble() / (1024 * 1024 * 1024))
                            totalBytes >= 1024 * 1024 -> String.format("%.1f MB", totalBytes.toDouble() / (1024 * 1024))
                            totalBytes >= 1024 -> String.format("%.0f KB", totalBytes.toDouble() / 1024)
                            totalBytes > 0 -> "$totalBytes B"
                            else -> "0 B"
                        }
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(16.dp),
                            colors = CardDefaults.cardColors(containerColor = GlassCardBg),
                            border = BorderStroke(1.dp, GlassBorder)
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(44.dp)
                                            .clip(RoundedCornerShape(10.dp))
                                            .background(FrostIceBlue.copy(alpha = 0.15f)),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.InsertDriveFile,
                                            contentDescription = null,
                                            tint = FrostIceBlue,
                                            modifier = Modifier.size(24.dp)
                                        )
                                    }
                                    Spacer(modifier = Modifier.width(14.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            if (stagedFiles.size == 1) stagedFiles[0].name else "${stagedFiles.size} files staged",
                                            style = MaterialTheme.typography.bodyLarge,
                                            fontWeight = FontWeight.SemiBold,
                                            color = FrostSlate100,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                        Spacer(modifier = Modifier.height(2.dp))
                                        Text(
                                            formattedTotal,
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = FrostSlate400
                                        )
                                    }
                                    IconButton(onClick = { stagedFiles = emptyList() }) {
                                        Icon(
                                            imageVector = Icons.Default.Close,
                                            contentDescription = "Clear",
                                            tint = FrostSlate400
                                        )
                                    }
                                }

                                if (stagedFiles.size > 1) {
                                    Column(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(FrostSlate900.copy(alpha = 0.5f))
                                            .padding(horizontal = 10.dp, vertical = 6.dp),
                                        verticalArrangement = Arrangement.spacedBy(4.dp)
                                    ) {
                                        stagedFiles.take(3).forEach { f ->
                                            Row(
                                                modifier = Modifier.fillMaxWidth(),
                                                horizontalArrangement = Arrangement.SpaceBetween
                                            ) {
                                                Text(
                                                    f.name,
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = FrostSlate100,
                                                    maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis,
                                                    modifier = Modifier.weight(1f, fill = false)
                                                )
                                                Spacer(modifier = Modifier.width(8.dp))
                                                Text(
                                                    f.formattedSize,
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = FrostSlate400
                                                )
                                            }
                                        }
                                        if (stagedFiles.size > 3) {
                                            Text(
                                                "... and ${stagedFiles.size - 3} more",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = FrostIceBlue
                                            )
                                        }
                                    }
                                }

                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.End
                                ) {
                                    TextButton(
                                        onClick = { filePickerLauncher.launch("*/*") },
                                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp)
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Add,
                                            contentDescription = null,
                                            tint = FrostIceBlue,
                                            modifier = Modifier.size(16.dp)
                                        )
                                        Spacer(modifier = Modifier.width(4.dp))
                                        Text(
                                            "Add More Files",
                                            color = FrostIceBlue,
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.SemiBold
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Devices Section
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "DEVICES (${peers.size})",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = FrostSlate400,
                            fontSize = 11.sp,
                            letterSpacing = 0.8.sp
                        )
                        if (peers.isNotEmpty()) {
                            val onlineCount = peers.count { it.online }
                            Text(
                                "$onlineCount online",
                                style = MaterialTheme.typography.labelSmall,
                                color = FrostSlate400.copy(alpha = 0.7f),
                                fontSize = 11.sp
                            )
                        }
                    }

                    if (peers.isEmpty()) {
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(16.dp),
                            colors = CardDefaults.cardColors(containerColor = GlassCardBg),
                            border = BorderStroke(1.dp, GlassBorderMuted)
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 32.dp, horizontal = 20.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(44.dp)
                                        .clip(CircleShape)
                                        .background(FrostSlate700.copy(alpha = 0.4f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.Devices,
                                        contentDescription = null,
                                        tint = FrostSlate400,
                                        modifier = Modifier.size(22.dp)
                                    )
                                }
                                Spacer(modifier = Modifier.height(12.dp))
                                Text(
                                    when {
                                        status is EngineStatus.Connected -> "No other devices on Tailnet"
                                        status is EngineStatus.NeedsAuth -> "Sign in above to see devices"
                                        else -> "Connecting to network..."
                                    },
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = FrostSlate400
                                )
                            }
                        }
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            peers.forEach { peer ->
                                val isTransferringWithPeer = activeTransfer != null &&
                                    (activeTransfer?.peerName == peer.displayName ||
                                     activeTransfer?.peerName == peer.hostName ||
                                     peer.ipAddresses.contains(activeTransfer?.peerName))

                                PeerCard(
                                    peer = peer,
                                    hasStagedFile = stagedFiles.isNotEmpty(),
                                    transferItem = if (isTransferringWithPeer) activeTransfer else null,
                                    onSend = {
                                        if (stagedFiles.isNotEmpty()) {
                                            SnowdropCoreBridge.sendFiles(context, peer, stagedFiles)
                                            stagedFiles = emptyList()
                                        }
                                    },
                                    onCancelTransfer = {
                                        activeTransfer?.let { SnowdropCoreBridge.cancelTransfer(it.id) }
                                    }
                                )
                            }
                        }
                    }
                }
            }

            // Recent Transfers Section
            if (recentTransfers.isNotEmpty()) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "RECENT TRANSFERS",
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                color = FrostSlate400,
                                fontSize = 11.sp,
                                letterSpacing = 0.8.sp
                            )
                            TextButton(
                                onClick = { SnowdropCoreBridge.clearRecentTransfers() },
                                contentPadding = PaddingValues(0.dp)
                            ) {
                                Text(
                                    "Clear All",
                                    color = FrostRose,
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 11.sp
                                )
                            }
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            recentTransfers.forEach { recent ->
                                key(recent.id) {
                                    val dismissState = rememberSwipeToDismissBoxState(
                                        confirmValueChange = { value ->
                                            if (value == SwipeToDismissBoxValue.EndToStart || value == SwipeToDismissBoxValue.StartToEnd) {
                                                SnowdropCoreBridge.removeRecentTransfer(recent.id)
                                                true
                                            } else false
                                        }
                                    )
                                    SwipeToDismissBox(
                                        state = dismissState,
                                        backgroundContent = {
                                            Box(
                                                modifier = Modifier
                                                    .fillMaxSize()
                                                    .clip(RoundedCornerShape(12.dp))
                                                    .background(FrostRose.copy(alpha = 0.2f))
                                                    .padding(horizontal = 16.dp),
                                                contentAlignment = if (dismissState.dismissDirection == SwipeToDismissBoxValue.StartToEnd) Alignment.CenterStart else Alignment.CenterEnd
                                            ) {
                                                Icon(
                                                    imageVector = Icons.Default.Delete,
                                                    contentDescription = "Delete",
                                                    tint = FrostRose
                                                )
                                            }
                                        }
                                    ) {
                                        RecentTransferRow(transfer = recent)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            item {
                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }

    if (showSettingsSheet) {
        ModalBottomSheet(
            onDismissRequest = { showSettingsSheet = false },
            containerColor = FrostSlate900,
            dragHandle = {
                BottomSheetDefaults.DragHandle(color = FrostSlate600)
            }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp)
                    .navigationBarsPadding()
                    .padding(bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        "Settings",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = FrostSlate100
                    )
                    IconButton(
                        onClick = { showSettingsSheet = false },
                        modifier = Modifier.size(32.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Close",
                            tint = FrostSlate400
                        )
                    }
                }

                Divider(color = FrostSlate700.copy(alpha = 0.5f), thickness = 0.8.dp)

                // 1. Device Name
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        "DEVICE NAME",
                        style = MaterialTheme.typography.labelSmall,
                        color = FrostSlate400,
                        fontWeight = FontWeight.Bold
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            currentDeviceName.ifEmpty { "My Device" },
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.Medium,
                            color = FrostSlate100
                        )
                        TextButton(
                            onClick = {
                                renameInputText = currentDeviceName
                                showRenameDialog = true
                            }
                        ) {
                            Text("Rename", color = FrostIceBlue, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }

                Divider(color = FrostSlate700.copy(alpha = 0.5f), thickness = 0.8.dp)

                // 2. Storage Location
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        "STORAGE",
                        style = MaterialTheme.typography.labelSmall,
                        color = FrostSlate400,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        downloadLocationName,
                        style = MaterialTheme.typography.bodyMedium,
                        color = FrostSlate100,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        OutlinedButton(
                            onClick = { directoryPickerLauncher.launch(null) },
                            shape = RoundedCornerShape(8.dp),
                            border = BorderStroke(1.dp, FrostSlate600),
                            colors = ButtonDefaults.outlinedButtonColors(contentColor = FrostSlate100)
                        ) {
                            Text("Change Folder...", fontSize = 12.sp)
                        }
                        if (downloadLocationName != "Downloads/Snowdrop") {
                            OutlinedButton(
                                onClick = { SnowdropCoreBridge.setCustomDownloadTreeUri(context, null) },
                                shape = RoundedCornerShape(8.dp),
                                border = BorderStroke(1.dp, FrostSlate700),
                                colors = ButtonDefaults.outlinedButtonColors(contentColor = FrostSlate400)
                            ) {
                                Text("Reset", fontSize = 12.sp)
                            }
                        }
                    }
                }

                Divider(color = FrostSlate700.copy(alpha = 0.5f), thickness = 0.8.dp)

                // 3. Security & Approvals
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        "SECURITY & APPROVALS",
                        style = MaterialTheme.typography.labelSmall,
                        color = FrostSlate400,
                        fontWeight = FontWeight.Bold
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            "Require Approval for New Devices",
                            style = MaterialTheme.typography.bodyMedium,
                            color = FrostSlate100,
                            modifier = Modifier.weight(1f)
                        )
                        Switch(
                            checked = requireApproval,
                            onCheckedChange = { SnowdropCoreBridge.setApprovalConfig(it, autoAccept) },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = FrostIceBlue,
                                checkedTrackColor = FrostIceBlue.copy(alpha = 0.3f)
                            )
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            "Auto-accept from Trusted",
                            style = MaterialTheme.typography.bodyMedium,
                            color = FrostSlate100,
                            modifier = Modifier.weight(1f)
                        )
                        Switch(
                            checked = autoAccept,
                            onCheckedChange = { SnowdropCoreBridge.setApprovalConfig(requireApproval, it) },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = FrostIceBlue,
                                checkedTrackColor = FrostIceBlue.copy(alpha = 0.3f)
                            )
                        )
                    }

                    Text(
                        "Trusted Devices (${trustedPeers.size})",
                        style = MaterialTheme.typography.labelSmall,
                        color = FrostSlate400,
                        fontWeight = FontWeight.SemiBold
                    )

                    if (trustedPeers.isEmpty()) {
                        Text(
                            "No trusted devices yet",
                            style = MaterialTheme.typography.bodySmall,
                            color = FrostSlate400.copy(alpha = 0.7f)
                        )
                    } else {
                        trustedPeers.forEach { peer ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    peer.deviceName,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = FrostSlate100,
                                    modifier = Modifier.weight(1f)
                                )
                                TextButton(onClick = { SnowdropCoreBridge.revokeTrustedPeer(peer.nodeId) }) {
                                    Text("Revoke", color = FrostRose, fontSize = 12.sp)
                                }
                            }
                        }
                    }
                }

                Divider(color = FrostSlate700.copy(alpha = 0.5f), thickness = 0.8.dp)

                // 4. Network Stack
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "NETWORK",
                        style = MaterialTheme.typography.labelSmall,
                        color = FrostSlate400,
                        fontWeight = FontWeight.Bold
                    )
                    OutlinedButton(
                        onClick = {
                            SnowdropCoreBridge.restart(context)
                            Toast.makeText(context, "Restarting network stack...", Toast.LENGTH_SHORT).show()
                        },
                        modifier = Modifier.fillMaxWidth().height(40.dp),
                        shape = RoundedCornerShape(8.dp),
                        border = BorderStroke(1.dp, FrostSlate700),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = FrostSlate100)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = null,
                            tint = FrostSlate400,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Restart Network Stack", fontSize = 12.sp)
                    }
                }

                Divider(color = FrostSlate700.copy(alpha = 0.5f), thickness = 0.8.dp)

                // 5. Account & Session
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "ACCOUNT",
                        style = MaterialTheme.typography.labelSmall,
                        color = FrostSlate400,
                        fontWeight = FontWeight.Bold
                    )
                    OutlinedButton(
                        onClick = {
                            SnowdropCoreBridge.signOut()
                            showSettingsSheet = false
                            Toast.makeText(context, "Signed out and unlinked", Toast.LENGTH_SHORT).show()
                        },
                        modifier = Modifier.fillMaxWidth().height(40.dp),
                        shape = RoundedCornerShape(8.dp),
                        border = BorderStroke(1.dp, FrostRose.copy(alpha = 0.5f)),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = FrostRose)
                    ) {
                        Icon(
                            imageVector = Icons.Default.ExitToApp,
                            contentDescription = null,
                            tint = FrostRose,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Sign Out & Unlink Device", fontSize = 12.sp, color = FrostRose)
                    }
                }
            }
        }
    }
}

@Composable
fun StatusPill(status: EngineStatus) {
    val (dotColor, label) = when (status) {
        is EngineStatus.Connected -> FrostEmerald to "Online"
        is EngineStatus.NeedsAuth -> FrostAmber to "Sign In"
        is EngineStatus.Connecting -> FrostIceBlue to "Connecting"
        else -> FrostSlate600 to "Offline"
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .background(dotColor.copy(alpha = 0.12f), shape = RoundedCornerShape(16.dp))
            .border(1.dp, dotColor.copy(alpha = 0.3f), RoundedCornerShape(16.dp))
            .padding(horizontal = 10.dp, vertical = 5.dp)
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(12.dp)) {
            if (status is EngineStatus.Connected) {
                Box(
                    modifier = Modifier
                        .size(12.dp)
                        .clip(CircleShape)
                        .background(dotColor.copy(alpha = 0.3f))
                )
            }
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(dotColor)
            )
        }
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = dotColor
        )
    }
}

@Composable
fun GlowingHaloDot(online: Boolean, isTransferring: Boolean = false) {
    val dotColor = if (isTransferring) FrostIceBlue else if (online) FrostEmerald else FrostSlate600
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(14.dp)) {
        if (online || isTransferring) {
            Box(
                modifier = Modifier
                    .size(14.dp)
                    .clip(CircleShape)
                    .background(dotColor.copy(alpha = 0.3f))
            )
        }
        Box(
            modifier = Modifier
                .size(7.dp)
                .clip(CircleShape)
                .background(dotColor)
        )
    }
}

@Composable
fun PeerCard(
    peer: PeerItem,
    hasStagedFile: Boolean,
    transferItem: TransferItem?,
    onSend: () -> Unit,
    onCancelTransfer: () -> Unit
) {
    val isTransferring = transferItem != null

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (isTransferring) FrostSlate800 else GlassCardBg
        ),
        border = BorderStroke(
            1.dp,
            if (isTransferring) FrostIceBlue.copy(alpha = 0.5f)
            else if (peer.online) GlassBorder
            else GlassBorderMuted
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(42.dp)
                        .clip(CircleShape)
                        .background(
                            if (peer.online) FrostIceBlue.copy(alpha = 0.12f)
                            else FrostSlate700.copy(alpha = 0.4f)
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = when (peer.os.lowercase()) {
                            "darwin", "macos", "ios" -> Icons.Default.Laptop
                            "android" -> Icons.Default.Smartphone
                            else -> Icons.Default.Computer
                        },
                        contentDescription = null,
                        modifier = Modifier.size(22.dp),
                        tint = if (peer.online) FrostIceBlue else FrostSlate400
                    )
                }

                Spacer(modifier = Modifier.width(14.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        peer.displayName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = FrostSlate100,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(modifier = Modifier.height(3.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        GlowingHaloDot(online = peer.online, isTransferring = isTransferring)
                        Spacer(modifier = Modifier.width(6.dp))
                        val statusLabel = if (isTransferring && transferItem != null) {
                            if (transferItem.isIncoming) "Receiving file" else "Sending file"
                        } else {
                            if (peer.online) "Connected" else "Offline"
                        }
                        val statusTextColor = if (isTransferring) FrostIceBlue else if (peer.online) FrostEmerald else FrostSlate400
                        Text(
                            statusLabel,
                            style = MaterialTheme.typography.bodySmall,
                            color = statusTextColor,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }

                Spacer(modifier = Modifier.width(10.dp))

                if (isTransferring) {
                    IconButton(
                        onClick = onCancelTransfer,
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Cancel",
                            tint = FrostRose,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                } else {
                    Button(
                        onClick = onSend,
                        enabled = peer.online && hasStagedFile,
                        modifier = Modifier.height(38.dp),
                        shape = RoundedCornerShape(10.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = FrostIceBlue,
                            contentColor = FrostSlate950,
                            disabledContainerColor = FrostSlate700.copy(alpha = 0.4f),
                            disabledContentColor = FrostSlate600
                        ),
                        contentPadding = PaddingValues(horizontal = 18.dp, vertical = 0.dp)
                    ) {
                        Text("Send", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    }
                }
            }

            // In-Place Inline Progress Bar
            val active = transferItem
            if (active != null) {
                Spacer(modifier = Modifier.height(14.dp))
                if (active.isBatch && active.currentFileName.isNotEmpty()) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            "File ${active.fileIndex} of ${active.totalFiles}: ${active.currentFileName}",
                            style = MaterialTheme.typography.labelSmall,
                            color = FrostSlate100,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                }
                LinearProgressIndicator(
                    progress = { active.progress },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(6.dp)
                        .clip(RoundedCornerShape(3.dp)),
                    color = FrostIceBlue,
                    trackColor = FrostSlate700
                )
                Spacer(modifier = Modifier.height(6.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        "${(active.progress * 100).toInt()}% • ${active.fileName}",
                        style = MaterialTheme.typography.labelSmall,
                        color = FrostSlate400,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    val transferredMb = active.bytesTransferred.toDouble() / (1024 * 1024)
                    val totalMb = active.totalBytes.toDouble() / (1024 * 1024)
                    Text(
                        String.format("%.1f / %.1f MB", transferredMb, totalMb),
                        style = MaterialTheme.typography.labelSmall,
                        color = FrostIceBlue
                    )
                }
            }
        }
    }
}

@Composable
fun ActiveTransferCard(transfer: TransferItem, onCancel: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = FrostSlate800),
        border = BorderStroke(1.dp, FrostIceBlue.copy(alpha = 0.4f))
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = if (transfer.isIncoming) Icons.Default.ArrowDownward else Icons.Default.ArrowUpward,
                    contentDescription = null,
                    tint = if (transfer.isIncoming) FrostEmerald else FrostIceBlue,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        transfer.fileName,
                        fontWeight = FontWeight.Bold,
                        color = FrostSlate100,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        if (transfer.isIncoming) "From ${transfer.peerName}" else "To ${transfer.peerName}",
                        style = MaterialTheme.typography.bodySmall,
                        color = FrostSlate400
                    )
                }
                IconButton(onClick = onCancel) {
                    Icon(Icons.Default.Close, contentDescription = "Cancel", tint = FrostRose)
                }
            }
            Spacer(modifier = Modifier.height(10.dp))
            if (transfer.isBatch && transfer.currentFileName.isNotEmpty()) {
                Text(
                    "File ${transfer.fileIndex} of ${transfer.totalFiles}: ${transfer.currentFileName}",
                    style = MaterialTheme.typography.labelSmall,
                    color = FrostSlate100,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(4.dp))
            }
            LinearProgressIndicator(
                progress = { transfer.progress },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .clip(RoundedCornerShape(3.dp)),
                color = FrostIceBlue,
                trackColor = FrostSlate700
            )
            Spacer(modifier = Modifier.height(6.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    "${(transfer.progress * 100).toInt()}%",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = FrostIceBlue
                )
                val transferredMb = transfer.bytesTransferred.toDouble() / (1024 * 1024)
                val totalMb = transfer.totalBytes.toDouble() / (1024 * 1024)
                Text(
                    String.format("%.1f / %.1f MB", transferredMb, totalMb),
                    fontSize = 12.sp,
                    color = FrostSlate400
                )
            }
        }
    }
}

@Composable
fun RecentTransferRow(transfer: TransferItem) {
    val context = LocalContext.current
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = GlassCardBg),
        border = BorderStroke(1.dp, GlassBorderMuted)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = if (transfer.isSuccess) Icons.Default.CheckCircle else Icons.Default.Cancel,
                contentDescription = null,
                tint = if (transfer.isSuccess) FrostEmerald else FrostRose,
                modifier = Modifier.size(18.dp)
            )
            Spacer(modifier = Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    transfer.fileName,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = FrostSlate100
                )
                Text(
                    if (transfer.isIncoming) "Received" else "Sent",
                    style = MaterialTheme.typography.labelSmall,
                    color = FrostSlate400
                )
            }
            if (transfer.isSuccess && transfer.isIncoming && transfer.fileUri != null) {
                Button(
                    onClick = {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(transfer.fileUri, context.contentResolver.getType(transfer.fileUri) ?: "*/*")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                            }
                            context.startActivity(intent)
                        } catch (_: Exception) {
                            Toast.makeText(context, "No app to open file", Toast.LENGTH_SHORT).show()
                        }
                    },
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = FrostIceBlue.copy(alpha = 0.15f),
                        contentColor = FrostIceBlue
                    ),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                    modifier = Modifier.height(30.dp)
                ) {
                    Text("Open", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                }
            } else {
                Text(
                    if (transfer.isSuccess) "Done" else "Failed",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (transfer.isSuccess) FrostEmerald else FrostRose,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}
