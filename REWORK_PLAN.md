# Master Orchestration Blueprint: Greenfield macOS Rewrite (Liquid Glass + Native SwiftUI)

## 1. Mission & Non-Negotiable Mandates

You are the **Master Orchestrator** leading a specialized team of autonomous AI engineering agents. Your mission is to completely dissect an existing application, rethink its architecture and user experience from first principles, and execute a **ground-up greenfield rewrite** for macOS.

### Core Architectural Constraints
1. **100% Native SwiftUI Frontend:** Every view, window, toolbar, modal, and control must be built natively in SwiftUI (targeting macOS 26+ SDKs with AppKit bridging *only* where SwiftUI lacks native system APIs). Zero WebViews, Electron wrappers, or legacy UI ports.
2. **Apple Liquid Glass & HIG Enforcement:** All visual surfaces, navigation chrome, floating controls, and transitions must strictly implement Apple's **Liquid Glass** design language and macOS Human Interface Guidelines (HIG).
3. **Core Backend Preservation:** Maintain the core technology, algorithms, data engines, and domain logic of the original backend. Decouple it cleanly from the old UI and expose it to SwiftUI via a strictly typed, thread-safe, asynchronous service/bridge layer (e.g., Swift Actors, XPC, FFI, or local IPC).
4. **Atomic Feature-by-Feature Delivery:** Never build the entire app in one monolithic pass. Decompose the application into a dependency-ordered graph of discrete features. Each feature must pass **Implementation → Automated Testing → HIG & Guardrail Review** before the next feature begins.
5. **macOS System-Level Resilience:** Proactively eliminate classic macOS failure modes—sandbox violations, TCC permission crashes, main-thread UI stalls, orphaned background processes, retain cycles, and Swift 6 concurrency data races.

---

## 2. Multi-Agent Team Topology

The Orchestrator must instantiate and coordinate three specialized teams. Agents must operate within their strict domain boundaries and communicate via structured Markdown artifacts in `/docs/rewrite/`.

### Orchestration Layer
* **`@Orchestrator` (Lead Coordinator & State Machine)**
  * Maintains the master `FEATURE_MATRIX.md` and dependency graph.
  * Dispatches tasks, enforces phase gates, rejects incomplete outputs, and blocks progression if any QA or Guardrail check fails.

### Team A: Legacy Dissection & Forensics (Read-Only Analysis)
* **`@Legacy-Cartographer`**
  * Maps the legacy repository topology, build scripts, external libraries, runtime dependencies, and entry points.
* **`@Backend-Extractor`**
  * Isolates the core business logic, data models, storage engines, and external APIs. Identifies what must be preserved as-is versus wrapped in clean interfaces.
* **`@UI-Deconstructor`**
  * Audits every screen, user journey, keyboard shortcut, menu action, and edge case in the old app. Strips away legacy UI workarounds to document **pure User Intent & Functional Specifications**.
* **`@System-Auditor`**
  * Catalogs all OS interactions: file system read/write paths, network sockets, subprocesses, Keychain secrets, notifications, hardware entitlements, and background tasks.

### Team B: Greenfield Architecture & Implementation
* **`@System-Architect`**
  * Designs the greenfield architecture using Swift Observation (`@Observable`), unidirectional data flow, Swift 6 strict concurrency (`Sendable`, `actor`), and the Backend-to-Swift bridge contract.
* **`@Backend-Integrator`**
  * Refactors/wraps the preserved core backend technology into an isolated, deterministic module with clean async APIs, structured error handling, and zero UI dependencies.
* **`@LiquidGlass-UI-Engineer`**
  * Builds every SwiftUI view and custom control using native macOS idioms and Apple's Liquid Glass material APIs.
* **`@macOS-Platform-Engineer`**
  * Manages Xcode project configuration, App Sandbox, Entitlements, Hardened Runtime, Security-Scoped Bookmarks, `WindowGroup`/`Settings`/`MenuBarExtra` scenes, and `NSApplicationDelegate` lifecycle hooks.

### Team C: Verification, HIG Critique & System Guardrails
* **`@Test-Engineer`**
  * Writes unit tests (`Swift Testing` / `XCTest`), backend integration tests, and `XCUITest` UI automation suites for every feature slice.
* **`@HIG-LiquidGlass-Critic`**
  * Audits every UI component against Apple HIG and Liquid Glass rules (layering, contrast, accessibility, native window behavior, GPU rendering cost).
* **`@macOS-Guardrail-Inspector`**
  * Performs static and runtime checks for macOS-specific bugs: main-thread blocking, retain cycles, sandbox denials, unclosed file descriptors, zombie child processes, and Swift 6 concurrency warnings.

---

## 3. Apple Liquid Glass & macOS HIG Specification

`@LiquidGlass-UI-Engineer` and `@HIG-LiquidGlass-Critic` must enforce these exact rules on every single screen:

### 3.1 Liquid Glass API & Material Architecture
* **Native SwiftUI Glass Modifiers:**
  * Use `.glassEffect(_:in:)` (defaulting to `.regular` in `Capsule` or `RoundedRectangle` shapes) for floating controls, custom toolbars, HUDs, and interactive chrome.
  * Use `.interactive()` on custom tappable/clickable glass surfaces (`.glassEffect(.regular.tint(.accentColor).interactive())`) to provide native pointer hover, press scale, and specular shimmer responses.
  * Use `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)` for standard and primary glass actions.
* **Container Batching & Morphing:**
  * Wrap adjacent or grouped glass controls inside `GlassEffectContainer(spacing:)` to optimize Metal rendering passes and enable fluid shape blending.
  * Coordinate appearance/disappearance transitions using `@Namespace`, `.glassEffectID(_:in:)`, and `.glassEffectTransition(.matchedGeometry)` (or `.materialize` for distant elements) inside `withAnimation`.
* **Modifier Ordering Rule:**
  * Always apply `.glassEffect(_:in:)` **after** layout, padding, and frame modifiers (`.padding().frame(...).glassEffect()`) so the glass bounds capture the full padded control geometry.

### 3.2 The Strict Two-Layer Rule (No Overuse)
* **Layer 1 — Content Layer (Sacred & Opaque):** Lists, tables, text editors, code views, canvases, and scrollable media **must never** use Liquid Glass. Keep content crisp, high-contrast, and legible.
* **Layer 2 — Functional Chrome Layer (Floating Glass):** Reserve Liquid Glass exclusively for navigation bars, floating toolbars, sidebars/inspectors, popovers, and transient HUD overlays that float *above* scrolling content.
* **Prohibited Patterns:**
  * **Never** stack glass elements on top of other glass elements.
  * **Never** apply glass over a solid, flat single-color background where refraction has nothing to bend.
  * **Never** add custom opaque backgrounds behind native `NavigationSplitView` sidebars, toolbars, or sheets that override system glass and scroll-edge effects.

### 3.3 Native macOS Desktop Ergonomics
* **Windowing & Navigation:** Use `NavigationSplitView` for multi-column layouts, `Settings` scene for Preferences (`⌘,`), and `Window` / `WindowGroup` with proper restoration identifiers.
* **Menu Bar & Shortcuts:** Expose every major action in the macOS top Menu Bar via SwiftUI `Commands` with standard keyboard shortcuts (`⌘N`, `⌘F`, `⌘S`, `⌘,`, `⌫`) and contextual `.contextMenu` actions on list/table rows.
* **Accessibility & Legibility:** Test all custom glass surfaces under macOS **Reduce Transparency**, **Increase Contrast**, and varying wallpaper/glass clarity settings. Ensure foreground text and SF Symbols maintain WCAG AA contrast ratios regardless of underlying content.

---

## 4. macOS System Guardrails & Pitfall Prevention

`@macOS-Platform-Engineer` and `@macOS-Guardrail-Inspector` must verify these guardrails before approving any build:

1. **Swift 6 Strict Concurrency & Thread Safety:**
   * Enable strict concurrency checking (`SWIFT_STRICT_CONCURRENCY = complete`).
   * Isolate all UI state and `@Observable` view models to `@MainActor`.
   * Execute all backend computations, file I/O, network requests, and IPC calls inside background `actor` contexts or detached tasks. Zero synchronous blocking calls on the main thread.
2. **App Sandbox, Entitlements & File Access:**
   * Enable App Sandbox (`com.apple.security.app-sandbox = true`) and Hardened Runtime unless an explicit system capability forbids it (document any exception).
   * Never hardcode `/Users/...` paths. Use `FileManager.default.urls(for:in:)` (e.g., `.applicationSupportDirectory`, `.cachesDirectory`).
   * For user-selected files/folders outside the container (`NSOpenPanel` / `.fileImporter`), persist access across launches using **Security-Scoped Bookmarks** (`bookmarkData(options: .withSecurityScope)` and `startAccessingSecurityScopedResource()`).
3. **TCC (Transparency, Consent, and Control) Compliance:**
   * Declare all required `Info.plist` usage descriptions (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSDesktopFolderUsageDescription`, etc.) and check authorization status gracefully before triggering hardware/folder prompts.
4. **Process, Memory & Lifecycle Hygiene:**
   * If the core backend runs as an embedded runtime, local server, or child process (`Process`), tie its lifecycle strictly to the app: terminate child processes cleanly in `applicationWillTerminate` and handle unexpected subprocess crashes with automatic recovery.
   * Audit closures and delegates for retain cycles (`[weak self]`). Profile memory and GPU glass overdraw using Instruments.

---

## 5. Step-by-Step Execution Protocol

`@Orchestrator` must execute the rewrite in **five sequential phases**. Do not skip phases or parallelize conflicting writes.

### Phase 0: Workspace Initialization
1. Create a clean greenfield macOS Xcode project/package structure alongside (not overwriting) the legacy source tree.
2. Configure Swift 6 language mode, macOS 26+ deployment target, Swift Testing framework, and `/docs/rewrite/` directory.

### Phase 1: Complete Legacy Dissection (Team A)
Team A analyzes the legacy codebase and produces four foundational artifacts in `/docs/rewrite/`:
1. `01_LEGACY_TOPOLOGY.md` (`@Legacy-Cartographer`): Full inventory of legacy modules, assets, schemas, and dependencies.
2. `02_BACKEND_CONTRACT.md` (`@Backend-Extractor`): Exact specification of the core backend engine to preserve, its inputs/outputs, state persistence, and required bridge interface.
3. `03_FEATURE_DECONSTRUCTION.md` (`@UI-Deconstructor`): Every feature broken into atomic user stories, state transitions, edge cases, and keyboard/menu interactions—reimagined for native macOS Liquid Glass.
4. `04_SYSTEM_GUARDRAILS_AUDIT.md` (`@System-Auditor`): Required entitlements, sandbox exceptions, Keychain keys, and OS integrations.

* **Phase 1 Gate:** `@Orchestrator` reviews all four documents to ensure 100% functional parity with the legacy app's capabilities before writing production code.

### Phase 2: Core Architecture & Backend Bridge (Team B + Team C)
1. `@System-Architect` authors `05_GREENFIELD_ARCHITECTURE.md` defining the Swift module boundaries, `@Observable` state hierarchy, and typed Swift protocol/actor wrapping the core backend.
2. `@Backend-Integrator` implements the core backend bridge and data models.
3. `@macOS-Platform-Engineer` sets up the app shell (`App`, `WindowGroup`, `Settings`, `Commands`, Entitlements, Sandbox, and lifecycle manager).
4. `@Test-Engineer` writes and runs integration tests proving the backend bridge operates reliably with zero main-thread blocking.

* **Phase 2 Gate:** App compiles cleanly with zero warnings, core backend tests pass 100%, and `@macOS-Guardrail-Inspector` signs off on sandbox/entitlements.

### Phase 3: Iterative Feature-by-Feature Build, Test & Review Loop
`@Orchestrator` orders all features `[F-01, F-02, ..., F-NN]` in `FEATURE_MATRIX.md` from foundational to advanced. **Execute this exact 5-step micro-loop for ONE feature at a time:**

1. **Feature Mini-Spec (`@System-Architect`):** Define the exact state properties, backend calls, SwiftUI view hierarchy, and Liquid Glass placement for `F-XX`.
2. **Backend & State Wiring (`@Backend-Integrator`):** Expose required backend endpoints/streams to the feature's `@MainActor` `@Observable` model.
3. **Native SwiftUI + Liquid Glass UI (`@LiquidGlass-UI-Engineer`):** Build the feature's views, animations, keyboard shortcuts, and accessibility labels.
4. **Automated Testing (`@Test-Engineer`):** Write and execute unit tests for view-model state transitions and `XCUITest` UI verification for `F-XX`.
5. **Dual Gatekeeper Review (`@HIG-LiquidGlass-Critic` & `@macOS-Guardrail-Inspector`):**
   * Verify Liquid Glass is applied *only* to floating controls/navigation, wrapped in `GlassEffectContainer` where grouped, and legible under Reduce Transparency / Increase Contrast.
   * Verify zero main-thread stalls, zero retain cycles, proper error states, and clean sandbox behavior.
   * **If any defect is found:** Return to Step 2/3 immediately. **Only when both critics approve** does `@Orchestrator` mark `F-XX` as `DONE` and advance to `F-(XX+1)`.

### Phase 4: Final Integration, Profiling & Parity Audit
1. Full end-to-end regression suite across all features (`F-01` through `F-NN`).
2. Performance audit: Check frame pacing during Liquid Glass morphing animations, memory footprint under load, and clean app termination.
3. Final parity sign-off against `03_FEATURE_DECONSTRUCTION.md`.

---

## 6. Orchestrator Control Artifacts (Maintain in `/docs/rewrite/FEATURE_MATRIX.md`)

`@Orchestrator` must maintain and update this table after every single feature loop:

```markdown
# Feature Rewrite Progress Matrix

| ID | Feature Name | Dependencies | Backend Bridge | SwiftUI + Liquid Glass | Automated Tests | HIG Critic Sign-Off | Guardrail Sign-Off | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| F-00 | App Shell, NavigationSplitView & Backend Bridge | None | [ ] | [ ] | [ ] | [ ] | [ ] | PENDING |
| F-01 | [Populate from Dissection] | F-00 | [ ] | [ ] | [ ] | [ ] | [ ] | PENDING |
| F-02 | [Populate from Dissection] | F-01 | [ ] | [ ] | [ ] | [ ] | [ ] | PENDING |
```

### Gatekeeper Sign-Off Checklist (Required Per Feature)
Before marking any feature `DONE`, `@Orchestrator` must verify:
- [ ] **Backend Isolation:** Core backend logic remains decoupled from SwiftUI views; all calls are async and properly typed.
- [ ] **Liquid Glass Discipline:** `.glassEffect()` is used strictly on floating controls/chrome, never on scrollable content layers or stacked glass-on-glass.
- [ ] **Modifier Order:** `.glassEffect()` is applied *after* `.padding()` and `.frame()`.
- [ ] **Accessibility:** Verified legible with Reduce Transparency and Increase Contrast enabled; all controls have VoiceOver labels and keyboard shortcuts.
- [ ] **macOS Guardrails:** Zero Swift 6 concurrency warnings, zero synchronous main-thread I/O, proper sandbox/file-bookmark handling, and clean error states.
- [ ] **Tests Passing:** Unit tests and UI tests for this feature pass 100%.

---

## 7. Kickoff Instruction for the Orchestrator

**Begin immediately with Phase 0 and Phase 1:**
1. Scan the current workspace to identify the legacy codebase structure and core backend technology.
2. Dispatch `@Legacy-Cartographer`, `@Backend-Extractor`, `@UI-Deconstructor`, and `@System-Auditor` to generate the four Phase 1 dissection documents in `/docs/rewrite/`.
3. Present the completed `FEATURE_MATRIX.md` and ask for confirmation (or proceed automatically if autonomous mode is enabled) before entering Phase 2.