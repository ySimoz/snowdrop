# 05 — Greenfield Architecture (`macos-next/`)

Architecture specification for the macOS 26+ native SwiftUI & Liquid Glass rewrite of Snowdrop.

---

## 1. Module Boundaries (`macos-next/`)

```text
macos-next/
├── Package.swift                 # swift-tools-version: 6.2, .macOS(.v26), Swift 6 mode
├── project.yml                   # XcodeGen spec (Snowdrop.app + SnowdropShare.appex)
├── scripts/
│   └── build_core.sh             # Builds core/bridge_darwin.go -> Frameworks/libsnowdrop.a
├── Config/
│   ├── Info.plist                # Snowdrop.app Info.plist (NSLocalNetworkUsageDescription, snowdrop://, NSServices)
│   ├── ShareExtension-Info.plist # Explicit NSExtensionActivationRule predicates
│   ├── Snowdrop.entitlements     # App Sandbox, network client/server, downloads/user-selected rw, app-scope bookmarks
│   ├── Snowdrop.AppGroups.entitlements # Documented App Group extension entitlements when Team ID is configured
│   └── SnowdropShare.entitlements# Sandboxed read-only user-selected files
├── Frameworks/
│   └── libsnowdrop.a             # Generated C-archive (gitignored)
├── Sources/
│   ├── CSnowdrop/                # System C module wrapping snowdrop.h -> libsnowdrop.a
│   ├── SnowdropCore/             # Pure Swift 6 domain models, SnowdropBackend protocol, @MainActor @Observable SnowdropStore, MockSnowdropBackend
│   ├── SnowdropBridge/           # LiveSnowdropBackend actor + OSAllocatedUnfairLock C-callback trampolines + AsyncStream<BackendEvent>
│   └── SnowdropApp/              # Native SwiftUI macOS 26+ scenes, AppDelegate, Liquid Glass Two-Layer chrome
├── ShareExtension/
│   └── ShareViewController.swift # Sandboxed Share Extension (stub in F-00, multi-file App Group handoff in F-09)
└── Tests/
    ├── SnowdropCoreTests/        # Fast unit tests against MockSnowdropBackend (zero C/Go link)
    └── SnowdropBridgeTests/      # Real C-archive integration & non-blocking MainActor tests
```

### Dependency Graph
- `SnowdropApp` → `SnowdropBridge`, `SnowdropCore`
- `SnowdropBridge` → `SnowdropCore`, `CSnowdrop` (links `libsnowdrop.a`)
- `SnowdropCore` → Foundation / Observation only (zero C or AppKit dependency, enabling fast deterministic unit tests)
- `SnowdropCoreTests` → `SnowdropCore`
- `SnowdropBridgeTests` → `SnowdropBridge`, `SnowdropCore`

---

## 2. State & Concurrency Architecture

1. **Swift 6 Strict Concurrency**: `swiftLanguageModes: [.v6]` in `Package.swift` and `SWIFT_STRICT_CONCURRENCY = complete` in `project.yml`. Zero `@unchecked Sendable` hacks on mutable state.
2. **Unidirectional Data Flow**:
   - `SnowdropStore` (`@MainActor @Observable`) owns all UI state (`status`, `peers`, `activeTransfers: [String: TransferItem]`, `recentTransfers`, `pendingApprovals`, `trustedPeers`, `stagedFileURLs`, `selectedSection`, settings state).
   - `SnowdropStore` consumes `backend.events` (`AsyncStream<BackendEvent>`) inside a single structured `Task` and cancels it cleanly during `shutdown()`.
3. **Actor-Isolated FFI (`LiveSnowdropBackend: SnowdropBackend`)**:
   - All C-FFI calls (`StartEngine`, `StopEngine`, `SendFile`, `SendBatch`, `CancelTransfer`, `ResolveTransferApproval`, `GetTrustedPeers`, `RevokeTrusted`, `SetApprovalConfig`, `SetDownloadDir`, `SnowdropSignOut`, `FreeCString`) execute off `@MainActor` inside `LiveSnowdropBackend`.
   - `start`, `stop`, and `restart` transitions are serialized inside the actor; `StopEngine` calls `eng.StopAndWait(3 * time.Second)` so `tsnet.Server` closes cleanly before relaunch or app termination.
4. **C-Callback Trampoline & Throttling (`CallbackBridge`)**:
   - `nonisolated` `@convention(c)` free-function trampolines copy `const char*` inputs synchronously via `String(cString:)` before Go's `defer C.free` runs.
   - `CallbackBridge` holds the active `AsyncStream<BackendEvent>.Continuation` and per-transfer progress timestamps under `OSAllocatedUnfairLock`, throttling `progress` and `batchProgress` updates to at most once per `50ms` per transfer ID (always forwarding initial and terminal events).
5. **Clean App Termination**:
   - `AppDelegate.applicationShouldTerminate(_:)` returns `.terminateLater`, runs `Task { @MainActor in await store.shutdown(); NSApp.reply(toApplicationShouldTerminate: true) }`.

---

## 3. Liquid Glass & Unslop Design Direction

- **Product**: Direct peer-to-peer macOS file drop over a private WireGuard mesh (`tsnet`).
- **Character**: Calm, exact, quiet craft.
- **World**: Native macOS instrument / utility surface — neutral window canvas, crisp typography, single accent.
- **Moments**: Live transfer progress & incoming peer approval controls.
- **Signature**: Tabular-digit live status & transfer telemetry (`monospacedDigit()`).

### Strict Two-Layer Rule
1. **Layer 1 — Content Layer (Strictly Opaque)**: `NavigationSplitView` sidebar lists, peer rows, transfer history rows, staged file lists, and grouped `Form` settings sit on standard opaque/system-adaptive macOS backgrounds. Never wrap scrollable content rows in `.glassEffect()`.
2. **Layer 2 — Floating Chrome (`.glassEffect` inside `GlassEffectContainer`)**: Reserve `.glassEffect(_:in:)` solely for floating toolbars, transient HUD overlays, and floating action clusters, grouped inside `GlassEffectContainer(spacing:)`.
3. **Modifier Order**: Always apply `.glassEffect(_:in:)` **after** layout, `.padding()`, and `.frame()` modifiers.
4. **Unslop Discipline**: 4px spacing scale, weights 400–600, sentence case everywhere (no `UPPERCASE` tracked headers), system semantic colors (`Color.accentColor`, `.primary`, `.secondary`, `.green`, `.orange`, `.red`), single SF Symbols icon weight/style, zero emojis, zero neon borders or colored glows.

---

## 4. Sandbox, Entitlements & Signing Strategy

- **App Sandbox & Hardened Runtime**: Enabled (`ENABLE_APP_SANDBOX: YES`, `ENABLE_HARDENED_RUNTIME: YES`) on `Snowdrop` and `SnowdropShare`.
- **Network**: `com.apple.security.network.client` + `com.apple.security.network.server` + `NSLocalNetworkUsageDescription` for `tsnet` WireGuard/DERP/HTTP (`:52445`).
- **File Access**: `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.downloads.read-write`, and `com.apple.security.files.bookmarks.app-scope` for persistent custom download directories.
- **Go `TMPDIR` Protection**: `core/engine.go` skips `os.Setenv("TMPDIR", ...)` and `os.Setenv("HOME", ...)` on `darwin` so the app sandbox container's `NSTemporaryDirectory()` remains intact.
- **App Groups (`Snowdrop.AppGroups.entitlements`)**: Sandboxed Share Extension handoff (`$(TeamIdentifierPrefix)com.snowdrop.mac.shared`) is isolated into `Config/Snowdrop.AppGroups.entitlements` for signed Team ID builds; unsigned/ad-hoc local builds omit App Groups so AMFI does not kill the process on launch (full Share Extension handoff implemented in `F-09`).
- **No Private APIs**: Zero `dlopen` calls to `IconServices.framework`.
