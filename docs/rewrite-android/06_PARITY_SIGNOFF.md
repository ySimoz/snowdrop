# Android Phase 4 Parity & Guardrails Sign-Off

Final sign-off report for the greenfield `android-next/` Jetpack Compose rewrite (Two-Layer Liquid Glass via `dev.chrisbanes.haze:1.1.1`, Light & Dark Material 3 support, `compileSdk = 35` / `targetSdk = 35`, `minSdk = 26`) and hardened `core/bridge_android.go`.

## 1. Automated Verification (Observed Post-Edit)

| Check | Command / Evidence | Result |
| :--- | :--- | :--- |
| Unslop & Guardrail Scan | `grep -rnE "FontWeight\.Bold\|FrostSlate\|GlowingHalo\|Uri\.fromFile\|…\|..." android-next/app/src/main/java/` | **0 violations** |
| Go core race suite | `go test -race -v ./core` | **47 passed** in 1 package |
| Android Go bridge test compilation | `GOOS=android GOARCH=arm64 go test -ldflags="-checklinkname=0" -c ./core` | **Compiled cleanly** (`core/bridge_android.go` + `core/bridge_android_test.go`) |
| Android AAR bind | `android-next/scripts/build_core.sh` | Generated `android-next/app/libs/core.aar` (NDK 27, 16 KB `0x4000` ELF aligned) |
| 16 KB ELF & zipalign | `llvm-readelf -l` + `zipalign -c -P 16 -v 4` | All `.so` LOAD segments `Align 0x4000` (`arm64-v8a`, `x86_64`), `Verification succesful` |
| Kotlin JUnit suites | `gradlew -p android-next testDebugUnitTest` | **`SnowdropStoreTest`: 10/10 passed**; **`ModelsFormatTest`: 3/3 passed** (13 total, 0 failures, 0 skipped) |
| Android APK build | `gradlew -p android-next assembleDebug` | **`BUILD SUCCESSFUL`** (0 Kotlin warnings; `app-debug.apk`) |

## 2. Connected Device Smoke Status (`5f83d171`)

- Connected device: `2510DPC44G` (`5f83d171`), Android 17 (API 37).
- `adb -s 5f83d171 install -r .../app-debug.apk` succeeded (`Success`), `dumpsys package com.snowdrop.app` reported `primaryCpuAbi=arm64-v8a`, `versionCode=100`, `pageSizeCompat=0` (native 16 KB mode).
- Launched `com.snowdrop.app/.ui.MainActivity` cleanly (`pid 10830`, `AndroidRuntime:E` empty).

## 3. Feature Parity Summary (`F-00`–`F-08`)

All rows in [`docs/rewrite-android/FEATURE_MATRIX.md`](file:///Users/zSimoz/Projects/snowdrop/docs/rewrite-android/FEATURE_MATRIX.md) are marked `DONE`:

- **F-00**: Clean `domain`/`data`/`service`/`ui` architecture, `SnowdropBackend` + `SnowdropStore` (`StateFlow`), `bridge_android.go` `OnApprovalDismissed` + `StopAndWait(3s)` + FD leak prevention, Light/Dark `Theme.kt`, `SnowdropGlassSurface` (`Modifier.haze` / `Modifier.hazeChild` on API 31+ with frosted scrim fallback on API 26–30).
- **F-01**: Tailscale `CustomTabsIntent` auth banner, sign-out, serialized restart, `RenameDeviceDialog` (`SharedPreferences` persistence).
- **F-02**: Online-first sorted `PeerItem` list, outline OS icons, live inline search filter (`DevicesScreen`).
- **F-03**: Multi-file SAF staging (`GetMultipleContents`, `FileMetadataResolver`), floating `FloatingStagedBar` dock, `StagedFilesSheet` item removal & clear.
- **F-04**: Concurrent dictionary-backed transfers (`Map<String, TransferItem>`), inline peer & `TransfersScreen` progress (`File X of Y`, speed, ETA in `tabular()`), cancel action.
- **F-05**: 3-slot `pendingApprovals` queue, `FloatingApprovalHud`, timeout cleanup (`OnApprovalDismissed`), distinct per-transfer approval notification actions (`Accept` / `Always Trust` / `Decline`), `TrustedScreen` revoke.
- **F-06**: `ReceivedFileStorage` (SAF custom tree, `MediaStore.Downloads` with atomic `IS_PENDING = 1` -> `0`, `FileProvider` URI fallback on API 26–28), transfer history `SwipeToDismissBox`, `ACTION_VIEW` open.
- **F-07**: Native `SettingsScreen` tab with Rename, persistable `OpenDocumentTree` folder picker, Reset, Approval toggles, Restart Network Stack, Sign Out.
- **F-08**: Android 15 `onTimeout`-compliant `TransferService` observing `uiState` concurrent transfers, distinct notification IDs, and Liquid Glass `ShareActivity` (`SEND` / `SEND_MULTIPLE` / `clipData`).
