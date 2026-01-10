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
│   ├── models/          # Data structures (TranscriptionEntry)
│   ├── services/        # Business logic (Audio, WebSocket, Settings, Hotkey)
│   └── utils/           # Helpers (Win32 key mapping)
├── ui/
│   ├── features/        # Feature modules (recording, settings)
│   ├── screens/         # Top-level screens
│   ├── shared/widgets/  # Reusable UI components
│   └── theme/           # Design tokens and theming
└── main.dart            # App entry point and DI setup
```

### Key Design Principles

- **Single Source of Truth**: Controllers own their state and listen to underlying services
- **Selective Listeners**: Services only react to relevant configuration changes
- **Native Integration**: Win32 APIs for clipboard, global hotkeys, and keyboard simulation
- **Minimal Latency**: Audio streams directly to the server with no local buffering delays

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter (Windows) |
| State Management | Provider + ChangeNotifier |
| Audio Capture | record package (16kHz PCM) |
| Networking | WebSocket (web_socket_channel) |
| Native APIs | Win32 via ffi/win32 packages |
| Typography | Google Fonts (Lexend) |

## Features

- **Global Hotkey**: Trigger recording from any application (default: Ctrl+Alt+R)
- **Real-time Transcription**: See words appear as you speak
- **Auto Copy/Paste**: Automatically insert transcriptions at your cursor
- **Audio Visualizer**: Live waveform feedback during recording
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

# Build release
flutter build windows --release
```

## Configuration

Access settings via the gear icon or hamburger menu:

- **Server URI**: WebSocket endpoint (e.g., `ws://localhost:9989/ws`)
- **Global Hotkey**: Customize your trigger key combination
- **Auto Copy**: Automatically copy transcriptions to clipboard
- **Auto Paste**: Automatically paste into the focused application

## Project Structure Rationale

The feature-sliced approach was chosen to:

1. **Enable independent feature development** without cross-contamination
2. **Simplify testing** by isolating business logic in controllers/services
3. **Support future features** like offline mode and history management
4. **Maintain clear dependency flow** from UI → Controllers → Services

## License

See the root project LICENSE file.
