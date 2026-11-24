# WhisperDoc Technical Changelog

## [3.3.0] - 2026-11-23
### OpenRouter Source
- **Three Sources**: `TranscriptionSource` (server, Groq, OpenRouter) replaces the Groq/server mode flag. A segmented `SourceSelector` heads Account and replaces **Switch service**; the saved choice carries over.
- **Live Model List**: `OpenRouterCatalog` reads OpenRouter's speech models and their zero-data-retention endpoints, caches the last list, and loads each model's 30-minute latency when the picker opens. WER comes from a fixed Artificial Analysis snapshot (`speech_model_accuracy.dart`, 23 Nov 2026).
- **Zero Data Retention**: On by default, and then every speech and chat request carries `provider.zdr`; turning it off asks first.
- **No Silent Switch**: `ModelSelectionProblem` (not chosen, retired, retains data) blocks a dictation before the microphone opens, and the home screen offers **Choose**.
- **Rewrite Model**: Output styles run on OpenRouter with `qwen/qwen3.8-27b` (reasoning off), routed by `sort: latency` with `preferred_min_throughput` p50 200. **Rewrite model** takes any model id and checks it with a one-word rewrite before saving.

### Cloud Engine Layer
- **One Path for Both Clouds**: `SpeechEngine`/`ChatEngine` with Groq and OpenRouter implementations behind `CloudTranscriptionService` and `TransformService`, replacing the five `groq_*` services. Buffering, the 25 MB cap, sanitizing and `CloudError` are shared.
- **Warm Upload**: Starting a dictation pre-opens the HTTPS connection; one keep-alive client serves every cloud call, and only a stale kept-alive connection is retried.
- **Off the UI Thread**: OpenRouter clips above 1 MiB are base64-, JSON- and UTF-8-encoded in an isolate, and `WavEncoder` writes the captured chunks once.

### Output Styles
- **Tech Prompt**: Keeps the speaker's words, writes code terms exactly in backticks, spells frameworks and protocols as their makers do, and lists only counted steps. Median 487 → 262 ms on Groq, length 2.59× → 0.90× the input, cut-off rewrites 3/8 → 0/8.

### Accessibility
- **Tooltips in the Windows Tree**: Each `SourceSegment` is its own semantics container holding its tooltip, and declares its tap. Merged tooltips had left bubbles without a parent, so Windows rejected every later update ("will not be in the tree"; flutter/flutter#197194).
- **Engine-Faithful Tests**: `AccessibilityTreeBinding` applies each semantics update as the Windows bridge does and records rejections across Account, home and the model picker.

### Server Setup
- **`setup.sh`**: Generates the API key, picks GPU or CPU (`docker-compose.cpu.yml` resets the GPU reservation), builds, starts and waits for `/health`. Flags `--engine`, `--cpu`/`--gpu`, `--dev`, `--yes`; the backend workflow runs it on every change.
- **Client Version Gate**: `.env.template` sets `MIN_CLIENT_VERSION=3.0.0` and `SEC_CLIENT_VERSION=3.1.0`.

### Tooling
- **Release Logs**: `LoggingService` drops debug lines outside debug builds.
- **Benchmarks**: `scripts/benchmark_prompts.py` reads the shipped prompts, routing and model from the Dart source; results live in `docs/benchmarks/`.
- **DCM**: `missing-test-assertion` counts only `expect()`; its `verify` option and `avoid-missing-image-alt` need a paid plan, so they are removed.
- **Terminal Client**: Message listeners are plain callables, no longer awaited.
- **Tests**: 709 Flutter, 268 terminal client and 295 backend tests.

## [3.2.0] - 2026-11-22
### Security Hardening
- **Sign-In Scope**: The OIDC token is sent only to the built-in server or one the user approved with **Trust server**, compared by normalized `scheme://host:port`. Trusted servers are forgotten on sign-out or an account switch. Developer keys are unaffected.
- **Transcript Gate**: A `transcription` frame is accepted only after end-of-stream, once, within `serverTranscriptTimeout` (2 min), and only as a string. It is sanitized and pasted on one line, so a server cannot paste text unasked or inject line breaks.
- **Line Breaks per Style**: Raw, Clean and Casual paste on one line; Pro, Tech and custom styles (`keepsLineBreaks`) keep paragraphs.
- **Sanitizer Coverage**: `TextSanitizer` strips every CSI and OSC sequence (BEL or ST terminated) and bidi overrides and isolates, and keeps ZWJ/ZWNJ.
- **Server Text Is Inert**: Server error messages are sanitized, one line, at most 160 code points. `AuthErrorDialog` and the home screen's error-text matching are removed.
- **Backend Log Privacy**: `transcribe_and_send` logs the transcript's length, never its words, in either mode.
- **Transport and Logs**: A `ws://` hostname must resolve only to private or loopback addresses. Update links are limited to this repo's HTTPS GitHub pages. Client logs drop transcript text, emails and raw provider bodies, and clearing history vacuums the database.

### Reliability
- **Connection State**: "Signed in" means holding credentials, and `ServerProblem` (unreachable, insecure, untrusted) drives `[ server offline ]`, `[ address not allowed ]` and `[ new server ]` with their fixes.
- **WebSocket Lifecycle**: `connect()` resolves on `authenticated` and is single-flight. Dropped and superseded sockets are closed, callbacks are bound to their own socket, a handshake timeout disconnects, and a queued end-of-stream follows the buffered audio. `HandshakeStateMachine` allows `authenticating → locked`.
- **Backoff**: `ReconnectionManager` retries at 2 s doubling to 60 s until a connection succeeds, and never after sign-out, in Groq mode, or after a ban.
- **Configuration Snapshots**: `ConfigurationManager` records every setting on every change, Groq mode included, and the config-change reconnect is skipped in Groq mode or without credentials.
- **Dictation Losses Reported**: A connection lost mid-dictation stops recording with a reason. A recorder that stops by itself still transcribes, a second press while starting stops once started, and paste runs before the history save.
- **Clean Exit**: Closing the window wakes the hotkey thread (`WM_QUIT`) and the runner destroys the window after the message loop, so the process ends.

### Captions Interface
- **Home**: `HomeStatusMapper` turns service signals into one cue, one fix and an account badge. Includes the pixel meter (`MeterHistory`, `LevelNormalizer`), captions for the last transcript, and `CrispText`/`PixelSnap` whole-pixel text.
- **Contour Background**: `topography.frag` with `TopographyMotion` (cursor peak, click wave, relief rise at any frame rate), flattened while listening and switchable off with **Moving background**.
- **Panels**: `AppPanel`, `PanelRow`, `ChoicePanel` and `FieldPanel` rebuild Account, Settings, History and Logs. Each change saves on its own; `FieldPanel` saves once and reports failures.
- **Native Window**: Borderless square popup without shadow, sized to a 420×600 client area by the runner before Flutter starts. Buttons press 2 px and climb back (`PressNudge`).
- **Bundled Assets**: Lexend, JetBrains Mono and a subsetted Lucide font replace `google_fonts` and `lucide_icons_flutter`.

### Tooling
- **DCM Clean**: All DCM findings fixed or suppressed with a stated reason; Bloc-only rules dropped and Mocktail `verify` counted as an assertion.
- **Tests**: 372 Flutter tests (from 239). The WebSocket suite injects a `ChannelOpener` and no longer opens real connections.

## [3.1.0] - 2026-11-19
### Security Hardening
- **Dependabot Remediation**: Patched all 44 open advisories (39 backend, 5 terminal client), including 15 PyJWT advisories, with lock refreshes plus GHSA-annotated `constraint-dependencies` floors so a future re-resolve cannot regress. An OSV scan of `flutter_client/pubspec.lock` found nothing.
- **X-Forwarded-For Spoofing Closed**: Replaced uvicorn `--forwarded-allow-ips='*'` with `FORWARDED_ALLOW_IPS=172.16.0.0/12,192.168.0.0/16`, so IP bans and flood tracking key on the real client address.
- **Pre-Parse Upload Guard**: `POST /transcribe` checks the bearer token, `Content-Length` presence, and a 25 MB cap in HTTP middleware (401 / 411 / 413) before the multipart body is read. ffmpeg runs with `-nostdin`, `FFMPEG_TIMEOUT_SECONDS`, and a duration cap.
- **HTTP Output Parity**: `/transcribe` shares the per-user semaphore and the WebSocket sanitizer (`sanitized_segments`), logs only character counts, and masks internal errors behind a reference id.
- **Attack Surface Removal**: Removed the `POST /log` endpoint and the unused `verify_api_key` dependency.
- **OIDC Key Rotation**: An unknown `kid` triggers one JWKS refetch, rate-limited to once per 60 s. Discovery/JWKS caches are guarded by an `RLock`, and validation runs via `asyncio.to_thread` so the event loop never blocks on the identity provider.
- **Unicode-Preserving Sanitizers**: Backend, Flutter, and terminal sanitizers replace the printable-ASCII whitelist with an ANSI + C0/C1 control-character blacklist. Backend sanitization is gated by `SANITIZE_TRANSCRIPTS`.
- **Safe Auto-Paste**: The Flutter client checks `SetClipboardData` and pastes only after a successful copy.

### Reliability
- **Flutter Startup**: Hidden-window configuration, immediate `runApp()`, and a `BootScreen` first frame remove the white flash and the rare frozen white window. Session restore is network-free, OIDC requests time out after 10 s, sign-out happens only on `OidcRejectedException` (400/401), and PBKDF2 runs on a worker isolate.
- **Microphone Hot-Plug**: The native `IMMNotificationClient` (`audio_device_watcher.cpp`) pushes coalesced Core Audio events over `whisperdoc/audio_devices`. Enumeration failures map to `unknown` instead of a sticky `noDevice`, and unavailable selections fall back to the default device.
- **Recording Races**: Start/stop re-entry guards stop duplicate capture streams and double upload-and-paste.
- **Structured Error Routing**: The Flutter client classifies session-ending errors by `error_code`, so the NO_AUDIO hint now fires and operational errors mentioning "Auth" no longer drop the session.
- **Backend Lifecycles**: `ConnectionManager.start()`/`stop()` are owned by the lifespan, concurrent handshakes share one warmup task, the Whisper idle monitor runs on a daemon thread, and expired IP bans are pruned periodically. Startup failures re-raise so the restart policy recovers, and `/health` no longer fails on idle unload.
- **Terminal Client Lifecycle**: A single idle watchdog ignores keepalive traffic, backoff resets only after authentication, there is no auto-reconnect after idle eviction or `AUTH_FAILED`, teardown no longer cancels itself, connects are serialized, and utterances finish in order (flush, then end-of-stream) through per-session capture queues. The version now comes from package metadata.

### Performance & Cleanup
- **Torch Removed**: Dropped CPU-only PyTorch and orjson from the backend. The Whisper image shrank from 5.23 GB to 4.3 GB.
- **Narrow UI Rebuilds**: `context.select`/`Selector` scoping, one-time history decryption, shared styles, and a fix for the pulse-animation smear.
- **Dead Code Purge**: Removed client-to-server log forwarding, unused widgets, getters, and constants, and the `whisper_client.py` shim. History is pruned to 100 entries.

### Infrastructure & Tooling
- **Compose Service Rename**: `whisper-backend` became `backend`, and `COMPOSE_PROFILES` is derived from `ASR_ENGINE`. Docker healthcheck runs every 30 s with a 180 s start period.
- **Lint Determinism**: ruff `known-first-party` makes import grouping independent of the working directory.
- **CI/CD**: GitHub Actions run every pre-commit hook; backend pyright and pytest plus a Docker end-to-end test of the Whisper image (CPU, `tiny.en`, production isolation flags, live API and WebSocket tests); terminal client and Flutter checks on Windows; and a tag-triggered release that builds the obfuscated installer into a draft GitHub Release. Actions are pinned to commit SHAs and kept current by Dependabot.
- **Version Drift Gate**: `bump_version.py --check` fails when any managed file disagrees with the backend version. It runs in pre-commit and before every release build.

### Dependency Refresh
- **Python**: FastAPI 0.165, uvicorn 0.54, websockets 17, cachetools 8, loguru 0.8, ctranslate2 4.9, cuDNN 9.28. uv 0.13.9 and static-ffmpeg 9.0.2 in the images and CI. PyAV capped below 19 (faster-whisper 1.2.1 passes the `metadata_errors` argument PyAV 19 removed).
- **Flutter 3.50.1**:
  - win32 6: typed handles and `Win32Result`; a raw `GetMessageW` binding so its -1 error ends the hotkey loop.
  - record 7 with `audioRouteChange: follow`.
  - window_manager 0.7's native `Window` API.
  - flutter_web_auth_2 6, google_fonts 9, drift 2.35, and `material_ui`.
  - Dropped `sqlite3_flutter_libs` and the discontinued `screen_retriever` packages.
- **Settings Dropdowns**: shared compact `GlassDropdown` in the theme font for audio input and Groq model.
- **E2E XFF Probe**: CI asserts that forged `X-Forwarded-For` hops resolve to the trusted rightmost entry.

### Verification & Quality Gates
- **Backend**: 137 passed, 7 skipped; pyright 0 errors; ruff clean. New `test_backend_hardening.py` and `test_sanitizer.py`.
- **Flutter**: `flutter analyze` clean; 239 tests passing, including new suites for the device monitor, session restore, and error routing.
- **Terminal Client**: 174 passed; rewritten transport lifecycle, recording-order, and audio-queue suites.

---

## [3.0.0] - 2026-09-05
### Client-Edge Dictation Profiles & LLM Transformation Subsystem
- **Zero-Backend Transformation Engine**: Added `GroqTransformService` and `GroqChatClient` executing client-side post-processing rewrites via Groq's high-speed `qwen/qwen3.8-27b` (~260ms latency, zero reasoning tokens).
- **Polymorphic Profile Architecture**: Introduced `DictationProfileSpec` interface implemented by both built-in `DictationProfile` enum (**Raw**, **Clean**, **Pro**, **Casual**, **Tech**) and dynamic `CustomProfile` models.
- **Custom Profile Management & In-Menu Editor**: Implemented up to 3 user-defined custom profiles (`custom1..3`) with sequential default naming (`Custom 1..3`), user renaming, 2,000 character prompt cap, automatic safety preamble composition, and an in-menu modal prompt editor (`ProfileEditorDialog` using `GlassDialog`).
- **Truncation Detection & Guarding**: Added `finishReason` parsing to `GroqChatClient` and hard rejection for `finish_reason == 'length'` in `GroqTransformService` to prevent partial sentence pasting.
- **Uniform Recording Session Lockout**: Replaced per-widget locking with centralized `_LockableControl` in `ActionBar` dimming (0.35 opacity) and blocking pointer events on all six secondary controls during `RecordingController.isSessionActive`, while keeping the silence warning button and primary recording controls 100% interactive.
- **Fail-Open Zero-Delay SLA**: Built-in instant fallback to raw transcription on timeouts, rate limits, empty prompts, truncation, or network errors to ensure user typing is never stalled.
- **Adaptive Timeout & Token Scaling**: Implemented input-scaled timeout scaling $\text{clamp}(1500\text{ms} + 25\text{ms} \times \text{wordCount}, 1.5\text{s}, 8\text{s})$ and completion token sizing.
- **Guard Normalization**: Added `TransformOutputGuard` stripping `<think>` tags, code fences, and normalizing curly/em-dash typography to ASCII equivalents before `TextSanitizer`.
- **UI Glassmorphism Integration**: Added `ProfileActionButton` popup vertical overlay menu, removed superseded `ProfileSelectorChips`, and updated `ActionBar` Incognito tooltip to `"Incognito (Local Only)"` when cloud paths are active.

## [2.25.2] - 2026-08-17
### Architecture & Subsystem Isolation
- **NeMo to Native `parakeet.cpp` Sidecar Migration**: Replaced the in-process Python `nemo_toolkit[asr]` engine with an isolated native C++ `parakeet-server` (ggml/CUDA) container communicating over local HTTP.
- **CPython Memory Corruption Resolved**: Eliminated the root cause of the CPython `b" "` singleton corruption documented in `NEMO_CPYTHON_MEMORY_CORRUPTION.md`.
- **Zero-Shim Policy Enforced**: Removed the in-process `_fixed_ws_upgrade` monkey-patch and `_SAFE_SPACE` h11 workaround in `backend/api_server.py`, restoring standard Uvicorn execution.
- **12 GB Toolchain Purged**: Removed `nemo_toolkit[asr]` and heavy PyTorch dependencies from `backend/pyproject.toml` and `backend/uv.lock`.
- **Unified Engine Contract & Health Warmup**: Consolidated `ParakeetEngine` to implement `BaseEngine` via HTTP dispatch, with lazy 10-second silent audio warmup to pre-initialize CUDA graphs.

### Audio Pipeline & Chunking
- **Silence-Aware Long-Form Chunking**: Added `backend/engine/silence_chunker.py` providing pure-Python zero-dependency RMS energy pause detection, splitting recordings exceeding 30 seconds at quiet acoustic boundaries (24s–30s).
- **Word-Level Midpoint Deduplication**: Slices long audio with word-level timestamps, filtering words across overlapping boundaries without phoneme clipping, word loss, or repetition (128x real-time on 516s benchmark).

### Tooling, Infrastructure & Release
- **CUDA Graph Diagnostic Filter**: Added `backend/tools/parakeet_log_filter.sh` to strip repetitive ggml CUDA graph warnings from container output.
- **Cross-Platform Bumper Hardening**: Hardened `scripts/bump_version.py` with newline preservation (`newline=""`), multiline regex fixes, and multi-rule file caching.
- **Release Packaging**: Compiled obfuscated Windows binary with split symbols and packaged standalone installer `win_x64_release/WhisperDoc_Setup_v2.25.2.exe`.

### Verification & Quality Gates
- **Comprehensive Test Suite**: Added test suites for silence chunking (`test_silence_chunker.py`), multi-rule newline preservation (`test_version_bumper.py`), and Parakeet multi-chunk timestamp alignment (`test_parakeet_engine.py`), with all 109 backend tests passing.

---

## [2.24.8] - 2026-08-11
### Direct Transcription & Client Features
- **Dynamic Groq Model Selector**: Added runtime model selection between `whisper-large-v3-turbo` and `whisper-large-v3` with a responsive dark-glassmorphism dropdown in the Flutter Settings UI.
- **Enclave & Persistence Hardening**: Hardened `SettingsService` with trimmed model validation and guaranteed unconditional, idempotent `SecureVault.initialize()` calls.
- **Dynamic HTTP Dispatch**: Updated `GroqHttpClient` to inject the selected model dynamically into multipart transcription requests.

### Tooling & Automation
- **Automated Version Bumper**: Created declarative `scripts/bump_version.py` utility with atomic multi-file SemVer arithmetic, `--dry-run` simulation, and `uv lock` synchronization.
- **Test Coverage Expansion**: Added test suites `test_version_bumper.py` and `groq_error_test.dart`.

---

## [2.24.7] - 2026-06-30
### Audio Availability Subsystem Hardening
- **Rich Status & Sealed Exceptions**: Introduced `AudioInputStatus` enum (`unknown`, `available`, `noDevice`, `selectedUnavailable`, `permissionDenied`) along with extensions defining `canRecord` and `bannerMessage` helpers. Replaced untyped catcher overrides in the controller with a clean sealed hierarchy of typed hardware exceptions (`NoAudioDeviceException`, `MicPermissionDeniedException`).
- **Context-Blind Services & UI Lifecycle**: Decoupled `AudioService` from Flutter widgets and context-aware overrides. Implemented `WidgetsBindingObserver` at the `HomeScreen` boundary to trigger passive re-checks when the app resumes focus, keeping Flutter bindings out of lower service directories.
- **Adaptive Recovery Monitor**: Added an adaptive self-recovering monitor in `AudioService` that polls every 3 seconds ONLY during degraded/unavailable hardware states and halts automatically once status resolves to `available`.

### Documentation & Version Syncing
- **Release Documentation Consolidation**: Created the `docs/` repository directory, generated the technical release notes, and migrated release notes files (`v1.14.0` to `v2.24.6`) and the technical changelog into the project repository.
- **Living Ledger Integration**: Established `docs/lessons_learned_and_anti_patterns.md` to track architectural guidelines, design mistakes, and system-level conventions dynamically.

---

## [2.24.6] - 2026-04-03
### Direct Transcription & Client Capability Expansion
- **Groq Cloud Direct Engine**: Added a backend-independent Groq Cloud transcription path to the Flutter client, including client-side WAV encoding, rate limiting, typed HTTP error handling, and mode-aware recording/transcription orchestration.
- **Mode-Aware UI & Settings**: Updated the Flutter settings, status, recording, and profile surfaces so WhisperDoc backend mode and Groq Cloud mode advertise the correct provider state, credentials, limits, and interaction paths.
- **Local Sanitization Boundary**: Added a Dart-side transcription sanitizer so Groq responses are cleaned before they reach the UI, clipboard, or automation path.

### Security, Storage & Runtime Reliability
- **OIDC & Secret Handling Hardening**: Tightened discovery validation, aligned backend and client identity handling around `sub` as the canonical principal, and strengthened local secret-handling paths in both Flutter and the backend.
- **Transport & Upload Correctness**: Removed event-loop blocking from backend upload validation, corrected issuer verification flow, reduced first-request Parakeet penalties, and brought Flutter WebSocket keepalive behavior into parity with the terminal client.
- **Drift/SQLite History Migration**: Replaced the unmaintained Isar history layer with Drift/SQLite, dropped obsolete dependency baggage, and modernized the Flutter dependency graph around the new storage model.

### Client Foundation & Verification
- **Flutter Foundation Cleanup**: Completed a broad Flutter client structural cleanup so services, controllers, widgets, and settings flows follow cleaner boundaries without compatibility bridges or migration scaffolding.
- **Test Suite Realignment**: Updated Flutter and terminal test coverage to match the refactored architecture directly, preserving readability while removing shim-style compliance workarounds.

---

## [2.23.6] - 2026-03-24
### Native UV Packaging & Developer Workflow
- **Backend Native UV Migration**: Completed the backend transition from split `requirements*.txt` files and `uv pip --target` installs to a first-class UV project with `backend/pyproject.toml`, `backend/uv.lock`, and Docker images that install into an in-image `.venv`.
- **Repo-Wide Quality Gates**: Added a shared `.pre-commit-config.yaml` that runs `ruff --fix` and `ruff format` separately for `backend/` and `terminal_client/`, using each project’s own `pyproject.toml` and failing cleanly when manual fixes are still required.
- **Setup Path Cleanup**: Reworked `setup.sh` into a backend-only flow that explicitly selects `whisper` or `parakeet`, syncs the matching backend environment, and updates `.env` accordingly.

### Backend Hardening & Validation
- **Import-Safe Runtime Surface**: Preserved lazy engine import behavior while restoring testable seams and keeping the backend package-safe across both engine environments.
- **Reproducible Verification Pass**: Revalidated the backend after the UV migration with Pyright, the backend pytest suite, both engine-specific Docker builds, and live Parakeet startup/transcription smoke testing.

### Client & Platform Positioning
- **Windows-Only Terminal Client Scope**: Tightened the terminal client docs and runtime contract so it is explicitly treated as a Windows fallback/debug client rather than a Linux/WSL-supported runtime.
- **Early Unsupported-Platform Exit**: Added a fail-fast guard for non-Windows terminal-client launches, replacing opaque `pynput` / X-server errors with a clear operator-facing message.

---

## [2.23.1] - 2026-03-21
### Multi-Engine ASR Architecture
- **BaseEngine Abstraction**: Introduced a unified engine contract (`transcribe`, `warmup`, `is_loaded`, `unload`) plus normalized `TranscriptionResult` and `SegmentResult` dataclasses, decoupling the WebSocket/HTTP layers from any specific ASR backend.
- **Whisper + Parakeet Implementations**: Wrapped the existing Whisper lifecycle behind `WhisperEngine` and added a thread-safe `ParakeetEngine` for NVIDIA NeMo `parakeet-tdt-0.6b-v2`, including normalized segment/timestamp mapping and engine-specific lifecycle controls.
- **Factory Dispatch**: Added `create_engine()` driven by `ASR_ENGINE`, enabling backend engine switching without protocol changes or client rewrites.

### Lifecycle & Transport Stability
- **Cache-First Model Loading**: Updated the Whisper model manager to attempt `local_files_only=True` before hitting the network, eliminating avoidable HuggingFace revision checks on warm cache.
- **Warmup Guard Rails**: Prevented unnecessary background warmup task spawning when the engine is already resident, reducing reconnect overhead.
- **Race-Condition Sweep**: Tightened backend eviction and Flutter buffered-audio flush ordering so reconnecting clients do not write stale audio into outdated sessions and idle slot enforcement no longer misclassifies short push-to-talk usage.

### Build, Dependencies & Test Realignment
- **Dependency Refresh**: Pinned the then-current backend stack around FastAPI `0.135.1`, uvicorn `0.42.0`, `websockets 16.0`, `python-jose 3.5.0`, `uvloop 0.22.1`, and the newer faster-whisper / CTranslate2 toolchain.
- **Compose & Engine Configuration**: Added `ASR_ENGINE`, updated engine defaults (`large-v3-turbo`, Parakeet v2), and introduced the dedicated Parakeet service profile and Docker pathing required by the new multi-engine architecture.
- **Test Suite Realignment**: Added engine contract/factory coverage, dedicated Whisper and Parakeet engine tests, and rewired the existing suite to the new abstraction layer and normalized result types.

---

## [2.22.2] - 2026-02-03
### Security & Availability Engineering
- **Hardening Blueprint v3.0**: Implemented **Identity-Pinned Concurrency (IPC)** via per-user semaphores to protect GPU resources from targeted DoS attacks while maintaining zero latency for concurrent users.
- **Backend Integrity Gate**: Introduced a backend-level sanitizer to neutralize "Reflected Terminal Injection" and model hallucinations before they reach the client.
- **Zero-Trust Lockdown**: Restricted backend infrastructure to local loopback (`127.0.0.1`) with mandatory 1-to-1 Docker port mapping, ensuring exclusively tunnel-mediated exposure.
- **Packet Guard & Protocol Limits**: Enforced protocol-level WebSocket frame size limits (1MB) and message complexity caps to prevent network-layer memory exhaustion.
- **Anti-Slowloris Enforcement**: Developed a minimum throughput monitor (1KB/s threshold after 60s grace) to prune idle or resource-wasting connection slots.
- **Fail-Secure Logic**: Hardened version validation (strict SemVer) and implemented OIDC Issuer Pinning to eliminate tenant-hopping and parsing bypass vectors.

### Terminal Client Modernization
- **Layered Architecture Migration**: Re-architected the terminal client into a strictly decoupled Infrastructure/Service/Logic/Controller hierarchy.
- **Zero-Loss Lifecycle**: Implemented parallel audio buffering and proactive connection warming to achieve near-instant recording readiness.
- **Transport & Credential Hygiene**: Enforced mandatory system-root TLS verification and integrated automated memory scrubbing for sensitive tokens.
- **Hardware Integration Hardening**: Added Win32 Host API validation and strict device-to-driver binding loops to eliminate invalid hardware selections.

### Flutter Client & Audio Heuristics
- **Digital-Zero Detection**: Developed a high-resolution signal heuristic ($10^{-8}$) to differentiate between silent virtual audio devices and the analog noise floor of physical microphones.
- **Reactive Silence Feedback**: Implemented a pulsing visual circuit in the ActionBar providing instant feedback and one-click corrective routing during audio signal loss.
- **Hardware Audio Routing**: Added native WASAPI input device selection with persistence and state-gated selection protection.
- **Aesthetic Standardization**: Integrated Lexend typography and Glassmorphism design tokens across configuration sub-menus.

### Performance & Container Optimization
- **Opaque Health Monitoring**: Sanity-checked the `/health` endpoint to hide system-level metadata (GPU/Version) from unauthenticated public scanning.
- **Metadata Lockdown**: Enforced `read_only` container root fs and `tmpfs` RAM-disks for secure transient audio storage in Docker.

---

## [2.20.0] - 2026-01-28
### Protocol & Security Engineering
- Standardized WebSocket 1008 rejections: Implemented a mandatory JSON error event transmission before socket closure to provide clients with explicit context (bans, versioning).
- Developed a Hardened Handshake Versioning Gate enforcing `MIN_CLIENT_VERSION` (strict block) and `SEC_CLIENT_VERSION` (advisory) logic.
- Integrated IP-governance tracking into the standardized rejection pipeline for unified active defense.
- Enhanced Handshake Observability: Captures `client` identifier and reports specific versioning and auth types at the `INFO` log level.

### Client Architecture & Orchestration
- Implemented a throttled `UpdateService` featuring a 6-hour rate-limit cooldown for GitHub discovery and state-gated listeners to minimize idle overhead.
- Introduced the `ProfileController` to decouple identity management and update tracking, adhering to the project's modularity "Principal Engineer" standards.
- Re-architected the Profile Hub into modular components: `UpdateCard` (atomic update feedback) and `ProfileInfoBlock` (identity visualization).
- Developed a Centralized Error Dispatcher in the `HomeScreen` for intelligent routing of protocol-level rejections (Bans, Updates, Auth failures).

### Performance, Stability & Logging
- Synchronized CID Logging: Captured assigned Connection IDs from the handshake to enable matched telemetry between client and server.
- Fixed a regression in `wsIdleTimeout` that caused aggressive reconnection cycles during background inactivity.
- Optimized UI notification responsiveness by refining SnackBar durations and pulse animation thresholds.
- Updated project documentation and README files across all stacks to reflect v2.20.0 security and functional enhancements.

---

## [2.19.0] - 2026-01-27
### Architectural & Structural Engineering
- Migrated to the "Smart" Modular Architecture, enforcing strict physical boundaries across five layers: Infrastructure (DI, Theme), Services (I/O, Domain Logic), Logic (Processors, Mappers), Controllers (Orchestration), and Feature-based UI.
- Decomposed the `WebSocketService` into an Orchestrator pattern, delegating specialized logic to independent sub-managers for Audio Buffering, Reconnection sequences, Heartbeat monitoring, and Reactive Configuration.
- Integrated an automated Session Lifecycle manager handling OIDC silent refresh flows and instant handshake re-synchronization upon identity changes.
- Refactored the `AuthService` into a modularized identity layer composed of an `OidcManager` (PKCE/OAuth2 protocol) and a `SessionManager` (Secure Token Persistence).
- Reorganized the feature-based UI hierarchy to isolate complex states (Recording, Settings, ProfileHub) into dedicated, testable domain folders.

### Security & Protocol Hardening
- Implemented the `HandshakePayloadBuilder` to standardize WebSocket metadata construction with tiered credential prioritization (OIDC > API Key).
- Hardened backend issuer validation utilizing slash-agnostic comparison to eliminate configuration mismatches between client and server.
- Refined URI normalization in the `TransportSecurityService` to strictly enforce WSS on public IPs while permitting explicit schemes for local development.
- Implemented a JavaScript-backed automated browser window closure verification for the OIDC callback flow.

### Backend Infrastructure & AI Performance
- Introduced predictive model warmup logic triggered immediately post-authentication to utilize user idle-time before recording starts.
- Implemented non-blocking model lifecycle management using threading locks and `asyncio.to_thread` to prevent event-loop starvation during GPU context loading.
- Optimized the backend execution environment via `uvloop` (C-based event loop) and `orjson` (high-speed binary serialization).
- Executed "Digital Liposuction" on the production Docker image, reducing size from 11.8GB to 7.35GB through static FFmpeg linking and aggressive layer pruning.
- Hardened memory hygiene using `malloc_trim` (via `ctypes`) to force OS-level RAM reclamation after Whisper model unloading.
- Implemented probabilistic silence gating to selectively return empty results when audio amplitudes fall below the noise floor, reducing transcription hallucination.

### Native Hardware Integration
- Developed the `AudioCueService` utilizing the native Windows `PlaySound` API for near-zero latency start/stop chimes.
- Implemented preloading of audio assets into native memory to bypass the overhead associated with standard high-level Dart audio packages.
- Added smart protocol detection to force `ws` on private/local network ranges, preempting TLS HandshakeErrors in local development environments.

---

## [2.13.0] - 2026-01-17
### Security Infrastructure & Identity
- Implemented RFC 7636 compliant PKCE (Proof Key for Code Exchange) authentication using the native system browser for secure identity tokens on Windows.
- Developed the `SecureVaultService`, leveraging Windows Credential Manager and PBKDF2 key derivation (100k iterations) seeded by the hardware Machine ID.
- Integrated a "Dual-Door" authentication engine supporting both stateless JWT validation (OIDC) and modular static API key verification.
- Enforced AES-256 field-level encryption for all transcription data persisted to the local Isar database using AES-CBC mode and hardware-bound IVs.
- Implemented JWKS (JSON Web Key Set) auto-discovery with a thread-safe, TTL-based public key caching layer to minimize authentication network overhead.

### Protocol Integrity & Active Defense
- Developed the "Handshake Cage" protocol, which enforces a valid JSON 'hello' sequence as the first message, buffering all incoming audio data until identity is verified.
- Implemented a bi-directional "Lock-Step" handshake to ensure granular synchronization between client and server states before promoting a connection to a ready state.
- Integrated the `BanStateService` with regex-based 1008 close code parsing to extract ban durations and provide real-time UI countdown streams.
- Hardened the transport layer with RFC 1918 validation to strictly block unencrypted WebSocket connections on public network interfaces.
- Implemented protocol algorithm pinning (RS256) and constant-time digest verification for static keys to mitigate substitution and timing side-channel attacks.

### UI Orchestration & Performance
- Refactored the `ActionBar` into a functional 5-button layout with a central dynamic connection security lock.
- Developed a multi-state security indicator system for real-time visualization of TLS 1.3/WSS, unencrypted local, and blocked/banned states.
- Optimized the desktop rendering engine by replacing global `SingleChildScrollView` structures with fixed-column layouts and internal text area scrolling to prevent UI jitter.
- Integrated high-resolution security thresholds and automated JWT expiry warning systems into the feature-layer configuration.

---

## [1.14.0] - 2026-01-12
### Core Automation & Win32 Integration
- Implemented direct Win32 clipboard API integration (`GlobalAlloc`, `SetClipboardData`) to achieve sub-150ms transcription-to-paste latency.
- Developed a native `GetMessage` blocking loop within a dedicated hardware isolate for global hotkey management, replacing resource-intensive timer polling.
- Migrated keyboard simulation from virtual keys to hardware scan codes to eliminate conflicts with the Flutter `HardwareKeyboard` internal state.
- Implemented foreground window detection logic to prevent recursive paste simulation when the application itself has focus.
- Introduced an "Immutable Isolate" pattern for hardware listeners, ensuring state purity through controlled isolate destruction and respawning.

### WebSocket Protocol & Connectivity
- Established a versioned WebSocket handshake protocol for robust client-server identification and feature capability negotiation.
- Implemented session-based lazy connections and a 5-minute automated idle timeout for efficient resource utilization.
- Developed an exponential backoff strategy for reconnections (scaling intervals up to 30 seconds) with integrated status synchronization.
- Standardized typed JSON error payloads (e.g., `NO_AUDIO`, `MODEL_LOADING`) to enable resilient UI-level exception handling.

### System Infrastructure & Build Engineering
- Implemented a multi-stage Docker build strategy (builder/runner pattern) to minimize the production footprint and secure build-time artifacts.
- Developed a comprehensive unit testing suite using `mocktail`, validating core service logic for Buffer limits, Incognito logic, and Isolate stability.
- Integrated a circular log buffer (200-entry capacity) with real-time stream emission for the in-app terminal-grade viewer.
- Implemented "Incognito Mode" (Ghost Mode) at the controller level to purge sensitive buffers and prevent persistent history logging during private sessions.
- Standardized the x64-exclusive Windows deployment pipeline via Inno Setup, including PE metadata rebranding for native Task Manager identification.
[2.25.2]: release_notes/v2.25.2.md
[2.24.8]: release_notes/v2.24.8.md
[2.24.7]: release_notes/v2.24.7.md
[2.24.6]: release_notes/v2.24.6.md
[2.23.6]: release_notes/v2.23.6.md
[2.23.1]: release_notes/v2.23.1.md
[2.22.2]: release_notes/v2.22.2.md
[2.20.0]: release_notes/v2.20.0.md
[2.19.0]: release_notes/v2.19.0.md
[2.13.0]: release_notes/v2.13.0.md
[1.14.0]: release_notes/v1.14.0.md
