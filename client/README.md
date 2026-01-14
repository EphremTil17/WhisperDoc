# WhisperDoc Client (v2.3.0)

A secure, modular, and high-performance Python terminal client for real-time dictation using the WhisperDoc backend.

## Features

### Enterprise-Grade Security
*   **Secure API Key Storage**: Uses the OS native credential manager (Windows Credential Manager, macOS Keychain, Linux Secret Service) via `keyring`. Keys are **never** stored in plain text files.
*   **Fail-Secure Architecture**: Validates credentials against the server *before* initializing hardware (mic/hotkeys). If auth fails, the client exits immediately.
*   **Transport Security**: Enforces `wss://` (TLS 1.2+) for all remote connections.
*   **RFC 1918 Compliance**: Intelligently falls back to plain text (`ws://`) **only** if the target is a verified private network IP (e.g., `192.168.x.x`), ensuring security without breaking local development.
*   **Secure Handshake**: Utilizes a versioned bi-directional handshake to verify client integrity and authentication tokens before promoting the connection to a processing state.

### Performance & UX
*   **Global Hotkeys**: Control recording (Default: `Ctrl+Alt+W`) system-wide from any application.
*   **Low-Latency Streaming**: Streams raw PCM audio chunks in real-time.
*   **Smart Auto-Paste**: Automatically types the transcription into your active window.
*   **Single-Instance Lock**: Uses a Windows Mutex to ensure only one client instance runs at a time (preventing mic conflicts).
*   **Auto-Reconnect**: Seamlessly handles connection drops and re-authenticates on demand.
*   **Auto Paste**: Automatically pastes the transcription into your active window text field.

## Getting Started

### 1. Prerequisites
- **Python 3.8+**
- **PortAudio**: Usually included with pip wheels.
  - *Linux*: `sudo apt install libportaudio2`

### 2. Installation - Linux/Windows/MacOS

After making sure you are in the client dir:
```bash
cd client
```
Create a virtual environment and install dependencies:
```bash
python -m venv venv

# Windows
.\venv\Scripts\Activate.ps1
# Linux/Mac
source venv/bin/activate

pip install -r requirements.txt
```

### 3. Launch & Configuration
Simply start the client. If it’s your first time, the interactive wizard will guide you through server setup and microphone selection:
```bash
python whisper_client.py
# or
python whisper_client.py --setup
```
*   **API Key**: You will be prompted for your API Key, which is then stored securely in your OS Enclave.
*   **Hardware**: Select your microphone device and hotkey during prompts.
*   **Ready**: Once you see "Client Ready", press (Default: **Ctrl+Alt+W**) to start dictating.

## CLI Options

| Flag | Description |
| :--- | :--- |
| `--setup` | Re-run the interactive setup wizard (Mic/Host selection). |
| `--clear-key` | Wipe the stored API key from the OS keyring. |
| `--health` | Perform a pre-flight health check on the backend. |
| `--version` | Display current client version. |

**Example:**
```bash
# Force re-configure audio device
python whisper_client.py --setup
```

## Troubleshooting

*   **Manual Edits**: If you prefer manual configuration, you can edit the `.env` file created after the first run.
*   **Auth Reset**: If the server rejects your key, use `--clear-key` to reset it.
*   **Linux/Wayland**: Global hotkeys may require X11 or specific compositor permissions.
