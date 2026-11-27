<p align="center">
  <img src="artwork/snowdrop_horizontal_seamless.svg" alt="Snowdrop" width="560">
</p>

<p align="center">
  <strong>Drop files between your Mac and Android phone in seconds — anywhere, even on restricted university or corporate Wi-Fi.</strong>
</p>

<p align="center">
  <a href="https://github.com/ySimoz/snowdrop/releases/latest">
    <img src="https://img.shields.io/github/v/release/ySimoz/snowdrop?color=38BDF8&style=flat-square" alt="Latest Release">
  </a>
  <img src="https://img.shields.io/badge/Platforms-macOS%20%7C%20Android-0284C7?style=flat-square" alt="Platforms">
  <img src="https://img.shields.io/badge/Privacy-Zero%20Cloud%20Relays-10B981?style=flat-square" alt="Privacy">
  <img src="https://img.shields.io/badge/Encryption-WireGuard%20P2P-6366F1?style=flat-square" alt="Encryption">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-slate?style=flat-square" alt="License">
  </a>
</p>

---

## Why Snowdrop?

- **AirDrop leaves Android behind.** If you use a Mac and an Android phone, Apple's ecosystem locks you out.
- **Local network sharing tools fail on public networks.** Tools like LocalSend, Quick Share, or AirDrop rely on local network broadcasts (mDNS/Bonjour). On university campuses (eduroam), offices, hotels, and airports, network firewalls isolate devices from seeing each other.
- **Messaging apps and cloud drives degrade your files.** Sending photos and videos over WhatsApp or Google Drive compresses them, hits upload quotas, and routes private files through third-party cloud servers.

**Snowdrop fixes this.** It connects your Mac and Android devices through a direct, private WireGuard peer-to-peer mesh. Whether you're across the room or on restricted university Wi-Fi, files stream directly between your devices at full speed — private, uncompressed, and effortless.

---

## What Makes It Great

- ⚡ **Works on Any Wi-Fi**: University eduroam, company guest networks, hotel lobbies, and coffee shops. Snowdrop punches straight through client isolation firewalls.
- 📦 **Multi-File Batch Transfers**: Send single files or batches of photos, videos, and documents with aggregate speed and dual progress bars.
- 🛡️ **Auto-Accept for Trusted Devices**: Add your laptop or phone to your trusted circle. Incoming transfers download silently in the background without nagging popups.
- 🔒 **Zero-Cloud, Absolute Privacy**: Direct device-to-device streaming encrypted with WireGuard. No intermediate cloud servers ever see or store your files.
- 🖥️ **Native Everywhere**: 
  - **macOS**: Menu-bar-first SwiftUI app (macOS 26+, Liquid Glass), standalone Settings, optional full window, Finder Share Extension, and Services.
  - **Android**: Jetpack Compose Material 3 app (Light & Dark, Two-Layer Liquid Glass chrome via Haze), Android 15 Foreground Service, and multi-file Share Sheet.
- 📋 **Transfer History**: Swipable / clearable session history with direct file reveal (`Show in Finder` on macOS, safe `MediaStore`/`FileProvider` open on Android).

---

## Quick Start

1. **Download**: Grab `Snowdrop-v0.2.0-macos.zip` for Mac and `Snowdrop-v0.2.0-android.apk` for Android from [Releases](https://github.com/ySimoz/snowdrop/releases/latest).
2. **One-Time Sign In**: Open Snowdrop on both devices. On first launch, tap **Sign In** to link them with your account (Google, Apple, or GitHub). No separate VPN app or setup needed; credentials persist automatically across launches.
3. **Send**: Pick your files, choose your target device, and tap **Send**.

---

## Architecture & Technical Deep-Dive

For developers and security engineers interested in how Snowdrop achieves zero-configuration connectivity without administrative permissions:

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
|            macOS Client             |   |           Android Client            |
|                                     |   |                                     |
|  • SwiftUI 6 + Liquid Glass         |   |  • Jetpack Compose + Haze Glass     |
|  • App Sandbox + Hardened Runtime   |   |  • Android 15 FGS & Share Target    |
|  • Actor-Isolated Bridge (snowdrop) |   |  • 16 KB Aligned JNI Lib (core.aar) |
|  • Multi-File Share Extension       |   |  • Scoped MediaStore / SAF Storage  |
+-------------------------------------+   +-------------------------------------+
```

### 1. Userspace Networking (`tsnet`)
Traditional VPN clients require root privileges to install virtual network adapters (`/dev/net/tun`) and rewrite system routing tables. Snowdrop embeds Tailscale's `tsnet` library directly into the Go engine binary. The entire TCP/IP and WireGuard stack runs inside application process memory with **zero OS-level administrative permissions**.

### 2. NAT Traversal & Relay Fallback
- **Direct UDP Hole-Punching**: Snowdrop discovers peers on the user's tailnet and negotiates direct peer-to-peer UDP WireGuard connections across NAT boundaries.
- **Transparent DERP Fallback**: If symmetric NAT or restrictive institutional firewalls block direct UDP hole-punching, connections transparently fall back to encrypted Tailscale DERP relays without interruption.

### 3. Streaming Protocol
Transfers utilize chunked HTTP streaming over the userspace WireGuard mesh with pre-flight disk allocation verification, SHA-256 chunk validation, and token authentication.

---

## Security Hardening

- **Tailscale WhoIs Identity Verification**: Receiver nodes cryptographically verify the sender's identity through the Tailscale node map before opening transfer streams, preventing device spoofing (CWE-290).
- **Path Traversal Protection**: All inbound filenames are strictly sanitized, stripping directory traversal tokens (`..`), null bytes (`\x00`), and control characters (CWE-22). Fuzz-tested with 100,000+ test iterations.
- **Safe File Permissions**: Incoming files are created with restricted permissions (`0600`) to prevent local unauthorized access.
- **Timing-Attack Resistance**: Authentication tokens are evaluated using `crypto/subtle.ConstantTimeCompare` (CWE-208).
- **DoS Safeguards**: Manifest endpoints enforce request body size limits (`http.MaxBytesReader`), expired session pruning, and bounded file conflict loops.
- **Platform Sandboxing**: macOS enforces App Sandbox, Hardened Runtime, and symlink-resolved sensitive-path checks (`FilePathValidator`); Android enforces `allowBackup="false"`, `FileProvider` URIs, atomic `MediaStore` `IS_PENDING` writes, and 16 KB ELF page alignment.

---

## Building from Source

### Prerequisites

- **Go**: 1.27+ with `gomobile` / `gobind`
- **macOS**: macOS 26+ with Xcode and `xcodegen`
- **Android**: JDK 17, Android SDK (API 35), and NDK r27 (`27.3.13750724`)

### macOS App

```bash
./macos/scripts/build_core.sh
./macos/scripts/install_local.sh
# Installs signed Snowdrop.app to /Applications/Snowdrop.app
```

### Android App

```bash
./android/scripts/build_core.sh
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./android/gradlew -p android assembleDebug
# Output: android/app/build/outputs/apk/debug/app-debug.apk
```

### Run Tests

```bash
(cd core && go test -race -v .)
swift test --package-path macos
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./android/gradlew -p android testDebugUnitTest
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
