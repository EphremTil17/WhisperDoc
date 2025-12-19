# WhisperDoc Client

A lightweight Python client for real-time dictation using the WhisperDoc backend.

## Features
- **Global Hotkeys**: Start/Stop recording from any application.
- **Auto-Paste**: Automatically copies transcription to clipboard and pastes it (`Ctrl+V`) or types it into the active text box.
- **Streaming**: Streams audio chunks to the server as you speak for low-latency processing.
- **Cross-Platform**: Works on Windows and Linux (X11).

## Setup

1. **Install PortAudio** (Required for `sounddevice`):
   - **Ubuntu/Debian**: `sudo apt install libportaudio2 python3-pyaudio`
   - **Windows**: Included in the pip package.

2. **Install Python Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure**:
   ```bash
   cp .env.template .env
   # Edit .env to set your server URI and preferred hotkey
   ```

## Usage

1. **Start the backend server** (ensure Docker is running):
   ```bash
   sudo docker compose up -d whisper-backend
   ```

2. **Run the client**:
   ```bash
   python whisper_client.py
   ```

3. **List Audio Devices** (if the default mic isn't working):
   ```bash
   python whisper_client.py --list-devices
   ```

4. **Dictate**:
   - Press the hotkey (default: `Ctrl+Alt+R`) to start recording.
   - Speak clearly.
   - Press the hotkey again to stop and paste the text.

## Troubleshooting

- **Linux/Wayland**: Global hotkeys and typing simulation may be restricted. Use an X11 session for best results.
- **Microphone issues**: Check `AUDIO_DEVICE_ID` in `.env` if the app picks the wrong microphone.
