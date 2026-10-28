Technical Specification & Agent Implementation Plan: MeshDrop

Target System: Minimalist, peer-to-peer file transfer system across macOS and Android
Core Networking: Embedded Tailscale Userspace Stack (tailscale.com/tsnet)
macOS Target: Native Swift / SwiftUI Menu Bar Application (MenuBarExtra / NSStatusItem)
Android Target: Native Kotlin / Jetpack Compose with gomobile bindings

0. Inviolable Agent Directives

All autonomous agents contributing to this repository must strictly adhere to these two foundational rules. Any pull request or automated task that violates either directive must be rejected.

Directive 1: Dual-Platform Core Parity Guarantee

⚬ Synchronous Implementation: Any feature, protocol enhancement, state update, or file-handling capability added to the Go core engine (core/) must be simultaneously exposed through both bridges (bridge_darwin.go and bridge_android.go) and implemented natively in both consumer platforms (macOS Swift and Android Kotlin).

⚬ No Platform Abandonment: An agent must never consider a task complete if a capability exists in the macOS client but is missing, mocked, or stubbed in the Android client, or vice versa. Both clients must remain functional parity targets at all times.

⚬ Uniform Error and Progress Contracts: Transfer IDs, cancellation signals, SHA-256 verification routines, and progress callbacks must behave identically across both operating systems.

Directive 2: Inviolability of the Tailscale / tsnet Core Stack

⚬ Zero Extraneous Discovery Mechanisms: Agents are strictly forbidden from introducing secondary local discovery layers (such as mDNS, Bonjour, SSDP, or raw UDP LAN broadcasts). Tailscale's userspace coordination plane is the sole discovery authority. Bypassing or supplementing it breaks isolation resistance on enterprise and university networks.

⚬ No Transport Tampering: Agents must not inject custom encryption layers, tunnel wrappers, or transport proxies on top of or beneath the tsnet connection. WireGuard handles end-to-end encryption, MTU sizing, and framing natively.

⚬ Preserve Userspace Isolation: Agents must never attempt to introduce system-level TUN/TAP devices (/dev/net/tun), request root/administrator escalation, or alter host OS routing tables. The userspace integrity of tsnet must remain completely intact.

⚬ Preserve DERP Fallback: No code may assume direct UDP hole-punching will always succeed. The HTTP streaming layer must remain protocol-agnostic so DERP relay fallback operates transparently when symmetric NAT prevents direct P2P connections.

1. Project Overview & Guarantees

1.1 Problem Statement

Standard local peer-to-peer discovery protocols (mDNS, Bonjour, LocalSend UDP broadcast) fail on enterprise and university campus Wi-Fi networks due to Client Isolation and strict symmetric NAT.

1.2 The Solution

MeshDrop creates an isolated, zero-config peer-to-peer overlay using Tailscale's tsnet library embedded directly into the application binary:

⚬ No system-wide VPN required: Runs entirely in userspace memory via an isolated TCP/IP stack.

⚬ Zero OS-level administrative privileges: Does not touch /dev/net/tun or require root/admin privileges.

⚬ NAT traversal & DERP relay: Seamless direct WireGuard hole-punching; transparently falls back to Tailscale DERP relays if symmetric NAT blocks direct UDP.

⚬ Zero bloat: No messaging, no user tracking, no cloud storage. Purely discovery, authentication, and high-throughput streaming file transfers.

2. System Architecture

                  +-----------------------------------+
                  | Tailscale Coordination / Auth API |
                  +-----------------+-----------------+
                                    | Control Plane (Keys/Peers)
           +------------------------+------------------------+
           |                                                 |
+----------v-----------+                         +-----------v----------+
|  macOS Menu Bar App  |                         | Android Native App   |
|  (Swift / SwiftUI)   |                         | (Kotlin / Compose)   |
|         |            |                         |         |            |
|    C-Archive         |                         |      AAR Bind        |
|  (libmeshdrop.a)     |                         |  (meshdrop.aar)      |
+---------+------------+                         +---------+------------+
|  Shared Go Engine    | <=== Encrypted WireGuard ====> |  Shared Go Engine    |
|   (`tsnet` node)     |      (Direct P2P or DERP)       |   (`tsnet` node)     |
+----------------------+                                 +----------------------+


2.1 Component Matrix

Component	Technology	Role
Shared Core Engine	Go 1.22+, tsnet	Tailscale auth, peer discovery, HTTP/2 streaming engine
macOS Native	Swift 5.10+, SwiftUI, AppKit	Menu bar lifecycle, drag-and-drop target, notifications
macOS Bridge	C-Archive (-buildmode=c-archive)	C header bridging between Swift and Go engine
Android Native	Kotlin, Jetpack Compose, Coroutines	Native UI, Scoped Storage (MediaStore/SAF), Share Target
Android Bridge	gomobile bind (.aar)	JNI/Java wrapper over Go engine

3. Core Engine Specification (core/)

The shared engine must be implemented in pure Go and compile cleanly for darwin/arm64, darwin/amd64, and android/arm64.

3.1 tsnet Lifecycle & Auth

⚬ Instance Isolation: Each app instance initializes a dedicated tsnet.Server:

	⚬ Hostname: Device name formatted as meshdrop-<sanitized-hostname>.

	⚬ Dir: App-specific secure data directory (~/Library/Application Support/MeshDrop on macOS, internal context filesDir on Android).

	⚬ Ephemeral: false (persists device state to prevent re-authenticating on every launch).

⚬ Authentication Hook:

	⚬ tsnet.Server.AuthURL listener: When a user needs to log in, the engine emits the Tailscale auth URL via a callback to the native UI.

	⚬ The native UI opens this URL in the default system browser or custom tab.

	⚬ Upon successful auth, tsnet receives machine authorization, and the engine state shifts to Connected.

3.2 Wire Transfer Protocol

All transfers operate over a lightweight streaming HTTP service bound exclusively to the private tsnet userspace listener (tsnet.Listen("tcp", ":52445")):

Endpoints:

1. GET /v1/info

	⚬ Returns node ID, device name, operating system, and protocol version.

2. POST /v1/transfer/request

	⚬ Headers: X-Transfer-ID, X-File-Name, X-File-Size, X-File-SHA256, X-Sender-Name.

	⚬ Body: Empty or small JSON metadata payload.

	⚬ Response: 200 OK (Accepted), 403 Forbidden (Declined), or 409 Conflict (Busy).

3. POST /v1/transfer/stream

	⚬ Headers: X-Transfer-ID.

	⚬ Body: Raw binary octet stream.

	⚬ Mechanism: Streamed via io.CopyBuffer with a $64\text{ KB}$ buffer. Calculates progress byte-by-byte and updates a progress callback.

[go]
package core

type EngineConfig struct {
    DataDir            string
    DownloadDir        string
    DeviceName         string
    OnStatusChange     func(status int, message string)
    OnAuthRequired     func(authURL string)
    OnPeersUpdated     func(peersJSON string)
    OnIncomingRequest  func(transferID string, senderName string, fileName string, sizeBytes int64) bool
    OnProgress         func(transferID string, bytesTransferred int64, totalBytes int64)
    OnTransferComplete func(transferID string, success bool, errorMsg string)
}


4. macOS Menu Bar Application (macos/)

4.1 UI Design Guidelines

⚬ Lifecycle: Exclusively lives in the macOS status bar using NSStatusItem or SwiftUI MenuBarExtra(isInserted: ...). Must configure LSUIElement = YES in Info.plist to hide from the Dock and CMD+Tab app switcher.

⚬ Status Indicator:

	⚬ Neutral Icon: Idle / Connected to Tailnet.

	⚬ Animated Icon / Progress Ring: Active incoming/outgoing transfer.

	⚬ Warning Badge: Action needed (Auth required or offline).

4.2 Interaction Architecture

1. Dropdown Popover:

	⚬ Header: Device name, Tailnet connection status dot (Green = Ready, Orange = Authenticating, Gray = Disconnected).

	⚬ Target Peers Section: List of online devices running MeshDrop on the user's Tailnet.

	⚬ Quick Drop Zone: Drag-and-drop zone inside the popover or directly onto the menu bar icon. Dropping a file prompts peer selection.

	⚬ Active Transfer Card: File name, live percentage bar, transfer rate ($\text{MB/s}$), remaining time, and a "Cancel" button.

	⚬ Settings Submenu: Select destination folder (defaults to ~/Downloads), toggle auto-accept from trusted own-devices, and Log Out.

4.3 Native macOS Permissions & Configuration

⚬ Network Permissions: Entitlements must include com.apple.security.network.client and com.apple.security.network.server.

⚬ Sandbox Compliance: If sandboxed, use Security-Scoped Bookmarks to maintain read/write permissions to user-selected download directories.

5. Android Application (android/)

5.1 Architecture & UX

⚬ Design Philosophy: Minimalist, single-screen Jetpack Compose dashboard with system notification overlays for background transfers.

⚬ Screen States:

    1. Unauthenticated State: Prominent "Sign in with Tailscale" button -> launches CustomTabsIntent with the auth URL emitted by the Go engine.

    2. Authenticated State:

		⚬ Top App Bar: Status pill (Tailnet Online/Offline) + Settings icon (Download destination).

		⚬ "Available Devices" Section: Clean cards representing detected Tailnet peers with status indicators.

		⚬ "Recent Transfers" Section: History and active transfers with progress bars.

5.2 System Integration (Crucial)

1. Android Share Sheet Integration:

	⚬ Register an intent-filter for android.intent.action.SEND and SEND_MULTIPLE for */* MIME types.

	⚬ When user taps "Share via MeshDrop" from Google Photos or Files app:

		⚬ Open a lightweight translucent Activity / Bottom Sheet showing available Tailscale peers.

		⚬ Selecting a peer starts transfer immediately in the background.

2. Foreground Service (TransferService):

	⚬ File operations must run inside an Android Foreground Service with type dataSync (android:foregroundServiceType="dataSync").

	⚬ Display a non-dismissible ongoing notification with a real-time progress bar and "Cancel" action.

3. Storage Access Framework & Scoped Storage:

	⚬ Default downloads go to Environment.DIRECTORY_DOWNLOADS/MeshDrop/.

	⚬ Android 10+ (API 29+): Use MediaStore API or ContentResolver to save incoming file streams safely without broad legacy storage permissions.

4. Android Permissions Manifest:

	⚬ android.permission.INTERNET

	⚬ android.permission.ACCESS_NETWORK_STATE

	⚬ android.permission.FOREGROUND_SERVICE

	⚬ android.permission.FOREGROUND_SERVICE_DATA_SYNC

	⚬ android.permission.POST_NOTIFICATIONS (Android 13+)

6. Bridge & Interface Contracts

6.1 macOS C-Bridge Interface (core/bridge_darwin.go)

Agents will compile this using:
go build -buildmode=c-archive -o macos/Frameworks/libmeshdrop.a core/bridge_darwin.go

[c]
// meshdrop.h
#ifndef MESHDROP_H
#define MESHDROP_H

#include <stdint.h>
#include <stdbool.h>

typedef void (*StatusCallback)(int status, const char* message);
typedef void (*AuthRequiredCallback)(const char* authURL);
typedef void (*PeersUpdatedCallback)(const char* peersJSON);
typedef void (*ProgressCallback)(const char* transferID, int64_t current, int64_t total);
typedef void (*TransferCompleteCallback)(const char* transferID, bool success, const char* errorMsg);

int StartEngine(const char* dataDir, const char* downloadDir, const char* deviceName);
void StopEngine();
void SendFile(const char* peerIP, const char* filePath, const char* transferID);
void CancelTransfer(const char* transferID);

#endif


6.2 Android gomobile Interface (core/bridge_android.go)

Agents will generate the .aar using:
gomobile bind -target=android/arm64,android/amd64 -o android/app/libs/core.aar ./core

[go]
package core

type AndroidCallback interface {
    OnStatusChange(status int, message string)
    OnAuthRequired(authURL string)
    OnPeersUpdated(peersJSON string)
    OnProgress(transferId string, current int64, total int64)
    OnTransferComplete(transferId string, success bool, errorMsg string)
}

func StartAndroidEngine(dataDir string, downloadDir string, deviceName string, cb AndroidCallback) error
func StopAndroidEngine()
func SendFileToPeer(peerIP string, fileDescriptor int, fileName string, fileSize int64, transferID string)
func CancelAndroidTransfer(transferID string)


7. Implementation Roadmap for Agents

Agents should execute this build sequentially in four distinct phases:

Phase 1: Shared Core Engine (/core)

⚬ [ ] Initialize Go module github.com/username/meshdrop/core.

⚬ [ ] Implement Engine wrapping tsnet.Server.

⚬ [ ] Implement local HTTP listener on the tsnet interface.

⚬ [ ] Implement peer status polling using tsnet.Server.LocalClient() to track peer online states.

⚬ [ ] Implement streaming file sender and receiver with SHA-256 chunked hashing.

⚬ [ ] Write CLI test harness in core/cmd/testnode to simulate transfers between two local virtual tsnet nodes.

Phase 2: macOS Menu Bar Client (/macos)

⚬ [ ] Create SwiftUI / AppKit Xcode project targeting macOS 13.0+.

⚬ [ ] Set LSUIElement to YES in Info.plist.

⚬ [ ] Integrate libmeshdrop.a and bridging header.

⚬ [ ] Build menu bar status view with peer listing and connection state.

⚬ [ ] Implement drag-and-drop file target and native NSOpenPanel fallback.

⚬ [ ] Connect system notifications via UserNotifications framework on transfer completion.

Phase 3: Android Client (/android)

⚬ [ ] Create modern Android Studio project targeting API 26+ (min) and 34+ (target).

⚬ [ ] Run gomobile bind and import core.aar into the Gradle build dependencies.

⚬ [ ] Implement Jetpack Compose UI (Authentication view, Peer selector, Active transfer card).

⚬ [ ] Implement TransferService (Android Foreground Service) with a progress notification.

⚬ [ ] Implement Share Target activity (android.intent.action.SEND) accepting incoming streams from other apps.

⚬ [ ] Implement target directory resolution via MediaStore/SAF for clean zero-error downloads.

Phase 4: Verification & Edge Cases

⚬ [ ] Campus Isolation Verification: Verify peer-to-peer data flow across distinct isolated client subnets.

⚬ [ ] DERP Relay Verification: Test behavior behind symmetric NAT to ensure graceful fallback without stalling.

⚬ [ ] Large File Transfer: Test uninterrupted transfer of a $4\text{ GB}+$ ISO or video file with progress tracking and hash verification.

⚬ [ ] Interrupted Connection Test: Ensure cancelling on either side immediately closes TCP stream connections and cleans up partial .tmp files.

