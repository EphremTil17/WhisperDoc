# WhisperDoc Flutter Client

A native Windows desktop application for real-time speech-to-text dictation powered by OpenAI's Whisper model.

## Purpose

WhisperDoc Client provides a lightweight, always-ready interface for voice dictation. It captures audio from your microphone, streams it to a local Whisper backend server, and receives transcriptions in real-time. The transcribed text can be automatically copied to your clipboard and pasted into any application.

This client is designed for users who need fast, accurate dictation without leaving their current workflow. Press a global hotkey, speak, and your words appear wherever your cursor is.

## Architecture

The client follows a **feature-sliced architecture** with clear separation of concerns:

```
lib/
├── core/
│   ├── constants/       # Centralized configuration (AppConstants)
│   ├── controllers/     # Business logic controllers (RecordingController)
│   ├── di/              # Dependency injection (ServiceLocator with get_it)
│   ├── models/          # Data structures (TranscriptionEntry)
│   ├── services/        # Core services (Audio, WebSocket, Settings, Hotkey)
│   └── utils/           # Helpers (Win32 key mapping)
├── ui/
│   ├── features/        # Feature modules (recording, settings)
│   ├── screens/         # Top-level screens (Home, Settings, Dialogs)
│   ├── shared/widgets/  # Reusable UI components (GlassDialog, etc.)
│   └── theme/           # Design tokens and theming
└── main.dart            # App entry point
```

### Key Design Principles

- **Dependency Injection**: Uses `get_it` for service location and clean testability
- **Single Source of Truth**: Controllers own state and listen to underlying services
- **Immutable Isolate Pattern**: Hotkey listener respawns on settings change for clean state
- **Native Win32 Integration**: Direct API calls for clipboard, hotkeys, and keyboard simulation
- **Minimal Latency**: Audio streams directly to the server with no local buffering delays

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter 3.x (Windows) |
| State Management | Provider + ChangeNotifier |
| Dependency Injection | get_it |
| Audio Capture | record package (16kHz PCM) |
| Networking | WebSocket (web_socket_channel) |
| Native APIs | Win32 via ffi/win32 packages |
| Typography | Google Fonts (Lexend) |

## Features

- **Deep Sleep Proof Hotkeys**: Native `GetMessage` blocking loop ensures hotkeys work after system sleep
- **Global Hotkey**: Trigger recording from any application (default: Ctrl+Alt+E)
- **Real-time Transcription**: See words appear as you speak
- **Auto Copy/Paste**: Automatically insert transcriptions at your cursor
- **WebSocket Resilience**: Exponential backoff reconnection (3s, 6s, 12s... up to 30s)
- **Intelligent Idle Timeout**: Connection auto-closes after 3 minutes of inactivity to save resources
- **Audio Visualizer**: Live waveform feedback during recording
- **Incognito Mode**: Temporarily disable history recording
- **Configurable Backend**: Connect to any Whisper server endpoint
- **Glassmorphic UI**: Modern, translucent design that stays out of your way

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

- **Server URI**: WebSocket endpoint (e.g., `ws://localhost:9989/ws`)
- **Global Hotkey**: Customize your trigger key combination
- **Auto Copy**: Automatically copy transcriptions to clipboard
- **Auto Paste**: Automatically paste into the focused application

## Known Limitations

### Hot Reload Does Not Work During Development

Due to the use of native Win32 blocking calls (`GetMessage`) in the hotkey isolate, **hot reload will hang indefinitely**. This is a trade-off for having bulletproof, deep-sleep-resistant hotkey handling.

**Workarounds:**
- Use **Hot Restart** (`Shift+R` in terminal) instead of hot reload
- Press the hotkey before attempting hot reload (unblocks the isolate momentarily)
- Full app restart (`r` to stop, then `flutter run` again)

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

