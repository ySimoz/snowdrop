# 01 Legacy Android Topology & Unslop Audit

Inventory of the legacy `android/` codebase (left untouched) and visual/structural debt to eliminate in `android-next/`.

## 1. File & Build Inventory

- **Build stack**: AGP `8.2.2`, Kotlin `1.9.22`, Compose compiler `1.5.8`, `compileSdk = 34`, `targetSdk = 34`, `minSdk = 26`, Compose BOM `2024.02.00`.
- **Source files** (7 Kotlin files under `android/app/src/main/java/com/snowdrop/app/`):
  - `SnowdropApplication.kt` (11 lines) — eagerly starts `SnowdropCoreBridge.init(this)` on launch.
  - `core/SnowdropCoreBridge.kt` (848 lines) — monolithic singleton mixing Go `gomobile` FFI, Android `SharedPreferences`, `ContentResolver`/MediaStore/SAF storage, notifications, and UI `StateFlow`s.
  - `service/TransferService.kt` (349 lines) — foreground service + `TransferActionReceiver`.
  - `ui/MainActivity.kt` (47 lines) — forces dark system bars (`SystemBarStyle.dark`) regardless of system theme.
  - `ui/ShareActivity.kt` (171 lines) — translucent `SEND`/`SEND_MULTIPLE` share sheet using dark scrim + M3 cards.
  - `ui/SnowdropScreen.kt` (1,415 lines) — monolithic single-file screen containing all banners, staging UI, peer list, transfer history, swipe-to-dismiss, rename dialog, and settings `ModalBottomSheet`.
  - `ui/theme/Theme.kt` (76 lines) — defines `LightColorScheme` and `DarkColorScheme`, then ignores light mode in `SnowdropScreen.kt` by referencing dark-only `FrostSlate*` / `GlassCardBg` tokens directly.

## 2. Visual & Unslop Audit

| Area | Legacy Finding (`SnowdropScreen.kt` / `Theme.kt`) | Greenfield Fix |
| :--- | :--- | :--- |
| Theme polarity | Hardcoded `FrostSlate900`/`FrostSlate800`/`FrostSlate100` breaks light mode | Semantic `SnowdropPalette` mapped to both Light & Dark Material 3 themes |
| Fake "glass" cards | Flat `Color(0xBF1E293B)` + neon cyan `GlassBorder` (`0x3338BDF8`) on scrolling cards | Layer 1 solid neutral surfaces + 8%-opacity hairline borders; Layer 2 real `haze` backdrop blur strictly on floating chrome |
| Slop motion/glow | `GlowingHaloDot` (`14.dp` alpha halo), arbitrary spacer/corner values | Static 6–8.dp status dot (`monospacedDigit` where numeric); 4.dp spacing scale |
| Typography & copy | `UPPERCASE` tracked section headers (`DEVICE NAME`, `TRANSFERRING`), pervasive `FontWeight.Bold`, `...` button labels (`Change Folder...`) | Sentence case everywhere, weights `400`/`500` (`600` max for emphasis), `fontFeatureSettings = "tnum"`, no trailing ellipses on action buttons |
| Icons | Filled `Icons.Default.*` mixed inconsistently | Uniform `Icons.Outlined.*` at fixed 18–20.dp sizing |
