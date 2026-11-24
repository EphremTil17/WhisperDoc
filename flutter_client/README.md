# WhisperDoc Flutter Client v3.3.0

A native Windows desktop application for real-time speech-to-text dictation powered by the WhisperDoc multi-engine ASR backend, with two direct cloud paths that work independently of the backend: **Groq** and **OpenRouter**.

## Purpose

WhisperDoc Client provides a lightweight, always-ready interface for voice dictation. It captures audio from your microphone, streams it to a local Whisper backend server, and receives transcriptions in real-time. The transcribed text can be automatically copied to your clipboard and pasted into any application.

When the backend is unavailable, under maintenance, or by user preference, the client can transcribe directly with your own API key: via **Groq** (free tier, `whisper-large-v3-turbo`), or via **OpenRouter**, where you pick any speech-to-text model it serves (with its live latency and accuracy), with zero data retention enforced by default. Pick the source with the three-way selector at the top of Account.

This client is designed for users who need fast, accurate dictation without leaving their current workflow. Press a global hotkey, speak, and your words appear wherever your cursor is.

## 🔒 Enterprise-Grade Security (Hardened v2.13.0)

The Flutter client has been hardened to match server-side security standards through five core pillars:

- **Identity Federation (OIDC/PKCE)**: Implements industry-standard OAuth2 PKCE (Proof Key for Code Exchange) flow via the **System Browser**. Verified via a custom Dart implementation for maximum transparency and Windows compatibility.
- **Credential Isolation**: API keys and OIDC JWTs are stored exclusively in the **Windows Credential Manager** (Secure Vault). Sensitive tokens are never written to plain-text configuration files.
- **Transport Security & RFC 1918**: Mandatory `wss://` (TLS 1.2+) is enforced for all public connections. Plain-text `ws://` is permitted **only** after validating the target as a verified local private network IP (RFC 1918).
- **Hardened Handshake (Handshake Cage)**: Implements a strict state machine that buffers audio locally and only flushes to the socket _after_ the identity-verified handshake is acknowledged by the backend.
- **Structured Error Awareness**: Routes every backend error by its structured `error_code` (never by message text), alongside numeric `1008` closures. The UI provides real-time "Ban Cooldown" countdowns, version mismatch warnings, and respects server-mandated wait periods.
- **Data-at-Rest Encryption**: Transcription history is stored in a **Drift (SQLite) database with every entry AES-256-GCM encrypted**, pruned to the newest 100 entries. Encryption keys are derived uniquely per-installation using hardware-bound salts and PBKDF2.
- **Sign-In Scope & Safe Paste (v3.2.0)**: The OIDC token is sent only to the built-in server or one the user approved with **Trust server**, and trust is forgotten on sign-out. A server transcript is accepted only after a dictation ends, sanitized, and pasted as plain text.
- **Memory Hygiene**: Toggleable **Incognito Mode** ensures zero-persistence on the backend (Ghost Mode) and performs explicit RAM clearing of sensitive transcription buffers on the client.

The client follows a **Smart Modular Architecture** designed for high scalability and zero-latency performance:

```
lib/
├── controllers/      # State orchestration (RecordingController, ProfileController)
├── infrastructure/   # System foundations (DI, Theme, Constants)
├── logic/            # Pure domain logic (Processors, Mappers, Models)
│   ├── models/       # DictationProfileSpec, DictationProfile, CustomProfile, HistoryEntry
│   └── processors/   # TransformOutputGuard, TextSanitizer, AudioSignalProcessor
├── services/         # Functional domain specialized services
│   ├── auth/         # OIDC & Session management
│   ├── hardware/     # Audio capture & Hotkey listeners
│   ├── transcription/# Cloud STT (Groq, OpenRouter), model catalog, LLM styles
│   ├── transport/    # WebSocket orchestration & Handshake
│   └── utility/      # Logging, Secure Vault, Settings
├── ui/               # Presentation layer
│   ├── features/     # Feature modules (recording)
│   ├── screens/      # Main screens & contextual dialogs (ProfileEditorDialog)
│   └── shared/       # Global widgets (AppPanel, AppDialog, CrispText, PixelMeter)
└── main.dart         # Clean entry point with service bootstrap
```

### Key Design Principles

- **Dependency Injection**: Uses `get_it` for service location and clean testability.
- **Single Source of Truth**: Controllers own state and listen to underlying services.
- **Immutable Isolate Pattern**: Hotkey listener respawns on settings change for clean state.
- **Native Win32 Integration**: Direct API calls for clipboard, hotkeys, and keyboard simulation.
- **Zero-Trust Networking**: Validates server parity during the versioned handshake.

## Tech Stack

| Component        | Technology                       |
| ---------------- | -------------------------------- |
| Framework        | Flutter 3.x (Windows)            |
| State Management | Provider + ChangeNotifier        |
| Database         | Drift / SQLite (AES-GCM entries) |
| Secure Storage   | flutter_secure_storage (WinCred) |
| Networking       | WebSocket (web_socket_channel)   |
| Cloud STT        | Groq and OpenRouter REST (http)  |
| Native APIs      | Win32 via ffi/win32 packages     |
| Encryption       | encrypt (AES-256-GCM)            |

- **Client-Edge Dictation Profiles & Custom LLM Prompts**: Built-in factory standards (**Raw**, **Clean Polish**, **Professional**, **Casual**, **Technical**) and up to three user-authored **Custom Profiles** (`CustomProfile` implementing `DictationProfileSpec`). Features an in-menu modal editor (`ProfileEditorDialog` on `AppDialog`) with sequential default naming (`Custom 1..3`), user renaming, a 2,000 character cap, automatic safety preamble prepending, and length-based truncation rejection. Secondary controls are uniformly locked during active recording.
- **Three Transcription Sources**: Your WhisperDoc server, **Groq** or **OpenRouter**, chosen from one selector in Account. Cloud sources share one engine interface (`SpeechEngine`): the clip is WAV-encoded on-device and uploaded when you stop, over a keep-alive connection that is warmed while you talk, so the upload skips the TLS handshake.
- **Groq Direct Transcription**: `whisper-large-v3-turbo` or `whisper-large-v3` with client-side rate-limit tracking, language validation and a 23 MiB (~12.5 min) buffer guard that keeps the upload under the 25 MB limit.
- **OpenRouter Model Choice**: The model picker lists every speech model OpenRouter serves right now (nothing about availability is hard-coded): each with its maker, OpenRouter's live latency, and its word error rate from a fixed Artificial Analysis snapshot (2026-11-23, in `speech_model_accuracy.dart`; unmeasured models show "—"), most accurate first. Models being retired are marked by date and a retired choice is flagged on the home screen. Links open OpenRouter's model table and Artificial Analysis to compare further. Zero data retention is on by default (only models with a zero-retention host are offered, and every request enforces it). Output styles run on OpenRouter too.
- **Instantaneous Connection**: Implements a "Zero-Latency" recording flow. Audio capture and UI feedback initiate instantly while the WebSocket handshake completes in parallel.
- **Background Auto-Wake**: The transport layer automatically resumes connectivity when a recording is initiated, removing the need for manual connection management.
- **Advanced Security Indicators**: Visual feedback (Lock/Warning/Block) for connection security status.
- **JWT Expiry Warnings**: Automatic detection of session tokens with user-friendly expiry countdowns.
- **Deep Sleep Proof Hotkeys**: Native `GetMessage` blocking loop ensures hotkeys work after system sleep.
- **Global Hotkey**: Trigger recording from any application (default: Ctrl+Alt+E).
- **Auto Copy/Paste**: Automatically insert transcriptions at your cursor.
- **WebSocket Resilience**: Retries back off from 2 s to once a minute and stop on sign-out, with a cloud source active, or after a ban. An unreachable server shows `[ server offline ]` with **Try again**.
- **Intelligent Idle Timeout**: Connection auto-closes after inactivity to save resources.
- **Incognito Mode**: Protocol-level privacy flag with memory hygiene. With a cloud source, Incognito is Local Only — local history is disabled but audio is processed by the cloud service.
- **Verification Suite**: Modular security tests (`auth_service_test.dart`) validating PKCE integrity and state-parameter protection.
- **Captions UI**: Crimson on near-black in a borderless 420×600 window: one status cue, a live pixel meter, the last transcript set as captions, and an optional moving contour map. Lexend type sits on whole pixels for crisp rendering.

## Prerequisites

- Windows 10/11
- Flutter SDK 3.50+ (Dart 3.14; the client uses the separate `material_ui` package)
- A running WhisperDoc backend server, **or** a [Groq API key](https://console.groq.com) (free tier), **or** an [OpenRouter API key](https://openrouter.ai/keys) with credits

## Quick Start

1. **Install dependencies**
   ```bash
   flutter pub get
   ```
2. **Configure Environment**
   Duplicate `env.json.template` to `env.json` and fill in your OIDC credentials.

3. **Run in development**
   ```bash
   flutter run -d windows --dart-define-from-file=env.json
   ```
4. **Build release**
   ```bash
   # Templatized production build command:
   flutter build windows --release --build-name=<version> --build-number=<build_number> --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env.json

   # Example for current v3.3.0 release:
   flutter build windows --release --build-name=3.3.0 --build-number=1 --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env.json
   ```

5. **Package Windows Installer**
   ```powershell
   # Paths in the script are relative to it, so this works from any checkout:
   & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows\installer\whisperdoc_setup.iss
   # Output: windows\installer\WhisperDoc_Setup_v<version>.exe
   ```
   Official installers are built by the **Release** workflow when a `vX.Y.Z` tag is pushed, and attached to a draft GitHub Release. Local packaging is for testing.

## Configuration

Two full-window panels hold every setting. Each change saves on its own.

**Account** (the person icon, top right):

- **Source selector** (top of Account): **Self-hosted**, **Groq** or **OpenRouter**. Switching to a cloud source without its key opens the key field.
  - _Self-hosted_: **Server address** (e.g. `ws://localhost:9989/ws`; `http(s)://` and bare hosts are accepted), **Sign in**, and an optional **Developer key**. A custom server you sign in to asks once before your sign-in is sent to it.
  - _Groq_: **Groq API key** (stored in Windows Credential Manager), **Model**, **Language** (picked by name), and **Words to expect** for names and domain terms.
  - _OpenRouter_: **OpenRouter API key** (Credential Manager), **Model** (the live list, with latency and word error rate), **Rewrite model** for output styles (Qwen3.8 27B unless you enter another OpenRouter model id; it is checked with a one-word rewrite before it is saved), **Zero data retention** (on by default; turning it off asks first) and **Language**.
- **App**: Version, update when one is available, and **Logs**.

**Settings** (the sliders icon, bottom right):

- **Recording**: Microphone and the level meter.
- **Shortcut**: The global hotkey (default Ctrl+Alt+E).
- **When you stop**: Copy to clipboard, and paste where your cursor is.
- **Appearance**: Moving background. Turn it off for a still map on slower computers.

## Known Limitations

### Hot Reload Does Not Work During Development

Due to the use of native Win32 blocking calls (`GetMessage`) in the hotkey isolate, **hot reload will hang indefinitely**. This is a trade-off for having bulletproof, deep-sleep-resistant hotkey handling.

**Workarounds:**

- Use **Hot Restart** (`Shift+R` in terminal) instead of hot reload.
- Press the hotkey before attempting hot reload (unblocks the isolate momentarily).
- Full app restart (`q` to stop, then `flutter run` again).

> **Note**: This limitation only affects development. Production builds are unaffected.

## Recent Improvements (v3.3.0)

- **OpenRouter Source**: A third source beside the server and Groq, chosen from a selector at the top of Account. The model list is live, ordered by accuracy with each model's latency, and zero data retention is on by default.
- **Rewrite Model**: Output styles run on OpenRouter too, with Qwen3.8 27B by default or any model id, checked with a one-word rewrite before it is saved.
- **Tech Style**: Keeps your words and writes code terms, frameworks and protocols exactly; a numbered list only for steps you count off.
- **Accessibility**: The source selector no longer breaks Windows' accessibility tree, and each source can be pressed from a screen reader.

## Improvements in v3.2.0

### Captions Interface

- **One Cue, One Fix**: `HomeStatusMapper` turns service signals into a single status cue (`[ ready ]`, `[ listening ]`, `[ transcribing ]`, `[ server offline ]` …), the one action that unblocks it, and the account badge.
- **Pixel Meter & Contour Map**: A retro meter at display refresh, normalized against each microphone's noise floor and peak, and a GPU-drawn topography that answers the cursor, flattens while you dictate, and can be switched off.
- **Panels**: Account, Settings, History and Logs share one panel kit (`AppPanel`, `PanelRow`, `ChoicePanel`, `FieldPanel`). Dialogs remain only for confirmations, the shortcut recorder and the style editor.
- **Native Window**: The runner creates a borderless, square window with a 420×600 client area before Flutter starts. Fonts and the Lucide icon font are bundled; nothing is downloaded at startup.

### Security & Reliability

- **Sign-In Scope**: The OIDC token goes only to the built-in server or one approved with **Trust server**. Trust is forgotten on sign-out or an account switch.
- **Transcript Gate**: A server transcript is used only within two minutes of a dictation ending, sanitized, and pasted on one line. Raw, Clean and Casual polishes also paste on one line; Pro, Tech and custom styles keep paragraphs.
- **Connection Lifecycle**: `connect()` resolves once the sign-in is accepted and is shared by concurrent callers. Failed and stale sockets are closed and ignored, and a dropped connection mid-dictation is reported instead of losing the text silently.
- **Clean Exit**: Closing the window always wakes the hotkey thread, so the process ends instead of lingering without a window.

## Older Improvements (v3.1.0)

### Startup, Devices & Session Reliability

- **Boot Screen First Frame**: The window is configured hidden and shown on a branded `BootScreen` frame while services initialize behind it, eliminating the white launch flash and the rare frozen white window. Setup failures are shown instead of hanging.
- **Offline-Safe Sessions**: Session restore no longer waits on the network. OIDC requests have 10 s timeouts, and the client signs out only when the identity provider definitively rejects the refresh token (HTTP 400/401), never on a network error.
- **Native Microphone Hot-Plug**: A Win32 `IMMNotificationClient` in the runner pushes Core Audio device events to Dart over `whisperdoc/audio_devices`, so plugging in a microphone recovers immediately with no polling. An unavailable selected device falls back to the system default.
- **Recording Race Guards**: Overlapping start/stop requests can no longer open a second capture stream or upload and paste the same clip twice.

### Security & Correctness

- **Unicode-Preserving Sanitizer**: `TextSanitizer` strips only ANSI sequences and control characters, so accents, typographic punctuation, and non-Latin scripts survive in both backend and Groq modes.
- **Safe Paste**: Auto-paste runs only after the clipboard write succeeds, so a locked clipboard can never paste stale contents (such as a password) into the focused window.
- **`error_code` Routing**: Server errors are classified by `error_code`, so operational errors no longer end the session and the "No audio detected" hint now appears.
- **Bounded Connects**: WebSocket connects time out instead of hanging.

### Performance

- **Narrow Rebuilds**: Widgets subscribe only to the state they render, history entries are decrypted once per dialog, and pulsing buttons no longer smear from restarted implicit animations.

## Older Improvements (v2.24.0)

### Groq Cloud Direct Transcription

- **Backend-Independent STT**: New `services/transcription/` module provides a complete Groq Cloud speech-to-text path using `whisper-large-v3-turbo`. Audio is captured locally as 16 kHz PCM, WAV-encoded on-device, and POSTed directly to Groq's REST API — no backend required.
- **Connection Mode Toggle**: A WhisperDoc/Groq Cloud toggle in the CONNECTION settings header switches the entire client between backend WebSocket mode and direct Groq Cloud mode. The backend connection lifecycle is fully dormant in Groq mode (no auto-connect, no reconnect, no WebSocket overhead).
- **Free-Tier Compliance**: Client-side rate-limit tracking (sliding-window RPM + daily counter), `retry-after` header parsing on 429 responses, and a conservative 24 MB buffer ceiling (~12.5 min at 16 kHz mono) that auto-stops recording with a clear user message.
- **Language Validation**: Inline validation of the language hint field against Groq's 99 supported ISO-639-1 codes, with a pre-record gate that prevents invalid codes from reaching the API.
- **Credential Isolation**: Groq API key and backend API key stored in separate SecureVault entries. Empty keys are deleted from the vault instead of storing empty strings. The mode toggle swaps displayed credentials without overwriting the inactive key.
- **Mode-Aware Settings**: Settings screen conditionally hides backend-only sections (Identity & Access, Developer Settings) in Groq mode, keeping the UI clean and contextual.
- **Transcription Lockout**: A single `isTranscribing` flag in `RecordingController` prevents hotkey, capsule, and settings toggle races during Groq upload.
- **Incognito Clarity**: Incognito tooltip appends "(Local Only)" in Groq mode to communicate that local history is disabled but audio is processed by a third-party cloud service.

## Older Improvements (v2.23.5)

### Transport Fingerprinting & Structured Errors

- **OIDC Identity Fingerprint**: `ConfigurationManager` now tracks OIDC identity state (`userId`, `isAuthenticated`) separately from settings. Silent token refreshes no longer trigger unnecessary WebSocket reconnects, while real identity changes (sign-in, sign-out, user switch) still force a reconnect.
- **Structured Error Compatibility**: The backend now emits `error_code` strings (`AUTH_FAILED`, `IP_BANNED`, `VERSION_OUTDATED`, etc.) alongside numeric codes, enabling precise client-side error routing without breaking backwards compatibility.
- **CORS Spec Compliance**: Backend CORS middleware now conditionally sets `allow_credentials` based on whether specific origins are configured, fixing a spec violation that caused browsers to reject credentialed cross-origin requests.

If the Flutter client is temporarily unavailable, the Python terminal client remains the supported fallback for backend diagnostics and low-level transport debugging.

## Older Improvements (v2.20.0)

### 🧩 Modular Profile Hub & Controllers

- **Profile Controller Architecture**: Decoupled authentication and update logic from the UI using a dedicated controller.
- **Update Card & Profile Block**: Atomic, shared widgets that provide clean visual feedback for user identity and version status.
- **Pulse Indicators**: Context-aware glowing animations for "Update Available" (Amber) and "Critical Required" (Red) states.

### 🚦 Intelligent Error Handling & Update Controls

- **Standardized 1008 Rejections**: Full support for the backend's JSON-to-Close protocol with structured `error_code` fields, ensuring descriptive error messages for bans or version mismatches.
- **Throttled Update Service**:
  - Implemented a **6-hour GitHub cooldown** to prevent API rate limiting.
  - Handshake-gated re-evaluations: Only checks for updates when connecting/authenticating, reducing idle CPU load.
- **CID Synchronization**: Captures and logs the 4-digit **Connection ID** from the server hello, allowing perfect log correlation between client and backend.
- **Snappier Feedback**: Error notifications (SnackBars) optimized to 1-second duration for a more responsive UI flow.

## Older Improvements (v2.14.0)

### Performance & Stability

- **uvloop & orjson Support**: Client communication is now faster due to the backend's move to ultra-high performance I/O and JSON serialization.
- **Drift-Proof Handshake**: Handshake timing is more resilient to network jitter and backend scheduling.
- **Improved Resource Cleanup**: Accelerated model unloading and RAM reclamation on the backend reduces idle latency for new sessions.

## Older Improvements (v2.13.0)

### Hotkey Resilience

- Replaced `Timer.periodic` polling with native `GetMessage` blocking loop
- Hotkeys now work reliably after system sleep/hibernate
- Implemented "Immutable Isolate" pattern: service respawns on settings change

### WebSocket Resilience

- Fixed reconnection logic bug (status was checked after update, not before)
- Added exponential backoff for reconnections to prevent resource waste
- Idle timeout reduced to 3 minutes for faster resource cleanup

### OIDC Identity Integration

- Implemented manual OAuth2 PKCE flow for Windows compatibility
- Replaced third-party OIDC libraries with a lean Dart implementation
- Added **System Browser** authentication for enhanced user trust and security

### Security Hardening

- Implemented the **Handshake Cage** (buffer-then-flush) strategy
- Added OIDC session persistence using hardware-bound secure storage
- Explicitly masked sensitive authentication tokens in technical logs

### Architecture Refactoring

- Added `get_it` for dependency injection
- Created `AppConstants` for centralized configuration
- Moved `RecordingController` from UI layer to core layer
- Shifted to a **Templatized Configuration** using `String.fromEnvironment`
- Consolidated JWT logic using `jwt_decoder` and removed legacy `dart_jsonwebtoken`
- Implemented a Win32 Named Mutex to enforce single-instance integrity
- Created `GlassDialog` reusable widget (reduced dialog boilerplate by ~50 lines each)

## License

See the root project LICENSE file.
