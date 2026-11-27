# 02 Core Backend Contract (`core/bridge_android.go`)

Contract between Go `core` (`gomobile bind`) and the Android `data` layer.

## 1. Exported Go Functions (`package core` → `core.Core`)

- `StartAndroidEngine(dataDir string, downloadDir string, deviceName string, cb AndroidCallback) error`
- `StopAndroidEngine()`
- `SendFileToPeer(peerIP string, fileDescriptor int, fileName string, fileSize int64, transferID string)`
- `SendBatchToPeer(peerIP string, batchID string, filesJSON string)`
- `CancelAndroidTransfer(transferID string)`
- `ResolveAndroidApproval(transferID string, decision int) bool` (`1=accept`, `2=alwaysTrust`, `3=decline`)
- `GetAndroidTrustedPeersJSON() string`
- `RevokeAndroidTrusted(nodeID string) bool`
- `SetAndroidApprovalConfig(requireApproval bool, autoAcceptTrusted bool)`
- `SignOutAndroid() bool`

## 2. `AndroidCallback` Methods

- `OnStatusChange(status int, message string)` (`0=Disconnected`, `1=NeedsAuth`, `2=Connecting`, `3=Connected`, `4=Error`)
- `OnAuthRequired(authURL string)`
- `OnPeersUpdated(peersJSON string)`
- `OnProgress(transferId string, current int64, total int64)`
- `OnTransferComplete(transferId string, success bool, errorMsg string)`
- `OnIncomingApproval(transferId string, senderNodeId string, senderName string, fileName string, fileSize int64)`
- `OnApprovalDismissed(transferId string, reason string)` — **Added in F-00** (wired to `EngineConfig.OnApprovalDismissed` so timed-out approvals clear from Android UI & notifications)
- `OnBatchProgress(batchId string, fileIndex int, totalFiles int, fileName string, fileCurrent int64, fileTotal int64, batchCurrent int64, batchTotal int64)`
- `OnBatchFileComplete(batchId string, fileIndex int, totalFiles int, fileName string, filePath string)`

## 3. Hardening Changes (`core/bridge_android.go`)

1. Wire `OnApprovalDismissed` on `AndroidCallback` and `EngineConfig`.
2. Hold `androidMu` across `StartAndroidEngine` and `StopAndroidEngine` and call `eng.StopAndWait(3 * time.Second)` to eliminate start/stop races.
3. Close detached Android file descriptors in `SendFileToPeer` and `SendBatchToPeer` whenever `eng == nil`, JSON unmarshaling fails, `items` is empty, or building `filesToClose` fails partway.
