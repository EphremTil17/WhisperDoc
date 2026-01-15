# WhisperDoc - Speech-to-Text System
A minimal, **secure**, and production-ready speech-to-text system. It combines `faster-whisper` GPU acceleration with a clean client-server architecture, featuring a **read-only container runtime** and a modern flutter client application for hassle free auto-pasting transcription.

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
   *  First make sure to have a python virtual environment activated
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   # Run the setup script to check dependencies and create config files
   ./setup.sh
   ```
3. **Build and Start**:
   ```bash
   # Build and start the backend service
   sudo docker compose build whisper-backend
   sudo docker compose up -d whisper-backend
   ```
4. **Secure the .env file**
   ```bash
   chmod 600 .env
   ```
### Option 2: Manual Setup - Windows/MacOS/Linux
1. **Configure Environment**

   ```bash
   *  First make sure to have a python virtual environment activated in powershell
   # Create .env file from template and make sure to secure it by making it read-only
   cp backend/.env.template .env
   python3 -m venv venv
   .\venv\Scripts\Activate.ps1
   
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
- `GET /ws` - WebSocket connection (JSON handshake with token required)

## Architecture
- **Backend Core**: Dockerized FastAPI server with `faster-whisper` GPU acceleration, operating within a **read-only container runtime** for maximum enclosure security.
- **Zero-Trust Modular Design**: Refactored into specialized domains to prevent lateral complexity:
    - **Engine**: Pure AI Orchestration with intelligent dynamic VRAM management (unloads model after 30m idle).
    - **Security**: Advanced IP-Level Governance featuring an automated **Active Defense Circuit Breaker** to mitigate flood attacks and protocol violations.
    - **Protocol**: Rigid WebSocket state machine enforcing identity verification before any data processing occurs.
- **Dual-Door Authentication & Secure Enclave**: Hybrid security supporting local static keys (Door #1) and OIDC/JWT providers (Door #2). Python clients further secure these keys via system-level OS enclaves (`keyring`).
- **Secure Handshake & Versioning**: Utilizes a versioned bi-directional handshake to verify client/server parity and identity before promoting a connection to active status.
- **Centralized Sanitized Logging**: High-performance logging with built-in **Incognito Mode (Ghost Mode)** for in-memory processing and automated server-side trace redaction.
- **Fail-Secure Transaction Integrity**: Implements deterministic cleanup of all temporary audio assets via `finally` blocks, ensuring zero disk persistence post-transcription.

## Configuration
WhisperDoc is entirely configuration-driven via the `.env` file. These variables are passed to the backend during startup.

### Core Settings
| Variable | Description | Default |
|----------|-------------|---------|
| `API_PORT` | Port the backend server will listen on. | `9989` |
| `MODEL_NAME` | Whisper model (e.g., `tiny.en`, `medium.en`). | `medium.en` |
| `MODEL_DEVICE` | Hardware allocation (`cuda` or `cpu`). | `cuda` |
| `LOG_LEVEL` | Logging verbosity (DEBUG, INFO, SUCCESS). | `INFO` |

### Security & Hardening Config Variables (Refer to `backend/.env.template`)

## Docker Commands
```bash
# View logs of the main backend service
docker compose logs -f whisper-backend

# Stop all services
docker compose down

# Rebuild and restart the backend after changes
docker compose build whisper-backend && docker compose up -d --force-recreate whisper-backend
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

### Python Terminal Client

A secure, modular, and production-ready terminal client for high-performance dictation. 

*   **Secure API Key Storage** (OS Enclave)
*   **Fail-Secure Handshake**
*   **Auto Copy/Paste**
*   **Automated First-Time Setup**
*   **Incognito Mode** (Ghost Mode)

📖 **[Terminal Client Documentation](client/README.md)**

## Common Troubleshooting

### Error: "Read-only file system"
This is expected behavior if you try to open a shell and write to root. The container is locked down. Write to `/tmp` if strictly necessary for testing.

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
| Phase 7 | Infrastructure Hardening | ✅ Complete |
| Phase 8 | Client and Backend Hardening | ✅ Complete |

