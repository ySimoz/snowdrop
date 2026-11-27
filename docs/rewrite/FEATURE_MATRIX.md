# Feature Rewrite Progress Matrix

Ordered dependency graph for Phase 2 (`F-00`) and Phase 3 (`F-01` through `F-09`) of the greenfield macOS 26 + Liquid Glass rewrite.

| ID | Feature Name | Dependencies | Backend Bridge | SwiftUI + Liquid Glass | Automated Tests | HIG Critic Sign-Off | Guardrail Sign-Off | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| F-00 | App Shell, NavigationSplitView, Xcode/Sandbox Setup & Typed Backend Bridge | None | [x] | [x] | [x] | [x] | [x] | DONE |
| F-01 | Tailnet Auth, Connection Lifecycle & Device Rename | F-00 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-02 | Peer Discovery, Presence & Search (`⌘F`) | F-01 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-03 | File Staging, Drag-and-Drop & Sensitive-Path Validation | F-00 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-04 | Single & Multi-File Batch Sending, Concurrent Progress & Cancellation | F-02, F-03 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-05 | Incoming Approval Queue, Notification Actions & Trust Circle | F-01 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-06 | Transfer History, Metadata Fidelity & Accurate Finder Reveal (`⌘R`) | F-04, F-05 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-07 | Native Settings (`⌘,`) & Security-Scoped Bookmark Persistence | F-01, F-05 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-08 | MenuBarExtra Quick-Drop Companion & Keyboard Commands | F-04, F-05 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-09 | Sandboxed Multi-File Share Extension (App Group) & Finder Services | F-03 | [x] | [x] | [x] | [x] | [x] | DONE |

---

## Feature Scope Summary

* **F-00**: Greenfield XcodeGen project (`Snowdrop.app` + `SnowdropShare.appex` + `SnowdropCore` + `CSnowdrop`), App Sandbox + Hardened Runtime entitlements, `05_GREENFIELD_ARCHITECTURE.md`, actor-isolated C-FFI bridge (`SetDownloadDir`, `OnBatchFileReceived`, `FreeCString`, bounded `StopEngine`, error emission, Go data-race fixes, removal of `os.Setenv("TMPDIR")`), `NavigationSplitView` shell, and `Commands`.
* **F-01**: Serialized engine `start`/`stop`/`restart` + `.terminateLater` app shutdown, status machine (`disconnected`/`needsAuth`/`connecting`/`connected`/`error`), Tailscale sign-in URL launch & sign-out, device rename sheet + `UserDefaults` persistence.
* **F-02**: Live `PeerItem` list, OS icons, online/offline presence, `.searchable` (`⌘F`), and empty states.
* **F-03**: `NSOpenPanel` (`⌘O`), always-available `.dropDestination(for: URL.self)`, `application(_:open:)`, symlink-resolved sensitive-path guard, security-scoped URL tracking, and floating `GlassEffectContainer` staged-files action bar.
* **F-04**: `SendFile`/`SendBatch`, dictionary-backed concurrent transfer state (`[String: TransferItem]`), inline peer + Transfers-tab progress with batch sub-progress (`File X of Y`), speed/ETA (`monospacedDigit`), cancel (`⌘.`), and surfaced error banners.
* **F-05**: Multi-request approval queue (up to 3 concurrent), `INCOMING_TRANSFER_APPROVAL` notification category (`ACTION_ACCEPT`/`ACTION_TRUST`/`ACTION_DECLINE`), floating Liquid Glass approval HUD, 60s timeout cleanup, Trusted Devices view & revocation, persisted `requireApproval`/`autoAccept`.
* **F-06**: Transfers view + history management (`Clear All`, `Remove`), real peer/filename tracking (`OnBatchFileReceived` + approval metadata), and exact destination URL `Show in Finder` (`⌘R`).
* **F-07**: Native `Settings` scene (`⌘,`) with `General`, `Trust & Approvals`, and `Network & Account` tabs; security-scoped bookmark persistence for `downloadDirectory` synced to Go via `SetDownloadDir`; Reset folder and Restart Network Stack.
* **F-08**: `MenuBarExtra(.window)` companion with 18×18 template icon, quick drop, status/peers/active-transfer summary, `Open Snowdrop Window` (`⌘0`), and `Quit` (`⌘Q`).
* **F-09**: Multi-file `ShareViewController` (fixing legacy `break` bug), App Group container handoff (`snowdrop://handoff?id=<uuid>`), `NSServices` (`Send with Snowdrop`), and removal of private `IconServices` `dlopen` hacks.

---

## Gatekeeper Sign-Off Checklist (Required Per Feature)

Before marking any feature `DONE`, `@Orchestrator` must verify:
- [ ] **Backend Isolation:** Core backend logic remains decoupled from SwiftUI views; all calls are async and properly typed.
- [ ] **Liquid Glass Discipline:** `.glassEffect()` is used strictly on floating controls/chrome, never on scrollable content layers or stacked glass-on-glass.
- [ ] **Modifier Order:** `.glassEffect()` is applied *after* `.padding()` and `.frame()`.
- [ ] **Accessibility:** Verified legible with Reduce Transparency and Increase Contrast enabled; all controls have VoiceOver labels and keyboard shortcuts.
- [ ] **macOS Guardrails:** Zero Swift 6 concurrency warnings, zero synchronous main-thread I/O, proper sandbox/file-bookmark handling, and clean error states.
- [ ] **Tests Passing:** Unit tests and UI tests for this feature pass 100%.
