# WhisperDoc - Speech-to-Text System

A minimal but production-ready speech-to-text system that combines faster-whisper GPU acceleration with a clean client-server architecture.

## Prerequisites

Before starting, ensure your system meets the following requirements:

### Standard Requirements
- **Linux/Ubuntu** (Tested on Ubuntu 22.04/24.04)
- **Python 3.8+** and `pip`
- **Docker** and **Docker Compose**

### GPU Requirements (Optional, but Recommended)
For high-performance transcription, an NVIDIA GPU is required:
- **NVIDIA Drivers** (Run `nvidia-smi` to verify)
- **NVIDIA Container Toolkit**: Required for Docker to access the GPU.
  - [Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  - After installing, run: `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`

## Quick Start

### Option 1: Automated Setup (Recommended)

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
4. **Verify**:
   ```bash
   # Test the API from your local machine
   python3 test_api.py --health-only
   ```

### Option 2: Manual Setup

1. **Configure Environment**
   ```bash
   # Create .env file from template
   cp .env.template .env
   
   # Install local dependencies (Terminal Client & Dev Tools)
   pip install -r requirements.txt
   pip install -r client/requirements.txt
   ```

2. **Start the Backend API**
   ```bash
   # Build and start the backend service
   docker compose build whisper-backend
   docker compose up -d whisper-backend
   ```

3. **Test the API**
   ```bash
   # Use the integrated backend tests
   cd backend
   python tests/test_api.py --health-only
   
   # Test transcription with an audio file
   python tests/test_api.py --file ../assets/jfk.flac --verbose
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


## Testing Strategy

The project uses a two-category testing strategy:

### 1. Integration & Protocol Tests
These tests verify the public-facing API and the WebSocket handshake protocol. They can be run against a live server.

**Location**: `backend/tests/test_api.py`, `backend/tests/test_websocket.py`

```bash
# Run from within the backend directory
cd backend

# Test the HTTP API
python tests/test_api.py --health-only

# Test the WebSocket Handshake and Streaming
# Requires a running server at localhost:9989
python tests/test_websocket.py
```

### 2. Logic & Hardware Tests (PyTest)
These tests check internal components and verify GPU/CPU availability.

**Location**: `backend/tests/test_backend_logic.py`, `backend/tests/test_whisper.py`

```bash
cd backend

# Run the full test suite (Zero-Config)
pytest

# To verify GPU hardware specifically:
python tests/test_whisper.py
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

## Troubleshooting

### Error: "unknown or invalid runtime name: nvidia"
This means Docker cannot find the NVIDIA runtime.
1. Ensure the **NVIDIA Container Toolkit** is installed.
2. Configure Docker to use the toolkit:
   ```bash
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```
3. If you do not have a GPU, remove `runtime: nvidia` from `docker-compose.yml` and change `MODEL_DEVICE` to `cpu` in your `.env` file.

## Next Steps (Future Phases)

See `spec.md` for detailed specifications on upcoming features.

- **Phase 2: WebSocket Streaming [COMPLETED]**
- **Phase 4: Windows Client [IN PROGRESS]**
- **Phase 5: Dynamic Model Loading [COMPLETED]**

