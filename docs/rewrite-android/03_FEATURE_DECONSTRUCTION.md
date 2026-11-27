# 03 Android Feature Deconstruction

Behavioral parity map for the greenfield `android-next/` rewrite (plus macOS-next parity upgrades).

| ID | Feature | Legacy Parity + Greenfield Improvements |
| :--- | :--- | :--- |
| F-00 | Project, Bridge Hardening & Liquid Glass Shell | Hardened `bridge_android.go` + `core.aar`, `SnowdropBackend` interface + `SnowdropStore` `StateFlow`, adaptive Light/Dark Two-Layer Liquid Glass shell + floating bottom navigation capsule |
| F-01 | Tailscale Auth, Connection Lifecycle & Device Rename | Custom Tabs OAuth sign-in, Sign-Out, serialized engine start/stop/restart, device rename dialog persisted in `SharedPreferences` |
| F-02 | Peer Discovery, Presence & Search | Live `PeerItem` list sorted online-first/name, device OS outline icons, inline search filter |
| F-03 | Multi-File Staging (`GetMultipleContents`) | Docked floating Liquid Glass staged-files bar, multi-file size summary, inspect/remove staged items, clear action |
| F-04 | Single & Batch Sending, Concurrent Progress & Cancellation | Concurrent `activeTransfers` map (`tx-*` / `batch-*`), `File X of Y` batch progress, byte/speed/ETA (`tnum`), inline cancel button |
| F-05 | Incoming Approval Queue, Notification Actions & Trust Circle | 3-slot pending approval queue (instead of single slot), floating approval HUD, notification actions (`Accept` / `Always Trust` / `Decline`), timeout cleanup via `OnApprovalDismissed`, Trusted Devices tab & revoke |
| F-06 | Transfer History, MediaStore/SAF Save & Safe Open | `MediaStore.Downloads` with `IS_PENDING = 1` atomic publish + SAF custom folder, transfer history management, `FileProvider` safe `ACTION_VIEW` (no `FileUriExposedException`) |
| F-07 | Settings Tab & Download Folder Persistence | Native Settings tab (replaces hidden sheet), SAF persistable folder picker, Reset to `Downloads/Snowdrop`, Approval/Trusted toggles, Restart Network Stack, Sign Out |
| F-08 | Android 15 Foreground Service & Multi-File Share Target | `TransferService` with `onTimeout` FGS compliance, unique per-transfer notification IDs, Liquid Glass `ShareActivity` supporting `SEND` & `SEND_MULTIPLE` |
