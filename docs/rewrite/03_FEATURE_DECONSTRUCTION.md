# 03 — Feature Deconstruction & macOS 26 Reimagination

Audit of the legacy macOS SwiftUI/AppKit client (`macos/Sources/Snowdrop/`, `macos/ShareExtension/`, `macos/Info.plist`) and functional specification for the greenfield macOS 26 Liquid Glass rewrite.

---

## 1. Legacy UI Surface Inventory

| Surface | Type & Dimensions | Trigger / Lifecycle | Source |
|---|---|---|---|
| **Menu Bar Status Item & Popover** | `NSStatusItem` (18×18 template) + `NSPopover` (`320×460`, `.transient`) | Status bar click (`togglePopover`) or programmatic `showPopover()` | `App.swift` (`StatusItemManager`), `MenuBarView.swift` |
| **Auth Banner** | Inline amber card inside popover `ScrollView` | `engine.status == .needsAuth` | `MenuBarView.swift` (`authBanner`) |
| **Incoming Approval Banner** | Inline card (`frostSlate800` + border) | `engine.pendingApproval != nil`; forces `showPopover()` | `MenuBarView.swift` (`incomingApprovalBanner`) |
| **Fallback Transfer Card** | Standalone card (`TransferCardView`) | `activeTransfer != nil` and `peerName` matches no visible `PeerItem` | `MenuBarView.swift`, `TransferCardView.swift` |
| **Rename Device Sheet** | `.sheet` modal (`260pt` wide) | Header pencil icon or Settings `"Rename"` | `MenuBarView.swift` (`RenameDeviceSheet`) |
| **Settings Popover / Scene** | `270pt` popover OR `320pt` `Settings` scene | Footer gear button OR macOS Settings scene | `MenuBarView.swift`, `App.swift` |
| **System Notifications** | `UNUserNotificationCenter` banners | Incoming approval + transfer complete/failed | `App.swift`, `SnowdropEngine.swift` |
| **Finder Share Extension** | `NSViewController` (`260×80` icon + spinner + label) | macOS Share menu (`com.apple.share-services`) | `ShareExtension/ShareViewController.swift` |

### Legacy Structural Bugs Observed
1. **`Settings` Scene Isolation (`App.swift:10-13`)**: Passes a throwaway `MenuBarViewModel()` with no `.sheet` observer, so clicking `"Rename"` in `Settings` silently does nothing.
2. **Inline `@ObservedObject` Initialization (`MenuBarView.swift:38`)**: `@ObservedObject var vm = MenuBarViewModel()` risks resetting transient UI state on view re-evaluation.
3. **Menu Bar Only (`LSUIElement = true`)**: No main window, no Menu Bar `Commands`, no keyboard shortcuts.

---

## 2. User Journeys, State Transitions & Edge Cases

### 2.1 Launch, Auth & Sign-Out
- **Launch**: `disableAutomaticTermination`, starts Go engine (`DataDir` = `Application Support/Snowdrop`, `DownloadDir` = `~/Downloads`), sets up status item + `servicesProvider`, opens popover if a file was staged on launch.
- **Status Machine**: `0` (`.disconnected`) -> `2` (`.connecting`) -> `1` (`.needsAuth(url)`) -> `3` (`.connected`) / `4` (`.error(msg)`).
- **Auth & Sign-Out**: `"Sign in with Tailscale"` opens `authURL` via `NSWorkspace.shared.open`. `"Sign Out & Unlink"` runs `SnowdropSignOut()`, clears `peers`, sets `.needsAuth(url: "")`.
  * *Edge case*: Clearing `status` to `.needsAuth(url: "")` leaves `"Sign in with Tailscale"` inert until Go emits a new `AuthRequiredCallback`.

### 2.2 Peer Discovery & Device Rename
- **Peer Model**: `PeerItem` (`id`, `hostName`, `customDisplayName`, `dnsName`, `os`, `ipAddresses`, `online`). `osIcon` maps `darwin/macos/ios` -> `apple.logo`, `android/linux` -> `antenna.radiowaves.left.and.right`, `windows` -> `pc`, default -> `desktopcomputer`.
- **Empty States**: `.connected` -> `"No peers found on Tailnet"`; `.needsAuth` -> `"Sign in above to see peers"`; else `"Waiting for connection..."`.
- **Device Rename**: Persists `"SnowdropDeviceName"` in `UserDefaults` and triggers `engine.restart()`.

### 2.3 File Staging & Entry Points
All entry points append deduplicated URLs to `stagedFileURLs`:
- **`NSOpenPanel`**: `StatusItemManager.selectFile()` temporarily sets `popover.behavior = .applicationDefined` so the open panel doesn't dismiss the popover.
- **Drag & Drop**: `dropZoneView.onDrop(of: [UTType.fileURL.identifier])`.
  * *Edge cases*: Drop zone disappears once ≥1 file is staged (cannot drop additional files onto staged card); concurrent `loadObject` appends to local `loadedUrls` without synchronization.
- **URL Scheme (`snowdrop://send?path=...`)**: Checks `fileExists`, `!isDir`, and blocks `/.ssh/`, `/.aws/`, `/.gnupg/`, `/etc/`, `/var/`, and dotfiles.
  * *Edge case*: Direct `file://` opens (`application(_:open:)`, `application(_:openFile:)`) and `handleSendService` bypass directory/sensitive-path checks.
- **Finder Service (`Send with Snowdrop`)**: `handleSendService` reads `[NSURL]` / `.fileURL` pasteboard items (supports multi-file).
- **Finder Share Extension (`ShareViewController.swift`)**:
  * **LEGACY BUG (`line 85`)**: `for provider in attachments` executes an unconditional `break` after the first attachment, silently dropping every file after the first in multi-file shares. Also has a hardcoded 3.0s `finish()` timer and uses `snowdrop://send?path=...` (which fails under App Sandbox).

### 2.4 Sending, Progress, Cancellation & Speed/ETA
- **Single vs. Batch**: 1 file -> `SendFile` (`tx-<uuid>`); >1 files -> `SendBatch` (`batch-<uuid>`) with JSON manifest.
  * *Edge case*: `MenuBarView` calls `clearStagedFiles()` immediately even if `peer.primaryIP == nil` (silent no-op).
- **Progress UI**: Matches `activeTransfer.peerName` against `PeerItem` for inline peer-row progress, else falls back to `TransferCardView`.
  * *Bug*: Incoming `handleProgress` / `handleBatchProgress` hardcodes `peerName: "Tailnet Peer"` and `fileName: "Receiving File..."`, so incoming transfers never match a `PeerItem` and lose sender/filename metadata already sent in `handleIncomingApproval`.
- **Speed & ETA**: Sampled every `0.5s`; ETA (`remainingTimeFormatted`) shown only on `TransferCardView`, omitted on inline peer progress.

### 2.5 Incoming Approvals, Notifications & Trust Circle
- **Approval Banner & Notification**: `handleIncomingApproval` sets single `pendingApproval`, opens popover, and posts `UNNotificationRequest`.
  * *Bug 1*: Single `pendingApproval` slot overwrites earlier requests if multiple peers send concurrently (Go allows up to 3).
  * *Bug 2*: `AppDelegate` handles `ACTION_ACCEPT` (1), `ACTION_TRUST` (2), `ACTION_DECLINE` (3), but `setupNotifications()` calls `setNotificationCategories([])` and never sets `categoryIdentifier`—so notification buttons never render.
- **Trust Circle**: `SettingsPopoverView` loads `GetTrustedPeers()` on `.onAppear` and supports `"Revoke"`.

### 2.6 Transfer History & Settings
- **History**: In-memory `[TransferItem]` capped at 5 items, lost on quit. `"Clear All"`, `"Remove from History"`, and `"Show in Finder"` (only when `isSuccess && direction == .incoming`).
  * *Bug*: `"Show in Finder"` checks `downloadDirectory.appendingPathComponent(recent.fileName)`, which fails for incoming single transfers (`"Receiving File..."`), batches (`"N files"`), and collision-renamed files (`"file (1).ext"`).
- **Settings**: `downloadDirectory` (not persisted across restarts, not synced to Go), `requireApproval` / `autoAccept` (not persisted, not synced on startup), `Restart Network Stack`, `Sign Out & Unlink`, `Quit`.

---

## 3. Greenfield Native macOS 26 + Liquid Glass Reimagination

### 3.1 Strip Legacy Workarounds
- Delete all hardcoded `frostSlate*`, `glassCardBg`, `glassBorder*`, and raw `Color(red:...)` tokens.
- Use system-adaptive semantics (`Color.accentColor`, `.primary`/`.secondary`, `.green`/`.orange`/`.red`), dynamic system fonts with `.monospacedDigit()` for metrics, and native macOS surfaces.

### 3.2 Native macOS 26 Window & Navigation Architecture
1. **Primary `Window` ("Snowdrop") — `NavigationSplitView`**:
   - **Sidebar (`.listStyle(.sidebar)`)**:
     - **Devices** (Online & Offline peers, `.searchable` via `⌘F`)
     - **Transfers** (Active transfers, incoming approval queue, and transfer history)
     - **Trusted Devices** (Trust Circle management & revocation)
   - **Detail Content (Strictly Opaque Layer 1)**:
     - *Devices*: Always-on `.dropDestination(for: URL.self)`, staged file tray with individual removal + `"Add Files…"`, peer list with status, OS icon, and **Send**.
     - *Transfers*: Real sender/receiver names and actual filenames, batch sub-progress (`File X of Y`), speed + ETA, cancel (`⌘.`), and accurate **Show in Finder** (`⌘R`).
     - *Trusted Devices*: Full `TrustedPeerItem` list with auto-accept metadata and **Revoke** action.
2. **`MenuBarExtra` Companion (`MenuBarExtra(.window)`)**:
   - Retains the 18×18 template icon for quick drop-on-icon, status glance, quick send, **"Open Snowdrop Window"** (`⌘0`), and **"Quit"** (`⌘Q`).
3. **Native `Settings` Scene (`⌘,`)**:
   - `TabView` + grouped `Form` tabs: **General** (Device Name, Menu Bar preference, Download Folder via security-scoped bookmark + Reset), **Security & Approvals** (persisted `requireApproval` / `autoAccept`, Trusted Devices), **Account & Network** (Sign In / Sign Out, Restart Network Stack).
4. **Native Menu Bar `Commands`**:
   - `Choose Files…` (`⌘O`), `Clear Staged Files` (`⇧⌘⌫`), `Find Peer…` (`⌘F`), `Devices`/`Transfers`/`Trusted` (`⌘1`/`⌘2`/`⌘3`), `Cancel Transfer` (`⌘.`), `Show in Finder` (`⌘R`), `Settings…` (`⌘,`), `Quit` (`⌘Q`).
5. **Strict Two-Layer Liquid Glass Enforcement**:
   - **Layer 1 (Content — Opaque)**: Sidebars, lists, transfer rows, staged file lists, and Settings forms remain crisp, opaque, high-contrast surfaces. Never apply `.glassEffect()` to scrollable rows or content cards.
   - **Layer 2 (Floating Chrome — `.glassEffect`)**: Reserve `.glassEffect(_:in:)` (always **after** `.padding()` and `.frame()`) exclusively for floating toolbars, the floating staged-files action bar (`GlassEffectContainer`), transient incoming-approval HUDs, and `MenuBarExtra` floating control clusters. Zero glass-on-glass stacking.
