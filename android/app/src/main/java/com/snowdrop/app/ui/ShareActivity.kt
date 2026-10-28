package com.snowdrop.app.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.snowdrop.app.core.PeerItem
import com.snowdrop.app.core.SnowdropCoreBridge
import com.snowdrop.app.service.TransferService
import com.snowdrop.app.ui.theme.SnowdropTheme

class ShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val uris = extractUrisFromIntent(intent)
        if (uris.isEmpty()) {
            finish()
            return
        }

        setContent {
            SnowdropTheme {
                val peers by SnowdropCoreBridge.peers.collectAsState()

                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = Color.Black.copy(alpha = 0.5f)
                ) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.BottomCenter
                    ) {
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            shape = RoundedCornerShape(16.dp)
                        ) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                    "Share via Snowdrop",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    "${uris.size} file(s) ready to send. Select destination peer:",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Spacer(modifier = Modifier.height(12.dp))

                                if (peers.isEmpty()) {
                                    Text(
                                        "No peers currently online on your Tailnet.",
                                        style = MaterialTheme.typography.bodyMedium,
                                        modifier = Modifier.padding(vertical = 16.dp)
                                    )
                                } else {
                                    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        items(peers) { peer ->
                                            SharePeerRow(peer = peer) {
                                                peer.primaryIP?.let { ip ->
                                                    TransferService.start(this@ShareActivity)
                                                    for (u in uris) {
                                                        SnowdropCoreBridge.sendFile(this@ShareActivity, ip, u)
                                                    }
                                                }
                                                finish()
                                            }
                                        }
                                    }
                                }

                                Spacer(modifier = Modifier.height(8.dp))
                                TextButton(
                                    onClick = { finish() },
                                    modifier = Modifier.align(Alignment.End)
                                ) {
                                    Text("Cancel")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private fun extractUrisFromIntent(intent: Intent?): List<Uri> {
        if (intent == null) return emptyList()
        val list = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                }
                uri?.let { list.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                uris?.let { list.addAll(it) }
            }
        }
        return list
    }
}

@Composable
fun SharePeerRow(peer: PeerItem, onSelect: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = peer.online, onClick = onSelect),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = when (peer.os.lowercase()) {
                    "darwin", "macos", "ios" -> Icons.Default.Laptop
                    "android" -> Icons.Default.Smartphone
                    else -> Icons.Default.Computer
                },
                contentDescription = null,
                tint = if (peer.online) MaterialTheme.colorScheme.primary else Color.Gray,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(peer.displayName, fontWeight = FontWeight.Medium, fontSize = 14.sp)
                peer.primaryIP?.let { ip ->
                    Text(ip, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
