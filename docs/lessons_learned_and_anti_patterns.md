# WhisperDoc Lessons Learned & Architectural Anti-Patterns

This document serves as the project's living ledger of architectural corrections, operational lessons learned, and forbidden anti-patterns. In accordance with project engineering rules, this document must be consulted at the start of every engineering session to ensure past design failures and regressions are never reintroduced.

---

## 1. Process Isolation vs. In-Process Heavy C/CUDA Libraries

- **The Mistake / Issue**: Embedding NVIDIA NeMo (`nemo_toolkit[asr]`) and its extensive C++/CUDA dependency graph directly into the Python `FastAPI` / `uvicorn` asyncio event loop.
- **The Root Cause**: A severe, non-deterministic CPython memory corruption bug occurred where a native C/CUDA extension mutated CPython's interned `b" "` (ASCII space `0x20`) singleton to `0x00` in memory. This corrupted `h11` HTTP header parsing, caused socket upgrade failures, and pulled over 12 GB of bloated dependencies into the backend container.
- **The Core Corrective Rule**: Never host complex, native C++/CUDA inference engines in-process alongside web services. Isolate heavy ML workloads behind a standalone sidecar process (e.g., native C++ `parakeet.cpp` container) communicating over lightweight HTTP/IPC.

---

## 2. Zero-Shim & Anti-Monkey-Patching Policy

- **The Mistake / Issue**: Introducing monkey-patches (`_fixed_ws_upgrade` and `_SAFE_SPACE` byte patches) inside `backend/api_server.py` to paper over `h11` protocol failures caused by memory corruption.
- **The Root Cause**: Attempting to fix downstream symptoms of underlying memory corruption rather than resolving the architectural root cause.
- **The Core Corrective Rule**: Zero silent patches. Never introduce runtime shims, monkey-patches, or compatibility layers to mask deeper structural bugs. If a foundational dependency or design pattern fails, isolate or refactor the architecture at its root.

---

## 3. Cross-Environment Windows/WSL Synchronization

- **The Mistake / Issue**: Manually copying files or using ad-hoc file transfers between Windows workspace filesystems and WSL Linux environments.
- **The Root Cause**: File permission discrepancies (e.g., execution bit loss on shell scripts), line ending mutations (CRLF vs. LF), and orphaned mirror files leading to state desynchronization and dirty git working trees.
- **The Core Corrective Rule**: Never perform manual file copies between Windows and WSL. Exclusively use `wdsync send` / `wdsync receive` or formal Git operations (`git fetch` / `git reset --hard`) to maintain synchronized environments.

---

## 4. Multi-Platform Line Ending Drift in Automation Tooling

- **The Mistake / Issue**: Regex-based text replacements in `scripts/bump_version.py` failing on Windows files formatted with CRLF (`\r\n`), and Python file writers converting LF to CRLF unexpectedly.
- **The Root Cause**: Using string `$`, `\n`, or default `open(..., "w")` without preserving exact newline semantics, causing silent regex mismatch or git diff churn.
- **The Core Corrective Rule**: All repository-level automation scripts touching files must use `newline=""` when reading and writing text (`_read_text_preserving_newlines()` / `_write_text_preserving_newlines()`), and multiline regexes must match non-newline characters explicitly (e.g., `[^\r\n]*`) instead of relying on `$` or `.*`.

---

## 5. Three-Tier Narrative Commit Standard

- **The Mistake / Issue**: Authoring generic, single-line, or vague commit messages lacking context, motivation, or detailed impact.
- **The Root Cause**: Omitting structured documentation standards during rapid development.
- **The Core Corrective Rule**: Every git commit must adhere to the three-tier narrative commit format:
  1. **Executive Summary Header**: `<type>(<scope>): <summary>` using 2 to 4 complete sentences stating both what changed and why/result.
  2. **Technical Narrative**: 1 to 2 paragraphs of prose (each at least 3 complete sentences) detailing architectural rationale, trade-offs, and system impacts.
  3. **Categorized Component Breakdown**: Explicit file paths grouped under domain headers (`**Backend**`, `**Frontend**`, `**Tooling**`, `**Infrastructure**`, `**Docs**`, `**Tests**`).

---

## 6. Windows Desktop Release Compilation Flags

- **The Mistake / Issue**: Compiling Flutter Windows release binaries without debug symbol separation or runtime configuration definitions.
- **The Root Cause**: Standard `flutter build windows --release` produces monolithic executables with unmapped crash traces and missing OIDC enclave credentials.
- **The Core Corrective Rule**: Windows release builds must always specify obfuscation, split debug symbol output, and explicit environment injection:
  ```powershell
  flutter build windows --release --build-name=<version> --build-number=<num> --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env.json
  ```

---

## 7. Decoupled Architecture & Context-Blind Services

- **The Mistake / Issue**: Embedding UI lifecycle observers (`WidgetsBindingObserver`) or Flutter widget dependencies inside low-level services like `AudioService`.
- **The Root Cause**: Conflating UI state orchestration with hardware interface management, creating cyclic dependencies and making services difficult to unit-test.
- **The Core Corrective Rule**: Adhere strictly to the five horizontal layers (Infrastructure -> Services -> Logic -> Controllers -> UI). Services must remain 100% context-blind. UI lifecycle and presentation logic belong strictly in UI widgets and Controllers.

---

## 8. Provider Tree vs. DI Service Locator Registration

- **The Mistake / Issue**: Registering a domain service (`GroqTransformService`) exclusively in `ServiceLocator` (GetIt) while omitting it from the root `MultiProvider` widget tree in `lib/main.dart`, leading to runtime `ProviderNotFoundException` during UI render.
- **The Root Cause**: Conflating DI service location with Flutter widget tree state propagation. GetIt provides programmatic access, but `context.watch<T>()` / `Provider.of<T>(context)` requires an explicit `ChangeNotifierProvider` ancestor in the widget hierarchy.
- **The Core Corrective Rule**: Whenever a service is exposed to the UI via `context.watch<T>()`, it must be registered in both `ServiceLocator.setup()` and `MultiProvider.providers` in `lib/main.dart`. Moreover, presentation widgets should directly observe the narrowest true source of truth (e.g. `SettingsService` for persisted credentials) rather than unnecessarily coupling to downstream domain services solely for mirrored getters.

---

## 9. Groq Chat Completions Reasoning Parameter Mutex

- **The Mistake / Issue**: Passing both `include_reasoning: false` and `reasoning_format: "hidden"` simultaneously in Groq `/chat/completions` request bodies.
- **The Root Cause**: The Groq API treats `include_reasoning` and `reasoning_format` as mutually exclusive controls; providing both triggers an HTTP 400 Bad Request (`cannot specify both include_reasoning and reasoning_format`).
- **The Core Corrective Rule**: Only pass `include_reasoning: false` when disabling chain-of-thought tokens on Groq chat completion endpoints. Never combine it with `reasoning_format`.

---

## 10. Technical Dictation Prompts: Zero-Omission vs. Aggressive Summarization

- **The Mistake / Issue**: Instructing an LLM to generate "concise markdown bullet points" or "optimize" causes it to summarize, truncate, and drop critical technical details (such as environment variables, edge cases, error codes, and parameters) from stream-of-consciousness dictation.
- **The Root Cause**: LLMs default to brevity and condensation when instructed to "clean" or "optimize" technical bullet points, discarding specific sub-clauses that appear redundant to the model.
- **The Core Corrective Rule**: Technical prompts must mandate an explicit **Zero-Omission & Exhaustive Detail** constraint. They must instruct the model that 100% of user-provided details (parameters, flags, constraints, edge cases, numbers, and identifiers) must be preserved in precise technical language and wrapped in inline backticks (`symbol`), formatted for direct consumption by engineers and AI models without information loss. Additionally, length guard filters must accommodate technical specification expansion ratios up to $4.5\times$ to avoid rejecting valid structured markdown.

---

## 11. Flutter Tooltip Empty String Toggle & OverlayPortal Assertion Failure

- **The Mistake / Issue**: Dynamically passing an empty string (`message: _isMenuOpen ? '' : tooltip`) to a Flutter `Tooltip` to hide or suppress it while a custom interactive overlay is open, triggering `'package:flutter/src/widgets/overlay.dart': Failed assertion: line 1681 pos 14: '_zOrderIndex != null': is not true`.
- **The Root Cause**: Flutter's `RawTooltip` uses `OverlayPortal` internally. When `message` dynamically transitions to `''` while a tooltip fade animation is active, `RawTooltipState.didUpdateWidget` immediately hides the internal portal and clears `_zOrderIndex`. When the fade animation controller subsequently finishes ticking to `0.000` (`AnimationStatus.dismissed`), `_handleStatusChanged` calls `_overlayController.hide()` a second time on the already detached portal, crashing with `assert(_zOrderIndex != null)`.
- **The Core Corrective Rule**: Never dynamically toggle `Tooltip.message` between an empty string (`''`) and a valid string to hide a tooltip. Instead, maintain constant, non-empty tooltip strings and resolve spatial conflicts geometrically (e.g. `preferBelow: true` vs. top-anchored menus) with appropriate `waitDuration` (e.g. `500ms`), or conditionally omit the `Tooltip` widget entirely using a builder.

---

## 12. Flutter Tooltip (OverlayPortal) Inside CompositedTransformFollower Paint Transform Assertion

- **The Mistake / Issue**: Nesting Flutter `Tooltip` widgets (such as wrapping action icons) inside an overlay rendered via `CompositedTransformFollower`, triggering `'The paint transform cannot be reliably computed because of RenderFollowerLayer(s)'` during `performLayout()`.
- **The Root Cause**: Flutter's `Tooltip` uses `OverlayPortal` (`_RenderLayoutBuilder`) to position its tooltip overlay during the layout phase. However, `CompositedTransformFollower` (`RenderFollowerLayer`) does not establish its paint transform matrix until the subsequent paint/compositing phase. Querying the follower's paint transform during layout throws an assertion error.
- **The Core Corrective Rule**: Never place `Tooltip` widgets inside a `CompositedTransformFollower` overlay subtree. Sub-items inside popup menus should render plain icons or text without nested tooltips, or rely on root-level layout mechanisms.

---

## 13. Production Code Quality Enforcement vs. Test Double Heuristics

- **The Mistake / Issue**: Conflating test fixture conventions (such as `late` test doubles in `setUp()`, mock class definitions co-located in test files, or repetitive async test pump invocations) with production architecture defects, leading to churn in test suites without improving production system integrity.
- **The Root Cause**: General static analysis rules (such as `prefer-moving-to-variable` or `avoid-late-keyword`) enforce strict DRY and runtime null-safety patterns vital for long-lived services in `lib/`. However, in test suites, tests must remain atomic, explicit, and self-contained (Arrange-Act-Assert). Forcing repeated assertions or async pump calls into shared helper variables obscures test failure traces and couples independent test cases.
- **The Core Corrective Rule**: Enforce 100% zero-defect DCM and analyzer cleanliness on all production code in `lib/` (zero warnings, zero style issues, modular file structure, and zero magic numbers). For test suites, preserve standard unit test idioms (isolated assertions, explicit setup lifecycle, and dedicated mocks) while maintaining a mandatory 100% test pass rate with zero `flutter analyze` compiler issues.

---

## 14. Python TextIO Reconfigure Typing & Script Credential Isolation

- **The Mistake / Issue**: Calling `sys.stdout.reconfigure()` causing `Cannot access attribute "reconfigure" for class "TextIO"` in Pylance/Pyright, and embedding fallback API keys, user names, or machine-specific paths in developer tooling scripts.
- **The Root Cause**: Typeshed types `sys.stdout` as abstract `TextIO` (which lacks `.reconfigure()` unlike runtime `io.TextIOWrapper`), and developer scratch scripts defaulting to convenience tokens rather than clean environment variables and standard CLI arguments.
- **The Core Corrective Rule**: Always narrow stream wrappers with `if isinstance(sys.stdout, io.TextIOWrapper):` before calling `.reconfigure(encoding="utf-8", errors="replace")`. In developer tools and benchmark utilities, never hardcode fallback API tokens, personal identities, or machine-specific file paths; require `os.environ` or standard `argparse` flags (`--groq-key`) with structured validation and `--help` support.
---

## 15. Error Message String Matching vs. Domain State Routing

- **The Mistake / Issue**: Dropping error toasts when the lowercase error message contained the substring `"ban"`, causing transform errors for user-created profiles named "Banking" or "Urban Memo" to be silently dropped.
- **The Root Cause**: Routing application behavior by inspecting error message text rather than checking the domain state directly (e.g. `WebSocketService.status == ConnectionStatus.banned`). When user-controlled text enters the message stream, substring matching causes false-positive suppression.
- **The Core Corrective Rule**: Never use string containment checks on user-facing error messages to drive application routing or state decisions. Always query domain state machines (`status == ConnectionStatus.banned`) or typed exception classes directly.

---

## 16. Overlay Element Lifecycle & Dialog Context Scope

- **The Mistake / Issue**: Calling `_closeMenu()` to remove an `OverlayEntry` and then immediately calling `showDialog` using the overlay builder's `BuildContext`.
- **The Root Cause**: The overlay builder's `BuildContext` corresponds to an `Element` in the overlay subtree that gets unmounted as soon as the entry is removed. Passing that context to asynchronous dialogs works only until frame garbage collection or strict lifecycle assertions fire.
- **The Core Corrective Rule**: When dismissing an overlay before launching a dialog or bottom sheet, always pass the persistent widget `State`'s own `this.context` to `showDialog`, reserving the overlay context strictly for scoped inherited lookups within the overlay itself.

---

## 17. Speculative Surface, Orphaned State, and Deserializer Integrity

- **The Mistake / Issue**: Leaving `GroqTransformService` as an unused `ChangeNotifier` registered in `MultiProvider`, retaining unreachable slot capacity branches when slot count is bounded by a static list, and fabricating default custom profiles from malformed JSON during startup.
- **The Root Cause**: Speculative scaffolding carried over during feature development without pruning unused surface, and permissive deserializers attempting to "fix" corrupt data rather than cleanly ignoring it.
---

## 18. Cross-Transport Credential Coupling vs. Strict Mode Gating

- **The Mistake / Issue**: Allowing client-edge LLM transformation to run across self-hosted backend connections when the required third-party cloud credential (Groq API key) was only exposed in the UI during cloud mode, causing backend users to see disabled profile tiles with no accessible way to configure keys.
- **The Root Cause**: Coupling an execution feature (LLM rewriting) to an external cloud vendor without strictly gating it behind the connection mode where that vendor's credentials exist, and fragmenting the mode invariant across multiple consumers rather than encapsulating state enforcement inside the settings owner.
- **The Core Corrective Rule**: When a feature requires third-party cloud credentials that are not part of the self-hosted transport contract, completely disable and gray out the control in self-hosted mode with an explicit onboarding tooltip (`'Available in Groq Cloud mode'`). Encapsulate the invariant strictly within `SettingsService` (resolving non-raw profiles to `DictationProfile.raw` whenever `!isGroqMode`) so downstream controllers remain context-blind to transport modes.
