package com.snowdrop.app.ui

import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import com.snowdrop.app.core.PeerItem
import com.snowdrop.app.core.SnowdropCoreBridge
import com.snowdrop.app.service.TransferService
import com.snowdrop.app.ui.theme.SnowdropTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            SnowdropTheme {
                var selectedPeer by remember { mutableStateOf<PeerItem?>(null) }

                val filePickerLauncher = rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.GetContent()
                ) { uri: Uri? ->
                    uri?.let { fileUri ->
                        selectedPeer?.primaryIP?.let { ip ->
                            TransferService.start(this)
                            SnowdropCoreBridge.sendFile(this, ip, fileUri)
                        }
                    }
                }

                SnowdropScreen(
                    onPickFileForPeer = { peer ->
                        selectedPeer = peer
                        filePickerLauncher.launch("*/*")
                    }
                )
            }
        }
    }
}
