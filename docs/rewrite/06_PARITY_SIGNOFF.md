# Phase 4 Parity & Guardrails Sign-Off

Final sign-off report for the greenfield `macos-next/` SwiftUI rewrite (macOS 26+, Swift 6 strict concurrency, Apple Liquid Glass Two-Layer design) and hardened `core/` Go C-FFI backend.

## 1. Automated Verification (Observed Post-Edit)

| Check | Command | Result |
| :--- | :--- | :--- |
| Go core race suite | `go test -race -v ./core` | **47 passed** in 1 package (includes `TestZeroByteBatchAcceptedAndExpiredEntriesPruned`) |
| Universal C static library | `macos-next/scripts/build_core.sh` | Built `macos-next/Frameworks/libsnowdrop.a` (`arm64` + `x86_64`, `-mmacosx-version-min=26.0`) |
| Swift package unit & bridge tests | `swift test --package-path macos-next` | **`SnowdropCoreTests`: 24 passed** in 4 suites; **`SnowdropBridgeTests`: 1 passed** in 1 suite |
| Xcode project generation | `xcodegen generate --spec macos-next/project.yml` | Generated `macos-next/Snowdrop.xcodeproj` (`Snowdrop`, `SnowdropShare`, `SnowdropCore`, `SnowdropBridge`) |
| macOS app + Share Extension build | `xcodebuild -project macos-next/Snowdrop.xcodeproj -scheme Snowdrop -configuration Debug CODE_SIGNING_ALLOWED=NO build` | **`** BUILD SUCCEEDED **`** (`AppIcon.icns`, `Assets.car`, and `SnowdropShare.appex` embedded cleanly) |
| Phase 4 Parity & Guardrails Auditor | Subagent `c051241a-b844-4314-84ea-c19d4d87f54e` | **`PARITY APPROVED`** |

## 2. Phase 4 Gap Fixes Resolved

1. **AppIcon Asset Catalog (`macos-next/Resources/Assets.xcassets`, `macos-next/project.yml`)**: Generated 16x16 through 512x512@2x `AppIcon.appiconset` PNGs and wired `Resources/Assets.xcassets` into both `Snowdrop` and `SnowdropShare`; verified `AppIcon.icns` and `Assets.car` are emplaced in `Snowdrop.app/Contents/Resources/` with zero private `IconServices`/`dlopen` APIs.
2. **Go Core Transfer Hardening (`core/transfer.go`, `core/engine_bridge_test.go`)**:
   - Added `pruneExpiredLocked(time.Now(), 15*time.Minute)` reaped on `/v1/transfer/request` and `/v1/transfer/batch/request`.
   - Accepted 0-byte file batches (`manifest.TotalBytes < 0` check).
   - Incremented `batch.TransferredBytes += transferred` using actual received byte counts.
   - Added `TestZeroByteBatchAcceptedAndExpiredEntriesPruned`.
3. **Menu Bar Active Transfer Fallback (`macos-next/Sources/SnowdropApp/MenuBarCompanionView.swift`)**: Added `unmatchedActiveTransfers` / `unmatchedTransfersSection` above `stagingSection` so active transfers with offline, unmatched, or post-top-5 peers remain visible in the popover.

## 3. Feature Parity Matrix (`F-00`–`F-09`)

All rows in [`docs/rewrite/FEATURE_MATRIX.md`](file:///Users/zSimoz/Projects/snowdrop/docs/rewrite/FEATURE_MATRIX.md) are marked `DONE` with all 5 sign-off columns (`Backend Bridge`, `SwiftUI + Liquid Glass`, `Automated Tests`, `HIG Critic Sign-Off`, `Guardrail Sign-Off`) checked:

| ID | Scope Delivered | Key Implementation |
| :--- | :--- | :--- |
| F-00 | Greenfield project, Sandbox + Hardened Runtime, typed Go C-FFI bridge, `NavigationSplitView` shell | `core/{types,engine,transfer,bridge_darwin}.go`, `LiveSnowdropBackend`, `MainShellView`, `project.yml` |
| F-01 | Auth/Sign-Out, connection lifecycle, `.terminateLater`, device rename | `SnowdropStore`, `AppDelegate`, `RenameDeviceSheet`, `SettingsShellView` |
| F-02 | Live peer discovery, OS symbols, online/offline presence, `⌘F` search | `DevicesView`, `SnowdropStore.sortedFilteredPeers` |
| F-03 | `NSOpenPanel` (`⌘O`), `.dropDestination`, symlink-resolved path check, staged floating bar | `FilePathValidator`, `SecurityScopedAccessTracker`, `DevicesView` |
| F-04 | Single/batch send, concurrent dictionary-backed transfers, `File X of Y`, cancel (`⌘.`) | `SnowdropStore`, `TransfersView`, `DevicesView` |
| F-05 | 3-slot incoming approval queue, notification actions, 60s timeout, trust circle | `ApprovalOverlayView`, `NotificationManager`, `TrustedDevicesView` |
| F-06 | History management, real peer/filename metadata, exact `Show in Finder` (`⌘R`) | `TransfersView`, `OnBatchFileReceived` callback |
| F-07 | Native `Settings` (`⌘,`) + security-scoped `BookmarkStore` synced via `SetDownloadDir` | `SettingsShellView`, `BookmarkStore` |
| F-08 | `MenuBarExtra(.window)` 18×18 template icon, quick drop, active transfer fallback, commands | `MenuBarCompanionView`, `MenuBarIconRenderer`, `SnowdropCommands` |
| F-09 | Multi-file App Group `ShareViewController` (`snowdrop://handoff?id=<uuid>`) + `NSServices` | `ShareExtension/ShareViewController.swift`, `ShareHandoff` |

## 4. Distribution & Live-UI Prerequisites (Out of Unsigned CLI Scope)

1. **Signing & App Groups**: Local verification builds unsigned (`CODE_SIGNING_ALLOWED=NO`) with `Snowdrop.entitlements` / `SnowdropShare.entitlements` (App Sandbox + Hardened Runtime) so macOS AMFI permits local launch without a provisioning profile. Release builds require selecting a paid Apple Developer Team ID and switching to `Snowdrop.AppGroups.entitlements` / `SnowdropShare.AppGroups.entitlements` (`$(TeamIdentifierPrefix)com.snowdrop.mac.shared`) + notarization.
2. **Interactive GUI & Live Tailnet End-to-End Test**: Unit/bridge suites verified state transitions, C-FFI lifecycle, file/bookmark security, and Go race safety offline; interactive window layout screenshots, Finder Share Sheet host invocation, and multi-device Tailnet file transfers were not executed headlessly and require interactive macOS desktop testing.
