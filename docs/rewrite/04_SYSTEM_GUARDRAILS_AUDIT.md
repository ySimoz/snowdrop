# 04 — System Guardrails Audit

Audit of OS interactions, App Sandbox, entitlements, `Info.plist`, TCC permissions, private APIs, lifecycle hygiene, and Swift 6 strict concurrency compliance.

---

## 1. App Sandbox & Entitlements Gap Analysis

### Legacy Deficiencies
1. **App Sandbox disabled**: `macos/MeshDrop.entitlements` sets `com.apple.security.app-sandbox = false`, and `macos/build.sh` signs `Snowdrop.app` without passing `--entitlements` at all.
2. **Share Extension breaks under Sandbox**: `SnowdropShare.appex` passes a raw path string over `snowdrop://send?path=...` (`ShareViewController.swift`), which gives a sandboxed `Snowdrop.app` zero security-scoped file access (`EPERM` when Go opens the file). Additionally, `ShareViewController` breaks after the first attachment (`line 85`) and uses `.urlQueryAllowed` (which fails to escape `&`, `+`, `#`).
3. **Unpersisted Download Folder**: `selectDownloadFolder()` stores `downloadDirectory` in memory only (`SnowdropEngine.swift:337-348`). Under App Sandbox, custom folders lose write access across restarts without a security-scoped bookmark.

### Required Greenfield Entitlements

#### `Snowdrop.app`
- `com.apple.security.app-sandbox = true`
- `com.apple.security.network.client = true` (Tailscale control/DERP/WireGuard + outbound HTTP)
- `com.apple.security.network.server = true` (`tsnet.Listen(":52445")` + WireGuard UDP)
- `com.apple.security.files.user-selected.read-write = true` (`NSOpenPanel`, drag-and-drop, custom destination folders)
- `com.apple.security.files.downloads.read-write = true` (default `~/Downloads` destination)
- `com.apple.security.files.bookmarks.app-scope = true` (persist custom download folder across launches)
- `com.apple.security.application-groups = ["$(TeamIdentifierPrefix)com.snowdrop.mac.shared"]` (sandboxed Share Extension handoff)

#### `SnowdropShare.appex`
- `com.apple.security.app-sandbox = true`
- `com.apple.security.files.user-selected.read-only = true`
- `com.apple.security.application-groups = ["$(TeamIdentifierPrefix)com.snowdrop.mac.shared"]`

**Signing rule**: Sign `SnowdropShare.appex` first with its entitlements, then `Snowdrop.app` with its entitlements and Hardened Runtime (`--options runtime`); never use `--deep`. (Note: App Groups require a development team / provisioning profile for full entitlement enforcement; document ad-hoc local dev fallback if unsigned.)

---

## 2. Private API & Prohibited Pattern Removal

1. **`App.swift:178, 212-253` (`warmIconServicesCache()`)**: Uses `dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices", RTLD_NOW)`, `dlsym("kISImageDescriptorHomeScreen")`, and private classes `ISBundleIdentifierIcon` / `ISImageDescriptor` with raw `unsafeBitCast` IMP calls (never calls `dlclose`).
2. **`macos/build.sh:65-128`**: Repeats the same private `IconServices.framework` `swift -e` script and runs `killall ShareSheetUI usernoted`.
3. **Greenfield Fix**: Delete both completely. Use a standard `Assets.xcassets` AppIcon catalog compiled with the Xcode target so LaunchServices and Share Sheet index icons natively.

---

## 3. TCC, Notifications & Permissions

1. **Missing Notification Categories (`SnowdropEngine.swift:606-609`)**: `setupNotifications()` calls `setNotificationCategories([])` and `handleIncomingApproval` sets no `categoryIdentifier`, making `AppDelegate`'s `ACTION_ACCEPT`, `ACTION_TRUST`, and `ACTION_DECLINE` handlers unreachable. Also `requestAuthorization` is called twice (`SnowdropEngine.init` and `AppDelegate.applicationDidFinishLaunching`).
   * **Fix**: Register `UNNotificationCategory` `"INCOMING_TRANSFER_APPROVAL"` once on startup and attach it to approval notifications.
2. **Missing Local Network Usage Description**: `macos/Info.plist` lacks `NSLocalNetworkUsageDescription`, which macOS 15+ requires when `tsnet`/`magicsock` probes local RFC1918 subnets for direct P2P hole-punching.
   * **Fix**: Add `NSLocalNetworkUsageDescription` to `Info.plist`.
3. **Share Extension Activation Rule**: Replace `TRUEPREDICATE` in `ShareExtension/Info.plist` with explicit file/attachment predicates (`NSExtensionActivationSupportsFileWithMaxCount` / `NSExtensionActivationSupportsAttachmentsWithMaxCount`).

---

## 4. Lifecycle, Storage & Process Hygiene

1. **Termination Race (`App.swift:322-324`, `SnowdropEngine.swift:201-220`)**: `applicationWillTerminate` calls `stop()`, which dispatches `StopEngine()` asynchronously, while Go's `Stop()` waits on `e.wg.Wait()` in a detached goroutine. The app exits before `tsServer.Close()` finishes. `restart()` also uses a blind `0.3s` delay.
   * **Fix**: Use `applicationShouldTerminate(_:)` returning `.terminateLater` + `NSApp.reply(toApplicationShouldTerminate: true)` once `await engine.stop()` completes, and serialize `start`/`stop`/`restart` in an actor.
2. **Sandbox Container Storage Shift**: Under `app-sandbox = true`, `.applicationSupportDirectory` moves from `~/Library/Application Support/Snowdrop` to `~/Library/Containers/com.snowdrop.mac/Data/Library/Application Support/Snowdrop` (`tailscaled.state` and `trusted_peers.json`).
3. **Global `TMPDIR` Env Mutation (`core/engine.go:81-85`)**: `core.Engine.Start()` overwrites process-wide `TS_LOGS_DIR`, `TMPDIR`, and fallback `HOME` with `DataDir`, overriding the sandbox container's `NSTemporaryDirectory()`. Remove/avoid mutating `TMPDIR` and `HOME` in the Darwin host process.
4. **URL Scheme & Sensitive-Path Validation (`App.swift:267-320`)**: Legacy `snowdrop://send?path=...` skips `.resolvingSymlinksInPath()`, misses `/private/etc/`, `/private/var/`, `~/Library/Keychains/`, and `~/Library/Application Support/Snowdrop/`, while `file://` opens and `handleSendService` perform no validation at all.
   * **Fix**: Replace `snowdrop://send?path=` with App Group manifest handoff (`snowdrop://handoff?id=<uuid>`), and run centralized symlink-resolved path + regular-file validation before staging any URL.

---

## 5. Swift 6 Strict Concurrency & Memory Safety Audit

1. **Unisolated `ObservableObject` & Global Singletons**: Legacy `SnowdropEngine` and `StatusItemManager` are unisolated classes with `static let shared` accessed across threads; `MenuBarView` uses `@ObservedObject var vm = MenuBarViewModel()`.
   * **Greenfield Requirement**: Isolate all UI state and `@Observable` stores to `@MainActor`; isolate backend FFI calls and state transitions inside a dedicated Swift `actor`.
2. **`onDrop` Data Race (`MenuBarView.swift:351-367`)**: Mutates local `var loadedUrls` concurrently from `NSItemProvider.loadObject` closures. Use Swift `withTaskGroup` / `.dropDestination(for: URL.self)`.
3. **C-FFI Callback Trampolines & Flooding**: C `@convention(c)` callbacks run on arbitrary Go goroutines and fire on every 64 KB chunk. Copy C strings synchronously in `nonisolated` free-function trampolines, coalesce/throttle progress updates (`>= 50ms` or completion), and hop to `@MainActor` / backend `actor` via `Sendable` payloads.
4. **Go Concurrency Races**: Fix `e.lastPeers` race (`engine.go:311, 517`) and `EngineConfig.RequireApproval`/`AutoAcceptTrusted` race (`engine.go:408` vs `transfer.go:188, 326`) in Phase 2.
