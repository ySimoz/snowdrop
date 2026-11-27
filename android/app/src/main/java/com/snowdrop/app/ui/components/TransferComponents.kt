package com.snowdrop.app.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.LaptopMac
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.snowdrop.app.domain.SnowdropFormat
import com.snowdrop.app.domain.TransferItem
import com.snowdrop.app.ui.theme.SnowdropThemeTokens
import com.snowdrop.app.ui.theme.tabular

fun peerOsIcon(os: String): ImageVector = when (os.lowercase()) {
    "darwin", "macos", "ios" -> Icons.Outlined.LaptopMac
    "android" -> Icons.Outlined.PhoneAndroid
    else -> Icons.Outlined.Computer
}

@Composable
fun TransferProgressBlock(
    transfer: TransferItem,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = SnowdropThemeTokens.palette
    val pct = (transfer.progress * 100).toInt()
    val speedLabel = SnowdropFormat.speed(transfer.speedBytesPerSec)
    val etaLabel = SnowdropFormat.eta(transfer.etaSeconds)
    val metrics = buildList {
        add("$pct%")
        add("${SnowdropFormat.bytes(transfer.bytesTransferred)} / ${SnowdropFormat.bytes(transfer.totalBytes)}")
        if (speedLabel.isNotEmpty()) add(speedLabel)
        if (etaLabel.isNotEmpty()) add("$etaLabel left")
    }.joinToString(" · ")

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (transfer.isBatch && transfer.currentFileName.isNotEmpty()) {
            Text(
                text = "File ${transfer.fileIndex} of ${transfer.totalFiles}: ${transfer.currentFileName}",
                style = MaterialTheme.typography.bodySmall.tabular(),
                color = palette.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            LinearProgressIndicator(
                progress = { transfer.progress },
                modifier = Modifier
                    .weight(1f)
                    .height(6.dp)
                    .clip(RoundedCornerShape(3.dp)),
                color = palette.accent,
                trackColor = palette.surfaceElevated
            )
            Spacer(modifier = Modifier.width(8.dp))
            IconButton(
                onClick = onCancel,
                modifier = Modifier.size(28.dp)
            ) {
                Icon(
                    imageVector = Icons.Outlined.Close,
                    contentDescription = "Cancel transfer",
                    tint = palette.textSecondary,
                    modifier = Modifier.size(18.dp)
                )
            }
        }

        Text(
            text = metrics,
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal).tabular(),
            color = palette.textSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
