# WhisperDoc Flutter Client v2.24.0

A native Windows desktop application for real-time speech-to-text dictation powered by the WhisperDoc multi-engine ASR backend, with an alternative **Groq Cloud** direct transcription path that works independently of the backend.

## Purpose

WhisperDoc Client provides a lightweight, always-ready interface for voice dictation. It captures audio from your microphone, streams it to a local Whisper backend server, and receives transcriptions in real-time. The transcribed text can be automatically copied to your clipboard and pasted into any application.

When the backend is unavailable, under maintenance, or by user preference, the client can transcribe directly via **Groq Cloud** using the same `whisper-large-v3-turbo` model — no backend required. Switch between modes with a single toggle in Settings.

This client is designed for users who need fast, accurate dictation without leaving their current workflow. Press a global hotkey, speak, and your words appear wherever your cursor is.

## 🔒 Enterprise-Grade Security (Hardened v2.13.0)

The Flutter client has been hardened to match server-side security standards through five core pillars:

- **Identity Federation (OIDC/PKCE)**: Implements industry-standard OAuth2 PKCE (Proof Key for Code Exchange) flow via the **System Browser**. Verified via a custom Dart implementation for maximum transparency and Windows compatibility.
- **Credential Isolation**: API keys and OIDC JWTs are stored exclusively in the **Windows Credential Manager** (Secure Vault). Sensitive tokens are never written to plain-text configuration files.
- **Transport Security & RFC 1918**: Mandatory `wss://` (TLS 1.2+) is enforced for all public connections. Plain-text `ws://` is permitted **only** after validating the target as a verified local private network IP (RFC 1918).
- **Hardened Handshake (Handshake Cage)**: Implements a strict state machine that buffers audio locally and only flushes to the socket _after_ the identity-verified handshake is acknowledged by the backend.
- **Structured Error Awareness**: Handles all backend `error_code` types alongside numeric `1008` closures. The UI provides real-time "Ban Cooldown" countdowns, version mismatch warnings, and respects server-mandated wait periods.
- **Data-at-Rest Encryption**: Transcription history is stored in an **AES-256 encrypted Isar database**. Encryption keys are derived uniquely per-installation using hardware-bound salts and PBKDF2.
- **Memory Hygiene**: Toggleable **Incognito Mode** ensures zero-persistence on the backend (Ghost Mode) and performs explicit RAM clearing of sensitive transcription buffers on the client.

The client follows a **Smart Modular Architecture** designed for high scalability and zero-latency performance:

```
lib/
├── controllers/      # State orchestration (RecordingController)
├── infrastructure/   # System foundations (DI, Theme, Constants)
├── logic/            # Pure domain logic (Processors, Mappers, Models)
├── services/         # Functional domain specialized services
│   ├── auth/         # OIDC & Session management
│   ├── hardware/     # Audio capture & Hotkey listeners
│   ├── transcription/# Groq Cloud direct transcription engine
│   ├── transport/    # WebSocket orchestration & Handshake
│   └── utility/      # Logging, Secure Vault, Settings
├── ui/               # Presentation layer
│   ├── features/     # Feature modules (recording, settings)
│   ├── screens/      # Main screens & contextual dialogs
│   └── shared/       # Global widgets & theme tokens
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
| Database         | Isar (AES-256 Encrypted)         |
| Secure Storage   | flutter_secure_storage (WinCred) |
| Networking       | WebSocket (web_socket_channel)   |
| Cloud STT        | Groq REST API (http)             |
| Native APIs      | Win32 via ffi/win32 packages     |
| Encryption       | encrypt (AES/CBC)                |

- **Groq Cloud Direct Transcription**: Backend-independent speech-to-text via Groq's `whisper-large-v3-turbo` REST API with local WAV encoding, client-side rate-limit tracking, language validation, and a conservative 24 MB (~12.5 min) buffer guard. Switch between WhisperDoc backend and Groq Cloud from the Connection toggle in Settings.
- **Instantaneous Connection**: Implements a "Zero-Latency" recording flow. Audio capture and UI feedback initiate instantly while the WebSocket handshake completes in parallel.
- **Background Auto-Wake**: The transport layer automatically resumes connectivity when a recording is initiated, removing the need for manual connection management.
- **Advanced Security Indicators**: Visual feedback (Lock/Warning/Block) for connection security status.
- **JWT Expiry Warnings**: Automatic detection of session tokens with user-friendly expiry countdowns.
- **Deep Sleep Proof Hotkeys**: Native `GetMessage` blocking loop ensures hotkeys work after system sleep.
- **Global Hotkey**: Trigger recording from any application (default: Ctrl+Alt+E).
- **Auto Copy/Paste**: Automatically insert transcriptions at your cursor.
- **WebSocket Resilience**: Exponential backoff reconnection with ban-awareness.
- **Intelligent Idle Timeout**: Connection auto-closes after inactivity to save resources.
- **Incognito Mode**: Protocol-level privacy flag with memory hygiene. In Groq mode, Incognito is Local Only — local history is disabled but audio is processed by Groq Cloud.
- **Verification Suite**: Modular security tests (`auth_service_test.dart`) validating PKCE integrity and state-parameter protection.
- **Glassmorphic UI**: Modern, translucent design with integrated OIDC identity hardening.

## Prerequisites

- Windows 10/11
- Flutter SDK 3.x
- A running WhisperDoc backend server **or** a [Groq API key](https://console.groq.com) (free tier)

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
   flutter build windows --release --obfuscate --split-debug-info=build/debug-info --dart-define-from-file=env.json
   ```

## Configuration

Access settings via the gear icon or hamburger menu:

- **Connection Mode**: Toggle between **WhisperDoc** (self-hosted backend) and **Groq Cloud** (direct API).
  - _WhisperDoc_: Enter the WebSocket endpoint (e.g., `ws://localhost:9989/ws`).
  - _Groq Cloud_: Enter your Groq API key (stored in Windows Credential Manager). Optionally set a language hint (ISO-639-1) and a prompt hint for domain-specific vocabulary.
- **Secure Key** (WhisperDoc mode): Enter your backend API Key or JWT via Developer Settings.
- **Global Hotkey**: Customize your trigger key combination.
- **Auto Copy/Paste**: Control automation behavior.

## Known Limitations

### Hot Reload Does Not Work During Development

Due to the use of native Win32 blocking calls (`GetMessage`) in the hotkey isolate, **hot reload will hang indefinitely**. This is a trade-off for having bulletproof, deep-sleep-resistant hotkey handling.

**Workarounds:**

- Use **Hot Restart** (`Shift+R` in terminal) instead of hot reload.
- Press the hotkey before attempting hot reload (unblocks the isolate momentarily).
- Full app restart (`q` to stop, then `flutter run` again).

> **Note**: This limitation only affects development. Production builds are unaffected.

## Recent Improvements (v2.24.0)

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
