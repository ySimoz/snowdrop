<p align="center">
  <img src="artwork/snowdrop_horizontal_bloom_v2.svg" alt="Snowdrop" width="560">
</p>

<p align="center">
  <strong>Fast, secure peer-to-peer file transfer across macOS and Android over Tailscale mesh networks.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platforms-macOS%20%7C%20Android-blue?style=flat-square" alt="Platforms">
  <img src="https://img.shields.io/badge/Core-Go%201.22+-00ADD8?style=flat-square&logo=go" alt="Go">
  <img src="https://img.shields.io/badge/Network-Tailscale%20tsnet-4969ED?style=flat-square" alt="Tailscale">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
</p>

---

## Overview

Snowdrop is a minimalist, zero-configuration file transfer utility designed to work seamlessly on isolated campus, corporate, and home Wi-Fi networks where traditional AirDrop, LocalSend, or mDNS tools fail.

By embedding Tailscale's userspace networking engine directly into the application binary, Snowdrop creates a secure, encrypted peer-to-peer WireGuard mesh without requiring root privileges, system VPN adapters, or open ports on the local network.

## Architecture

```
                      +-----------------------------------+
                      |   Tailscale Mesh Plane (tsnet)    |
                      |   - Userspace WireGuard (no TUN)  |
                      |   - Automatic NAT hole-punching   |
                      |   - DERP relay fallback           |
                      +-----------------+-----------------+
                                        |
                   +--------------------+--------------------+
                   |                                         |
+------------------v------------------+   +------------------v------------------+
|           macOS Client              |   |          Android Client             |
|                                     |   |                                     |
|  • SwiftUI Menu Bar App             |   |  • Jetpack Compose Material 3 UI    |
|  • Native Share Extension           |   |  • System Share Sheet Target        |
|  • C-Archive Bridge (libsnowdrop)   |   |  • JNI Bindings (core.aar)          |
|  • Real-time Transfer Cards         |   |  • Foreground Transfer Service      |
+-------------------------------------+   +-------------------------------------+
```

### How It Works

1. **Userspace Networking**: Powered by `tailscale.com/tsnet`, the network stack runs entirely inside application memory. It requires no `/dev/net/tun` access and no root/administrator privileges.
2. **NAT Traversal & Enterprise Resilience**: Automatically establishes direct UDP connections across firewalls. On networks with client isolation (e.g. university eduroam or enterprise guest Wi-Fi), connections transparently fall back to encrypted DERP relays.
3. **Core Engine**: Written in Go and compiled directly to a C-archive for macOS (`libsnowdrop.a`) and an AAR via Gomobile for Android (`core.aar`).
4. **Direct Streaming Protocol**: Files stream over chunked HTTP with pre-flight disk space checks, SHA-256 integrity verification, and dual progress reporting.

---

## Core Features

- **Multi-File Batch Transfers**: Send single files or batches with aggregate and per-file progress tracking.
- **Auto-Accept Trust Store**: Mark familiar devices as trusted to bypass confirmation dialogs for subsequent transfers.
- **Two-Step File Staging**: Stage files in the UI or via OS share sheets, select a peer, and confirm transmission.
- **Tailscale WhoIs Identity Verification**: Receiver nodes cryptographically verify the sender's identity through the Tailscale node map before processing incoming requests.
- **Transfer History**: Monitor recent incoming and outgoing transfers with clearable session logs.
- **Zero-Cloud Storage**: Files travel directly peer-to-peer with end-to-end WireGuard encryption; no files are ever uploaded to intermediate servers.

---

## Security Hardening

- **Path Traversal Defenses**: Inbound file paths are sanitized, stripped of directory traversals (`..`), null bytes (`\x00`), and control characters.
- **Permission Clamping**: Received files are written with restricted permissions (`0600`) to prevent local snooping.
- **Timing-Attack Resistance**: Authentication tokens are validated using constant-time comparison (`crypto/subtle`).
- **DoS Safeguards**: Manifest endpoints enforce request body size limits (`http.MaxBytesReader`) and bounded file conflict iteration loops.

---

## Building from Source

### Prerequisites

- **Go**: 1.22 or higher with `gomobile` installed
- **macOS**: macOS 13 (Ventura) or newer, Xcode Command Line Tools
- **Android**: Android Studio / SDK (API 34) & NDK (r25c or r26)

### 1. Build macOS Menu Bar App

```bash
# Builds Go core C-archive and compiles Snowdrop.app
./macos/build.sh
```

The resulting `Snowdrop.app` will be located in `macos/dist/Snowdrop.app`.

### 2. Build Android App

```bash
# Builds Go core.aar and compiles the debug APK
./android/build.sh
```

The compiled APK will be at `android/app/build/outputs/apk/debug/app-debug.apk`.

### 3. Run Core Tests

```bash
go test -v ./core
```

---

## Configuration

On first launch, Snowdrop generates a Tailscale authentication URL in the UI. Log in with your Tailscale identity once; all devices signed into the same tailnet will discover each other automatically.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
