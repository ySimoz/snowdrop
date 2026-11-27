# 02 — Backend Contract (`core/` & C FFI Surface)

Specification of the preserved Go networking/transfer engine (`core/`), data schemas, HTTP protocol, C-ABI surface, and legacy bridge defects to fix in Phase 2.

---

## 1. Core Preserved Engine Architecture

* **Go Module**: `github.com/username/snowdrop/core` (`go 1.27.3`, `tailscale.com v1.104.4` using `tsnet` and `client/local`).
* **`Engine` Struct (`core/engine.go`)**: Holds `config *EngineConfig`, `tsServer *tsnet.Server`, `listener net.Listener`, `httpSrv *http.Server`, `transfers *TransferManager`, `trustStore *TrustStore`, `ctx`/`cancel`, `wg sync.WaitGroup`, `mu sync.Mutex`, `status int`, `authURL string`, `lastPeers string`, `peerNamesMu sync.RWMutex`, `peerNames map[string]string`.
* **Initialization (`NewEngine(cfg *EngineConfig)`)**:
  * Rejects `nil` config, empty `DataDir`, or empty `DownloadDir`.
  * Defaults `Port <= 0` to `DefaultPort` (`52445`) and empty `DeviceName` to `"device"`.
  * Instantiates `TrustStore` (`NewTrustStore(cfg.DataDir)`) and `TransferManager` (`NewTransferManager(cfg, ts)`).
* **Status Codes (`core/types.go`)**:
  * `0`: `StatusDisconnected`
  * `1`: `StatusNeedsAuth`
  * `2`: `StatusConnecting`
  * `3`: `StatusConnected`
  * `4`: `StatusError`
* **Lifecycle (`Start` / `runServer` / `monitorStatus` / `Stop` / `SignOut`)**:
  1. **`Start()`**: Ensures `DataDir` (`0700`) and `DownloadDir` (`0755`). Computes `serverHostname = "snowdrop-" + sanitizeHostname(DeviceName)` (alphanumeric/dash lowercase, max 32 chars, fallback `"device"`). Creates persistent `&tsnet.Server{Dir: DataDir, Hostname: serverHostname, Ephemeral: false}` with `UserLogf` extracting auth URLs (`https?://[^\s]+`). Spawns `runServer` and `monitorStatus`.
  2. **`runServer()`**: Starts `tsServer`, binds Tailscale `WhoIsResolver` (`LocalClient.WhoIs(ctx, remoteAddr)` -> `ComputedName` / `Hostinfo.Hostname()`), listens on Tailnet TCP `:52445`, and runs `&http.Server{Handler: transfers.Router(serverHostname), ReadTimeout: 10m, WriteTimeout: 10m}`.
  3. **`monitorStatus()` & Peer Sync**: Polls `lc.Status` every `2s`. Maps `BackendState` (`Running` -> `3`, `NeedsLogin`/`NeedsMachineAuth` -> `1`, `Starting` -> `1` if `authURL` set else `2`, `Stopped`/`NoState` -> `0`). Classifies `snowdrop-*` peers, queries `GET http://<ip>:52445/v1/info` (2s timeout) for friendly `deviceName`, falls back to non-Snowdrop peers only if zero Snowdrop peers exist, deduplicates `-\d+` collision suffixes preferring online nodes, and emits `OnPeersUpdated` JSON on change.
  4. **`Stop()`**: Cancels context, closes `httpSrv`, `listener`, and `tsServer`, waits on `wg.Wait()`, and emits `StatusDisconnected`.
  5. **`SignOut()`**: Calls `lc.Logout(ctx)` (10s timeout) and `lc.StartLoginInteractive(ctx)`, emitting `StatusNeedsAuth`.

---

## 2. Data Models & Persisted State

### JSON Schemas

* **`PeerInfo`** (`core/types.go`): `id`, `hostName`, `displayName`, `dnsName`, `os`, `ipAddresses` (`[string]`), `online` (`bool`).
* **`NodeInfo`** (`GET /v1/info`): `nodeId`, `deviceName`, `os`, `protocolVersion` (`1`).
* **`BatchManifest`** (`core/types.go`): `batchId`, `senderNodeId` (`omitempty`), `senderName`, `totalBytes`, `files` (`[{fileId, fileName, fileSize, sha256}]`).
* **`TrustedPeer`** (`core/trust.go`): `node_id`, `device_name`, `added_at` (RFC3339), `auto_accept` (`bool`).

### Persisted State & File Permissions

| Artifact | Path | Permissions | Lifecycle / Notes |
|---|---|---|---|
| `tsnet` identity & Tailscale state | `<DataDir>/` | `0700` dir | `tsnet.Server{Ephemeral: false}`. |
| Trusted peers store | `<DataDir>/trusted_peers.json` | `0600` | Atomic write via `trusted_peers.json.tmp` + `os.Rename`. |
| Single-file staging part | `<DownloadDir>/.<transferID>.part` | `0600` | Renamed via `resolveUniquePath` on SHA-256 pass; deleted on error/cancel/mismatch. |
| Batch-file staging part | `<DownloadDir>/.<batchID>-<fileID>.part` | `0600` | Same atomic write-and-rename lifecycle per file in batch. |

---

## 3. Network & Streaming Transfer Protocol

* **Transport**: HTTP/1.1 over WireGuard/`tsnet` TCP port `52445`, `BufferSize = 64 * 1024` (64 KB chunks), `ProtocolVersion = 1`.
* **Headers**: `X-Transfer-ID`, `X-File-Name`, `X-File-Size`, `X-File-SHA256`, `X-Sender-Name`, `X-Sender-Node-ID`, `X-Snowdrop-Batch-ID`, `X-Snowdrop-File-ID`.

### Endpoints (`TransferManager.Router`, `core/transfer.go`)

1. **`GET /v1/info`** -> `200 OK` with `NodeInfo` JSON.
2. **`POST /v1/transfer/request`** (Single-file pre-flight):
   * Validates headers (`X-Transfer-ID`, sanitized `X-File-Name`, `X-File-Size >= 0`, `X-File-SHA256`) -> `400`.
   * Resolves sender node ID via `whoIsResolver` (CWE-290).
   * Pre-flight disk check: `fileSize + 50 MiB` via `syscall.Statfs` -> `507 Insufficient Storage`.
   * Duplicate `transferID` -> `409 Conflict`.
   * Approval gate (when `RequireApproval && !(IsTrusted && AutoAcceptTrusted)`): max 3 concurrent pending approvals (`429`), 60s timeout (`408`). Decisions: `1` = Accept (`200`), `2` = Always Trust (`AddTrusted` + `200`), `3` = Decline (`403`).
3. **`POST /v1/transfer/batch/request`** (Multi-file batch pre-flight):
   * `http.MaxBytesReader` caps manifest body at `1 MiB`.
   * Validates `BatchID`, non-empty `Files`, `sum(FileSize) == TotalBytes`, disk space (`TotalBytes + 50 MiB`), WhoIs identity, duplicate `BatchID` (`409`), and approval gate. Returns `200 OK` `{"batchId": "<id>", "status": "approved"}`.
4. **`POST /v1/transfer/stream`** (Data plane):
   * Streams `64 KB` chunks to `0600` `.part` file, updating SHA-256 and invoking progress callbacks.
   * Verifies SHA-256 via `crypto/subtle.ConstantTimeCompare` (CWE-208); mismatch deletes `.part` and returns `400`.
   * Renames `.part` to `resolveUniquePath(DownloadDir, fileName)` (`"name (1).ext"` .. `"name (10000).ext"`), fires `OnBatchFileReceived` / `OnTransferComplete`.
   * Cancellation (`Cancel(id)`) cancels stream context, cleans `.part`, fires `OnTransferComplete(id, false, "transfer canceled")`, returns `408`.

### Path Sanitization (CWE-22)

* `sanitizeFileName`: strips NUL (`0`), ASCII control (`< 32`), DEL (`127`); runs `filepath.Base(filepath.Clean(name))`; replaces `/` and `\` with `_`; maps `""`, `"."`, `".."` to `"file"`.
* `resolveUniquePath`: validates `filepath.Rel(dir, candidate)` stays inside `dir`.

---

## 4. Exact C FFI Surface (`core/bridge_darwin.go` & `snowdrop.h`)

### Callbacks
`StatusCallback`, `AuthRequiredCallback`, `PeersUpdatedCallback`, `ProgressCallback`, `TransferCompleteCallback`, `ApprovalCallback`, `BatchProgressCallback`.

### Exported Functions
- `RegisterCallbacks(...)`, `RegisterApprovalCallback(cb)`, `RegisterBatchProgressCallback(cb)`
- `StartEngine(dataDir, downloadDir, deviceName) -> int` (`0` ok, `-1` `NewEngine` err, `-2` `Start` err)
- `StopEngine()`
- `SendFile(peerIP, filePath, transferID)`
- `SendBatch(peerIP, batchID, filesJSON)`
- `CancelTransfer(transferID)`
- `ResolveTransferApproval(transferID, decision) -> bool`
- `GetTrustedPeers() -> char*` (heap-allocated `C.CString`; caller must `free()`)
- `RevokeTrusted(nodeID) -> bool`
- `SetApprovalConfig(requireApproval, autoAcceptTrusted)`
- `SnowdropSignOut() -> bool`

### Memory Ownership Rules
1. **Caller -> Go (`const char*`)**: Copied synchronously via `C.GoString` before returning/spawning goroutines.
2. **Go -> Caller callbacks**: Allocated via `C.CString` and freed immediately via `defer C.free` when the callback returns; Swift callbacks MUST copy synchronously before hopping actors.
3. **Go -> Caller return (`GetTrustedPeers`)**: Caller owns the pointer and must free it (greenfield should add `FreeCString(const char*)` in Go).

### Missing Exports
- `OnBatchFileReceived` is wired in `bridge_android.go` (`OnBatchFileComplete`) but unbridged in `bridge_darwin.go`.
- No `SetDownloadDir(const char* dir)` export exists.

---

## 5. Known Legacy Bridge & Engine Defects to Fix in Phase 2

1. **`downloadDirectory` changes never reach Go**: Swift never persists `downloadDirectory` or updates `TransferManager.config.DownloadDir`. Add `SetDownloadDir` export (guarded by mutex) + security-scoped bookmark persistence.
2. **Synchronous C FFI calls on Main/Caller thread**: `SetApprovalConfig`, `SendFile`, `SendBatch`, `CancelTransfer`, `ResolveTransferApproval`, `GetTrustedPeers`, `RevokeTrusted` block UI/caller threads on Go mutexes and disk I/O (`TrustStore.saveLocked`). Wrap all C FFI calls inside a Swift `actor`.
3. **Racy 300ms restart & async `StopEngine()`**: `StopEngine()` spawns `wg.Wait()` without blocking, while `SnowdropEngine.restart()` uses a blind `0.3s` timer, risking concurrent `tsnet.Server` instances sharing `DataDir`. Make `StopEngine` bounded-synchronous (or await completion) and serialize `start`/`stop`/`restart`.
4. **Single `activeTransfer` slot**: Swift tracks only one `TransferItem?` while Go supports concurrent transfers; concurrent transfers overwrite progress and drop completions. Track `[String: TransferItem]` keyed by `transferID`.
5. **Swallowed `SendFile`/`SendBatch` errors**: `bridge_darwin.go` ignores returned errors (`_ = eng.SendFile(...)`), and early `json.Unmarshal` / `tsServer == nil` failures never emit `OnTransferComplete`, leaving UI stuck indefinitely. Emit failure completion callbacks on every error path.
6. **`SetApprovalConfig` data race & non-persistence**: `Engine.SetApprovalConfig` writes `config.RequireApproval`/`AutoAcceptTrusted` under `Engine.mu` while `TransferManager` reads them without locking `Engine.mu`, and neither Go nor Swift persists them. Pass initial values in `StartEngine` (or persist in `UserDefaults`) and protect reads/writes with an atomic/mutex accessor.
7. **Go data race on `e.lastPeers`**: `monitorStatus` and `go e.syncPeers(nil)` read/write `e.lastPeers` without synchronization; protect under `e.mu` or a dedicated `syncMu`.
8. **Process-wide `os.Setenv("TMPDIR", DataDir)` (`core/engine.go:81-85`)**: Overrides the macOS sandbox container's `NSTemporaryDirectory()` for the entire host process. Remove/guard for Darwin.
9. **Approval timeout leaves UI stuck**: 60s approval timeout or sender disconnect returns HTTP `408` without notifying Swift to dismiss `pendingApproval`. Emit an approval-expired/cancelled notification callback.
10. **Batch accounting & zero-byte batches**: `BatchSession.TransferredBytes` adds `fileItem.FileSize` instead of actual bytes, `manifest.TotalBytes <= 0` rejects valid 0-byte file batches, `tm.pending`/`tm.batches` lack a TTL reaper, and `bridge_darwin.go` lacks `//go:build darwin && cgo` vet coverage.
11. **Missing startup `GetTrustedPeers()` & broken batch Finder reveal**: Trusted peers are not fetched on startup/connect, and Darwin drops `OnBatchFileReceived`, breaking Finder reveal for batches and renamed duplicates (`"file (1).ext"`).
