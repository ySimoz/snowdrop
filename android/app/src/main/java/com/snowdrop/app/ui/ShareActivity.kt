package com.snowdrop.app.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.snowdrop.app.SnowdropApplication
import com.snowdrop.app.data.FileMetadataResolver
import com.snowdrop.app.domain.PeerItem
import com.snowdrop.app.domain.SnowdropFormat
import com.snowdrop.app.domain.StagedFile
import com.snowdrop.app.service.TransferService
import com.snowdrop.app.ui.components.SnowdropGlassSurface
import com.snowdrop.app.ui.components.peerOsIcon
import com.snowdrop.app.ui.theme.SnowdropTheme
import com.snowdrop.app.ui.theme.SnowdropThemeTokens
import com.snowdrop.app.ui.theme.tabular
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class ShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
        )
        super.onCreate(savedInstanceState)

        val uris = extractUris(intent)
        if (uris.isEmpty()) {
            finish()
            return
        }

        val app = application as SnowdropApplication
        val store = app.store

        setContent {
            SnowdropTheme {
                val uiState by store.uiState.collectAsStateWithLifecycle()
                var stagedFiles by remember { mutableStateOf<List<StagedFile>>(emptyList()) }
                val palette = SnowdropThemeTokens.palette

                LaunchedEffect(uris) {
                    stagedFiles = withContext(Dispatchers.IO) {
                        FileMetadataResolver.resolveAll(this@ShareActivity, uris)
                    }
                }

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.45f))
                        .clickable(onClick = { finish() }),
                    contentAlignment = Alignment.BottomCenter
                ) {
                    SnowdropGlassSurface(
                        hazeState = null,
                        shape = RoundedCornerShape(24.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .navigationBarsPadding()
                            .padding(16.dp)
                            .clickable(enabled = false, onClick = {})
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            val totalBytes = stagedFiles.sumOf { it.byteSize }
                            val fileSummary = when {
                                stagedFiles.isEmpty() -> "${uris.size} items"
                                stagedFiles.size == 1 -> stagedFiles.first().name
                                else -> "${stagedFiles.size} files"
                            }

                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(
                                    text = "Send with Snowdrop",
                                    style = MaterialTheme.typography.titleMedium,
                                    color = palette.textPrimary
                                )
                                Text(
                                    text = if (totalBytes > 0L) "$fileSummary · ${SnowdropFormat.bytes(totalBytes)}" else fileSummary,
                                    style = MaterialTheme.typography.bodySmall.tabular(),
                                    color = palette.textSecondary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            val onlinePeers = uiState.filteredPeers.filter { it.online }
                            if (onlinePeers.isEmpty()) {
                                Text(
                                    text = "No online devices found on your Tailnet",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = palette.textSecondary,
                                    modifier = Modifier.padding(vertical = 12.dp)
                                )
                            } else {
                                LazyColumn(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .heightIn(max = 260.dp),
                                    verticalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    items(onlinePeers, key = { it.id }) { peer ->
                                        SharePeerRow(
                                            peer = peer,
                                            enabled = stagedFiles.isNotEmpty()
                                        ) {
                                            TransferService.start(this@ShareActivity)
                                            store.sendDirectFiles(peer, stagedFiles)
                                            finish()
                                        }
                                    }
                                }
                            }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.End
                            ) {
                                TextButton(onClick = { finish() }) {
                                    Text("Cancel", style = MaterialTheme.typography.labelMedium, color = palette.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private fun extractUris(intent: Intent?): List<Uri> {
        if (intent == null) return emptyList()
        val result = LinkedHashSet<Uri>()

        when (intent.action) {
            Intent.ACTION_SEND -> {
                val streamUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                }
                if (streamUri != null) result.add(streamUri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val streamUris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (streamUris != null) result.addAll(streamUris)
            }
        }

        val clipData = intent.clipData
        if (clipData != null) {
            for (i in 0 until clipData.itemCount) {
                clipData.getItemAt(i).uri?.let { result.add(it) }
            }
        }

        return result.toList()
    }
}

@Composable
private fun SharePeerRow(
    peer: PeerItem,
    enabled: Boolean,
    onSelect: () -> Unit
) {
    val palette = SnowdropThemeTokens.palette
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled && peer.online, onClick = onSelect),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = palette.surface),
        border = BorderStroke(1.dp, palette.hairline)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = peerOsIcon(peer.os),
                contentDescription = null,
                tint = palette.accent,
                modifier = Modifier.size(18.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = peer.displayName,
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                    color = palette.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = peer.primaryIP.orEmpty().ifEmpty { "Online" },
                    style = MaterialTheme.typography.bodySmall.tabular(),
                    color = palette.textSecondary
                )
            }
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(palette.positive)
            )
        }
    }
}
