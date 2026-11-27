# 01 — Legacy Repository Topology

Audit of `/Users/zSimoz/Projects/snowdrop` documenting the legacy Go + macOS + Android codebase, build/packaging pipelines, dependency inventory, artwork generation, and runtime entry points.

---

## 1. Repository Directory Tree & Module Boundaries

### Top-Level Structure

```text
snowdrop/
├── go.work                        # Go workspace (go 1.27.3, use ./core)
├── go.work.sum
├── README.md                      # Product overview, architecture diagram, build instructions
├── LICENSE                        # MIT License
├── .gitignore                     # Ignores *.a, *.so, *.dylib, *.aar, *.jar, *.apk, macos/.build/, macos/dist/, dist/
├── REWORK_PLAN.md                 # Greenfield rewrite blueprint
├── dist/                          # Release artifacts (gitignored)
│   ├── Snowdrop-v0.10.0-android.apk
│   └── Snowdrop-v0.10.0-macos.zip
├── core/                          # Shared Go networking & transfer engine + platform bridges
├── macos/                         # Legacy macOS SwiftPM app + ShareExtension + build.sh
├── macos-next/                    # Greenfield macOS rewrite SwiftPM workspace (Phase 0 scaffold)
├── artwork/                       # Source SVGs + asset generation script for macOS & Android
└── android/                       # Android Kotlin/Jetpack Compose client + gomobile AAR scripts
```

### Module Boundaries

| Directory / Module | Responsibility | Key Files |
|---|---|---|
| **`core/`** (`github.com/username/snowdrop/core`) | Shared userspace WireGuard (`tsnet`) node lifecycle, peer discovery, HTTP transfer protocol, SHA-256 verification, disk space pre-flight checks, and trusted-peer JSON persistence. | `engine.go`, `transfer.go`, `trust.go`, `disk_space.go`, `types.go`, `bridge_darwin.go`, `bridge_android.go`, `*_test.go`, `go.mod`, `go.sum` |
| **`macos/`** | Legacy macOS menu bar app (`Snowdrop.app`), SwiftPM C-interop wrapper (`CSnowdrop`), Finder Share Extension (`SnowdropShare.appex`), entitlements, plist manifests, icon resources, and packaging script. | `Package.swift`, `build.sh`, `Info.plist`, `MeshDrop.entitlements`, `Frameworks/libsnowdrop.h`, `Sources/CSnowdrop/`, `Sources/Snowdrop/`, `ShareExtension/`, `Resources/` |
| **`artwork/`** | Canonical SVG vector marks/lockups and Python generator script producing raster/icns/vector assets into `macos/Resources/` and `android/app/src/main/res/`. | `build_all_assets.py`, `snowdrop_logo_seamless.svg`, `snowdrop_logo_round.svg`, `snowdrop_horizontal_seamless.svg`, `snowdrop_horizontal_lockup.svg`, `snowdrop_mark_transparent.svg`, `snowdrop_menubar.svg`, `snowdrop_menubar_template.svg` |
| **`android/`** | Android client wrapping `./core` via `gomobile bind` (`core.aar`), Jetpack Compose UI, system Share target, and foreground transfer service. | `build.gradle.kts`, `settings.gradle.kts`, `build_core.sh`, `build.sh`, `app/build.gradle.kts`, `app/libs/core.aar`, `app/src/main/java/com/snowdrop/app/` |
| **`macos-next/`** | Greenfield Swift 6 / macOS 26+ SwiftPM workspace (`Package.swift`, `SnowdropCore`, `SnowdropApp`, `SnowdropCoreTests`). | `macos-next/Package.swift`, `macos-next/Sources/...`, `macos-next/Tests/...` |

### Detailed Legacy Module Contents

```text
core/
├── go.mod
├── go.sum
├── types.go               # Status codes, protocol headers/port (52445), BatchManifest, PeerInfo, EngineConfig
├── engine.go              # Engine struct, tsnet.Server lifecycle, peer sync/dedup, WhoIs resolver, /v1/info client
├── transfer.go            # TransferManager, HTTP Router, single & batch request/stream handlers, path sanitization
├── trust.go               # TrustStore backed by <DataDir>/trusted_peers.json (mode 0600)
├── disk_space.go          # syscall.Statfs disk free-space check (+50 MB headroom)
├── bridge_darwin.go       # //go:build ignore, package main; cgo C-ABI exports for macOS libsnowdrop.a
├── bridge_android.go      # package core; gomobile-compatible exports + anet interface getter for Android
├── engine_test.go
├── transfer_test.go
└── trust_test.go

macos/
├── Package.swift          # SwiftPM 5.9 manifest (macOS 13+, targets: CSnowdrop, Snowdrop)
├── build.sh               # Full build, bundle, sign, install, zip, LaunchServices/IconServices registration script
├── Info.plist             # Main app bundle metadata (com.snowdrop.mac, v0.10.0, snowdrop://, NSServices)
├── MeshDrop.entitlements  # Sandbox=false, network client/server, user-selected/downloads rw (unused by build.sh)
├── Frameworks/
│   └── libsnowdrop.h      # cgo-generated C header (libsnowdrop.a is gitignored and built on demand)
├── Resources/
│   ├── AppIcon.icns
│   ├── AppIcon.png        # 256x256
│   ├── AppIcon@2x.png     # 512x512
│   ├── MenuBarIcon.png    # 18x18
│   └── MenuBarIcon@2x.png # 36x36
├── Sources/
│   ├── CSnowdrop/
│   │   ├── dummy.c        # void _meshdrop_c_anchor(void) {}
│   │   └── include/
│   │       ├── module.modulemap   # module CSnowdrop [system] { header "snowdrop.h" export * }
│   │       └── snowdrop.h         # Hand-written SwiftPM-compatible C header
│   └── Snowdrop/
│       ├── App.swift              # @main SnowdropApp, AppDelegate, StatusItemManager, URL/Services/Notification handlers
│       ├── SnowdropEngine.swift   # ObservableObject wrapper over CSnowdrop C functions & callbacks
│       ├── Models.swift           # EngineStatus, PeerItem, TransferDirection, TransferItem
│       ├── MenuBarView.swift      # Popover UI, settings popover, rename sheet, approval banner, SnowdropFlowerIcon
│       └── TransferCardView.swift # Standalone transfer progress card view
└── ShareExtension/
    ├── Info.plist                 # com.snowdrop.mac.share (XPC!, com.apple.share-services)
    ├── ShareExtension.entitlements# App sandbox = true, files.user-selected.read-only = true
    └── ShareViewController.swift  # NSViewController extracting attachment URL -> snowdrop://send?path=...
```

---

## 2. Legacy macOS Build, Linking, Packaging & Signing Pipeline

`macos/build.sh` (`set -e`) executes all build, bundling, signing, installation, release packaging, and macOS system-cache mutations in one script:

1. **Compile Go C-Archive (`libsnowdrop.a`)**
   ```bash
   go build -buildmode=c-archive -o "$DIR/Frameworks/libsnowdrop.a" core/bridge_darwin.go
   ```
   - Outputs `macos/Frameworks/libsnowdrop.a` and regenerates `macos/Frameworks/libsnowdrop.h`.
   - `core/bridge_darwin.go` carries `//go:build ignore` so standard `go test ./core` skips it while direct file invocation compiles it as `package main`.

2. **Build SwiftPM Release Binary**
   ```bash
   swift build -c release
   ```
   - Produces `macos/.build/release/Snowdrop`, statically linking `macos/Frameworks/libsnowdrop.a` via `-L <pkg>/Frameworks -lsnowdrop`.

3. **Stage Bundle Skeleton (`macos/dist/Snowdrop.app`)**
   - Creates `Contents/{MacOS,Resources}` and `Contents/PlugIns/SnowdropShare.appex/Contents/{MacOS,Resources}`.
   - Copies `.build/release/Snowdrop`, `macos/Info.plist`, `macos/Resources/*`, and `AppIcon.{icns,png}` into the extension resources.

4. **Compile & Populate Share Extension (`SnowdropShare.appex`)**
   ```bash
   swiftc -target arm64-apple-macosx13.0 \
       -parse-as-library \
       -Xlinker -e -Xlinker _NSExtensionMain \
       "$DIR/ShareExtension/ShareViewController.swift" \
       -o "$APP_DIR/Contents/PlugIns/SnowdropShare.appex/Contents/MacOS/SnowdropShare"
   ```
   - Copies `macos/ShareExtension/Info.plist` and writes `PkgInfo` (`APPL????` and `XPC!????`).

5. **Ad-Hoc Code Signing**
   - Signs `SnowdropShare.appex` with `ShareExtension.entitlements`.
   - Signs `Snowdrop.app` ad-hoc **without** `--entitlements` (even though `macos/MeshDrop.entitlements` exists).

6. **Direct Installation & Packaging**
   - Deletes and overwrites `/Applications/Snowdrop.app`, creates `dist/Snowdrop-v0.10.0-macos.zip`, and deletes `macos/dist/Snowdrop.app`.

7. **System Registration & Cache Mutation**
   - Runs `lsregister`, `pluginkit -r/-a/-e`, and `pbs -update`.
   - Executes an inline `swift -e` script calling private `IconServices.framework` (`dlopen` + `ISBundleIdentifierIcon` / `ISImageDescriptor`) for `com.snowdrop.mac` and `com.snowdrop.mac.share`.
   - Kills `ShareSheetUI`, `usernoted`, and `Snowdrop`, then opens `/Applications/Snowdrop.app`.

---

## 3. Dependencies Inventory

### Go Workspace & Modules (`go.work`, `core/go.mod`)

- **Toolchain**: `go 1.27.3` (`go.work` uses `./core`).
- **Codegen Tool**: `golang.org/x/mobile/cmd/gobind` (for Android AAR).
- **Direct Code Imports in `core/*.go`**:
  - `tailscale.com/tsnet`, `tailscale.com/client/local`, `tailscale.com/net/netmon` (`tailscale.com v1.104.4`)
  - `github.com/wlynxg/anet v0.0.5` (`core/bridge_android.go`)
  - Go standard library (`context`, `crypto/sha256`, `crypto/subtle`, `encoding/hex`, `encoding/json`, `errors`, `fmt`, `io`, `math`, `net`, `net/http`, `os`, `path/filepath`, `regexp`, `runtime`, `strconv`, `strings`, `sync`, `syscall`, `time`, `unsafe`, `C`).

### SwiftPM Targets & Linker Flags (`macos/Package.swift`)

- **`swift-tools-version: 5.9`**, package `Snowdrop`, platform `.macOS(.v13)`.
- **Zero external SwiftPM dependencies**; links Apple frameworks (`SwiftUI`, `AppKit`, `UserNotifications`, `Combine`, `UniformTypeIdentifiers`, `Cocoa`).
- **`CSnowdrop`** (`Sources/CSnowdrop`): contains `dummy.c` (`_meshdrop_c_anchor`) and `include/{module.modulemap, snowdrop.h}`.
- **`Snowdrop`** (`Sources/Snowdrop`): depends on `CSnowdrop` and passes `.unsafeFlags(["-L", "\(Context.packageDirectory)/Frameworks", "-lsnowdrop"])`.

### C Bridge Headers: `CSnowdrop/include/snowdrop.h` vs `Frameworks/libsnowdrop.h`

Both headers declare the same 13 C functions and 7 callback typedefs:
- `snowdrop.h` is hand-written with `const char*` and `<stdbool.h>` (`bool`) for clean SwiftPM Clang module import.
- `libsnowdrop.h` is cgo-generated with non-`const` `char*`, `_Bool`, and cgo boilerplate (`_GoString_`).

### Android Touchpoints (`android/`)

- Root Gradle (`android/build.gradle.kts`): AGP `8.2.2`, Kotlin `1.9.22`.
- `android/build_core.sh`: `gomobile bind -target=android/arm64,android/amd64 -androidapi 26 -ldflags="-checklinkname=0" -o "$DIR/app/libs/core.aar" ./core`.
- Any changes to shared Go structs/callbacks in `core/` must keep `bridge_android.go` compiling cleanly.

---

## 4. Assets & Artwork Pipeline

### Source SVGs (`artwork/`)

| File | Dimensions | Role |
|---|---|---|
| `snowdrop_logo_seamless.svg` | `512x512` | Master rounded-rect (`#0F172A` bg) flower mark (`#38BDF8`, `#BAE6FD`, `#FFFFFF`). Source for macOS `AppIcon.icns` & PNGs. |
| `snowdrop_logo_round.svg` | `512x512` | Circular variant overwritten by `build_all_assets.py` for Android round launcher icons. |
| `snowdrop_horizontal_seamless.svg` | `640x180` | Dark rounded-rect horizontal lockup referenced by `README.md`. |
| `snowdrop_horizontal_lockup.svg` | `640x180` | Earlier two-tone horizontal lockup variant. |
| `snowdrop_mark_transparent.svg` | `512x512` | Transparent-background flower mark. |
| `snowdrop_menubar.svg` | `18x18` | Monochrome `#000000` vector with `0.6` opacity inner petals. |
| `snowdrop_menubar_template.svg` | `512x512` | Monochrome `#000000` vector with `<mask id="petal-mask">` overwritten by `build_all_assets.py`. |

### `artwork/build_all_assets.py` & `macos/Resources/`

- Generates `macos/Resources/MenuBarIcon{,@2x}.png` (18×18, 36×36) via `qlmanage` + `sips`. (Note: `App.swift` drew the menu bar template icon procedurally in CoreGraphics instead of loading `MenuBarIcon.png`.)
- Generates `macos/Resources/AppIcon.icns`, `AppIcon.png` (256×256), and `AppIcon@2x.png` (512×512) via `swift` `NSImage` rendering + `iconutil`.

---

## 5. Entry Points & Runtime Targets

1. **`Snowdrop.app` (`com.snowdrop.mac`)**: `LSUIElement = true`, `LSMinimumSystemVersion = 13.0`, v`0.10.0` (10). `@main struct SnowdropApp: App` with `AppDelegate` and `StatusItemManager` (`NSStatusBar.system` + `NSPopover`).
2. **`SnowdropShare.appex` (`com.snowdrop.mac.share`)**: `com.apple.share-services`, `NSExtensionActivationRule = TRUEPREDICATE`, linked with `_NSExtensionMain` (`ShareViewController.swift`).
3. **`NSServices` ("Send with Snowdrop")**: `handleSendService` registered on `NSApp.servicesProvider` (`public.item`, `public.data`, `public.content`).
4. **`snowdrop://` URL Scheme & `CFBundleDocumentTypes`**: Handled by `AppDelegate.application(_:open:)` and `application(_:openFile:)`.
5. **`libsnowdrop.a` (`core/`)**: Userspace `tsnet` WireGuard + HTTP server on Tailnet TCP port `52445`.
