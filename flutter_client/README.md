# WhisperDoc Flutter Client v2.10.0

A native Windows desktop application for real-time speech-to-text dictation powered by OpenAI's Whisper model.

## Purpose

WhisperDoc Client provides a lightweight, always-ready interface for voice dictation. It captures audio from your microphone, streams it to a local Whisper backend server, and receives transcriptions in real-time. The transcribed text can be automatically copied to your clipboard and pasted into any application.

This client is designed for users who need fast, accurate dictation without leaving their current workflow. Press a global hotkey, speak, and your words appear wherever your cursor is.

## 🔒 Enterprise-Grade Security (Hardened v2.8)

The Flutter client has been hardened to match server-side security standards through five core pillars:

- **Credential Isolation**: API keys and OIDC JWTs are stored exclusively in the **Windows Credential Manager** (Secure Vault). Sensitive tokens are never written to plain-text configuration files.
- **Transport Security & RFC 1918**: mandatory `wss://` (TLS 1.2+) is enforced for all public connections. Plain-text `ws://` is permitted **only** after validating the target as a verified local private network IP (RFC 1918).
- **Hardened Handshake Protocol**: Implements a strict state machine that buffers audio locally and only flushes to the socket *after* the identity-verified handshake is acknowledged by the backend.
- **Active Defense Awareness**: Intelligently handles `1008` (Policy Violation) closures. The UI provides real-time "Ban Cooldown" countdowns and disables reconnection attempts until the server-mandated wait period expires.
- **Data-at-Rest Encryption**: Transcription history is stored in an **AES-256 encrypted Isar database**. Encryption keys are derived uniquely per-installation using hardware-bound salts and PBKDF2.
- **Memory Hygiene**: Toggleable **Incognito Mode** ensures zero-persistence on the backend (Ghost Mode) and performs explicit RAM clearing of sensitive transcription buffers on the client.

## Architecture

The client follows a **feature-sliced architecture** with clear separation of concerns:

```
lib/
├── core/
│   ├── constants/       # Centralized configuration (AppConstants)
│   ├── controllers/     # Business logic controllers (RecordingController)
│   ├── di/              # Dependency injection (ServiceLocator with get_it)
│   ├── models/          # Data structures (TranscriptionEntry)
│   ├── services/        # Core services (Audio, WebSocket, Settings, SecureVault)
│   └── utils/           # Helpers (Win32 key mapping)
├── ui/
│   ├── features/        # Feature modules (recording, settings)
│   ├── screens/         # Top-level screens (Home, Settings, Dialogs)
│   ├── shared/widgets/  # Reusable UI components (GlassDialog, etc.)
│   └── theme/           # Design tokens and theming
└── main.dart            # App entry point
```

### Key Design Principles

- **Dependency Injection**: Uses `get_it` for service location and clean testability.
- **Single Source of Truth**: Controllers own state and listen to underlying services.
- **Immutable Isolate Pattern**: Hotkey listener respawns on settings change for clean state.
- **Native Win32 Integration**: Direct API calls for clipboard, hotkeys, and keyboard simulation.
- **Zero-Trust Networking**: Validates server parity during the versioned handshake.

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter 3.x (Windows) |
| State Management | Provider + ChangeNotifier |
| Database | Isar (AES-256 Encrypted) |
| Secure Storage | flutter_secure_storage (WinCred) |
| Networking | WebSocket (web_socket_channel) |
| Native APIs | Win32 via ffi/win32 packages |
| Encryption | encrypt (AES/CBC) |

## Features

- **Advanced Security Indicators**: Visual feedback (Lock/Warning/Block) for connection security status.
- **JWT Expiry Warnings**: Automatic detection of session tokens with user-friendly expiry countdowns.
- **Deep Sleep Proof Hotkeys**: Native `GetMessage` blocking loop ensures hotkeys work after system sleep.
- **Global Hotkey**: Trigger recording from any application (default: Ctrl+Alt+E).
- **Auto Copy/Paste**: Automatically insert transcriptions at your cursor.
- **WebSocket Resilience**: Exponential backoff reconnection with ban-awareness.
- **Intelligent Idle Timeout**: Connection auto-closes after inactivity to save resources.
- **Incognito Mode**: Protocol-level privacy flag with memory hygiene.
- **Glassmorphic UI**: Modern, translucent design that stays out of your way.

## Prerequisites

- Windows 10/11
- Flutter SDK 3.x
- A running WhisperDoc backend server

## Quick Start

```bash
# Install dependencies
flutter pub get

# Run in development
flutter run -d windows

# Build release (with obfuscation)
flutter build windows --release --obfuscate --split-debug-info=build/debug-info
```

## Configuration

Access settings via the gear icon or hamburger menu:

- **Server URI**: WebSocket endpoint (e.g., `ws://localhost:9989/ws`).
- **Secure Key**: Enter your API Key or JWT (stored in Windows Credential Manager).
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

## Recent Improvements (v1.13.0)

### Hotkey Resilience
- Replaced `Timer.periodic` polling with native `GetMessage` blocking loop
- Hotkeys now work reliably after system sleep/hibernate
- Implemented "Immutable Isolate" pattern: service respawns on settings change

### WebSocket Resilience
- Fixed reconnection logic bug (status was checked after update, not before)
- Added exponential backoff for reconnections to prevent resource waste
- Idle timeout reduced to 3 minutes for faster resource cleanup

### Architecture Refactoring
- Added `get_it` for dependency injection
- Created `AppConstants` for centralized configuration
- Moved `RecordingController` from UI layer to core layer
- Created `GlassDialog` reusable widget (reduced dialog boilerplate by ~50 lines each)

## License

See the root project LICENSE file.
