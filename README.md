# WhisperDoc - Speech-to-Text System
A minimal but production-ready speech-to-text system that combines faster-whisper GPU acceleration with a clean client-server architecture.

## Prerequisites
Before starting, ensure your system meets the following requirements:

### Standard Requirements
- **Linux/Ubuntu** (Tested on Ubuntu 22.04/24.04) for automated setup
- **Windows/MacOS/Linux** for manual setup
- **Python 3.8+** and `pip`
- **Docker** and **Docker Compose**

### GPU Requirements (Optional, but Recommended)
For high-performance transcription, an NVIDIA GPU is required:
- **NVIDIA Drivers** (Run `nvidia-smi` to verify)
- **NVIDIA Container Toolkit**: Required for Docker to access the GPU.
  - [Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  - After installing, run: `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`

## Quick Start

### Option 1: Automated Setup (Recommended) - Linux Only
1. **Check Prerequisites**: Ensure Docker and (optionally) NVIDIA drivers are installed.
2. **Run Setup**:
   ```bash
   # Run the setup script to check dependencies and create config files
   ./setup.sh
   ```
3. **Build and Start**:
   ```bash
   # Build and start the backend service
   sudo docker compose build whisper-backend
   sudo docker compose up -d whisper-backend
   ```
### Option 2: Manual Setup - Windows/MacOS/Linux
1. **Configure Environment**
   ```bash
   # Create .env file from template
   cp backend/.env.template .env
   
   # Install local dependencies (Terminal Client & Dev Tools)
   pip install -r backend/requirements.txt
   pip install -r client/requirements.txt
   ```

2. **Start the Backend API**
   ```bash
   # Build and start the backend service
   docker compose build whisper-backend
   docker compose up -d whisper-backend
   ```

3. **Test the API**

You can run the test suite locally or directly inside the running Docker container.

**Run Locally:**
```bash
# Ensure you are using the backend venv and have all dependencies
pytest backend/tests
```
**Run Inside Docker (Recommended for Environment Consistency):**
```bash
# Run all tests inside the active container
docker compose exec whisper-backend pytest tests/

# To run a specific test file:
docker compose exec whisper-backend pytest tests/test_api.py
```


**API Endpoints:**
- `GET /health` - Check API status and model readiness
- `POST /transcribe` - Upload audio file for transcription
- `POST /log` - Ingest a batch of logs from a remote client
- `GET /ws` - WebSocket connection for real-time streaming

## Architecture
- **Backend**: Docker containerized FastAPI server with `faster-whisper` and CUDA acceleration.
- **Dynamic Resource Scaling**: The backend includes an intelligent `ModelManager` that unloads the Whisper model from VRAM after 30 minutes of inactivity to save GPU resources, and reloads it instantly on demand.
- **Session-Based WebSockets**: Connections are established only when recording starts and are automatically closed after 5 minutes of idle time.
- **Protocol Handshake**: A versioned `hello` event system ensures clients and server are synchronized on versioning and readiness states before data starts flowing.
- **Centralized Logging**: The system uses `loguru` for structured, colorful logging. All logs are standardized to UTC. A `POST /log` endpoint allows any client (Flutter/Python) to send a batch of logs to the server.
- **Decoupled Requirements**: Dependencies are split into modular `requirements.txt` files (backend, client, tests) to minimize bloat on client machines.

## Configuration
The system is entirely configuration-driven via the `.env` file in the root directory.

| Variable | Description | Default |
|----------|-------------|---------|
| `API_PORT` | The port the backend server will listen on. | `9989` |
| `MODEL_NAME` | The Whisper model to use (e.g., `tiny.en`, `base.en`, `medium.en`). | `medium.en` |
| `MODEL_DEVICE` | Hardware to run on (`cuda` for GPU, `cpu` for CPU). | `cuda` |
| `MODEL_COMPUTE_TYPE` | Precision level (`float16` for GPU, `int8` for CPU). | `float16` |
| `LOG_LEVEL` | Verbosity of the logs (`DEBUG`, `INFO`, `WARNING`, `ERROR`). | `INFO` |

To change these values, edit your `.env` file and restart the container:
```bash
docker compose up -d --force-recreate whisper-backend
```

## Docker Commands
```bash
# View logs of the main backend service
sudo docker compose logs -f whisper-backend

# Stop all services
sudo docker compose down

# Rebuild and restart the backend after changes
sudo docker compose build whisper-backend && sudo docker compose up -d --force-recreate whisper-backend
```
## Performance
- **Model Loading**: First time is slow (downloads model). Subsequent starts are fast due to caching in the `./model-cache` directory.
- **Transcription**: ~1s for a 10-second audio file on an RTX 3060TI.
- **GPU Acceleration**: CUDA-enabled for faster processing.

## Clients

### Flutter Client (Windows)

A native Windows desktop application with a modern glassmorphic UI. Features include:
- **Global Hotkey** for hands-free recording (default: Ctrl+Alt+E)
- **Deep Sleep Resilience** - Hotkeys work reliably even after system sleep
- **Auto Copy/Paste** - Transcriptions go straight to your cursor
- **Incognito Mode** - Temporarily disable history recording

📖 **[Flutter Client Documentation](flutter_client/README.md)**

```bash
cd flutter_client
flutter pub get
flutter run -d windows
```

### Python Terminal Client

A lightweight terminal-based client for quick testing and scripting.

```bash
cd client
pip install -r requirements.txt
python whisper_client.py
```

## Common Troubleshooting

### Error: "unknown or invalid runtime name: nvidia"
This means Docker cannot find the NVIDIA runtime.
1. Ensure the **NVIDIA Container Toolkit** is installed.
2. Configure Docker to use the toolkit:
   ```bash
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```
3. If you do not have a GPU, remove `runtime: nvidia` from `docker-compose.yml` and change `MODEL_DEVICE` to `cpu` in your `.env` file.

## Project Phases

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Core Backend & REST API | ✅ Complete |
| Phase 2 | WebSocket Streaming | ✅ Complete |
| Phase 3 | Terminal Client | ✅ Complete |
| Phase 4 | Flutter Windows Client | ✅ Complete |
| Phase 5 | Dynamic Model Loading | ✅ Complete |
| Phase 6 | Architecture Refactoring | ✅ Complete |
