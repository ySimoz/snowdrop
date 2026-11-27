# 04 Android System Guardrails Audit (`targetSdk = 35`)

Hardening requirements enforced across `android-next/` and `core/bridge_android.go`.

1. **Android 15 Foreground Service Timeout (`FGS_DATA_SYNC`)**:
   - `TransferService` declares `foregroundServiceType="dataSync"` (`targetSdk = 35`). Must override `onTimeout(startId: Int, fgsType: Int)` calling `stopForeground(STOP_FOREGROUND_REMOVE)` and `stopSelf()` so Android 15 does not throw `ForegroundServiceDidNotStopInTimeException`.
2. **Notification Safety & Distinct IDs**:
   - Use distinct notification IDs per active/received/approval event instead of colliding constants or random `System.currentTimeMillis()`.
   - Gate notification posting gracefully on `POST_NOTIFICATIONS` permission on API 33+.
3. **Scoped Storage & FileProvider**:
   - Atomic `MediaStore.Downloads` writes using `IS_PENDING = 1` before copy and `IS_PENDING = 0` after flush on API 29+.
   - Serve file previews (`ACTION_VIEW`) via `androidx.core.content.FileProvider` for file paths (`FileProvider` authority `${applicationId}.fileprovider`) — never expose `file://` URIs across IPC (`FileUriExposedException`).
4. **File Descriptor Leak Prevention**:
   - `SendFileToPeer` and `SendBatchToPeer` must close every detached FD on early return or partial failure.
   - `LiveSnowdropBackend` closes `ParcelFileDescriptor` cleanly if JSON serialization fails before `Core.sendBatchToPeer` takes ownership.
5. **Backup & Secrets Exclusion**:
   - `android:allowBackup="false"` in `AndroidManifest.xml` so Tailscale node state/keys in `filesDir` are not backed up unencrypted.
6. **Service Coroutine Scope**:
   - `TransferService` uses `SupervisorJob() + Dispatchers.Main.immediate` cancelled cleanly in `onDestroy()`.
7. **Adaptive Edge-to-Edge System Bars**:
   - `MainActivity` uses `SystemBarStyle.auto(TRANSPARENT, TRANSPARENT)` supporting both Light and Dark themes cleanly with `WindowInsets` padding.
