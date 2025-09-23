# WhisperDoc - Speech-to-Text System

A minimal but production-ready speech-to-text system that combines faster-whisper GPU acceleration with a clean client-server architecture.

## Quick Start

### Option 1: Automated Setup (Recommended)

```bash
# Run the setup script to install dependencies and create config files
./setup.sh

# Build and start the backend service
sudo docker compose build whisper-backend
sudo docker compose up -d whisper-backend

# Test the API from your local machine
python3 test_api.py --health-only
```

### Option 2: Manual Setup

1. **Configure Environment**
   ```bash
   # Create .env file
   cp .env.template .env
   
   # Install local dependencies for testing
   pip install -r requirements.txt
   ```

2. **Start the Backend API**
   ```bash
   # Build and start the backend service
   sudo docker compose build whisper-backend
   sudo docker compose up -d whisper-backend
   
   # Check if it's running
   sudo docker compose ps
   ```

3. **Test the API**
   ```bash
   # Test health endpoint from your local machine
   python3 test_api.py --health-only
   
   # Test transcription with an audio file
   python3 test_api.py --file your_audio.wav --verbose
   ```

**API Endpoints:**
- `GET /health` - Check API status and model readiness
- `POST /transcribe` - Upload audio file for transcription
- `POST /log` - Ingest a batch of logs from a remote client
- `GET /ws` - WebSocket connection for real-time streaming

## Architecture

- **Backend**: Docker containerized FastAPI server with `faster-whisper` and CUDA acceleration.
- **API**: RESTful HTTP and WebSocket endpoints.
- **Configuration-Driven**: The entire system is configured via a central `.env` file. This includes ports, model names, and log levels. There are no hardcoded values.
- **Persistent Model Caching**: The `faster-whisper` model is downloaded on the first run and then cached in the `./model-cache` directory on the host machine, preventing re-downloads on subsequent starts.
- **Centralized Logging**: The system uses `loguru` for structured, colorful logging. All logs are standardized to UTC. A `POST /log` endpoint allows any client to send a batch of logs to the server for centralized storage and analysis. Client-side loggers are designed to be asynchronous, sending batches in the background to ensure high performance.

## Project Structure
```
WhisperDoc/
├── README.md
├── spec.md
├── docker-compose.yml
├── setup.sh
├── requirements.txt
├── test_api.py
├── test_websocket.py
├── backend/
│   ├── Dockerfile
│   ├── api_server.py
│   └── logging_config.py
└── tests/
    ├── test_logging.py
    └── test_whisper.py
```

## Testing Strategy

The project uses a two-category testing strategy:

### 1. API / End-to-End Tests
These tests act as external clients to verify the public-facing API. They should be run from your **local machine** against the running backend container.

**Test Files:** `test_api.py`, `test_websocket.py`

```bash
# Ensure you have installed local dependencies
# pip install -r requirements.txt

# Test the HTTP API and remote logging (health check)
python3 test_api.py --health-only

# Test transcription and remote logging
python3 test_api.py --file assets/jfk.flac --verbose

# Test the WebSocket echo server
python3 test_websocket.py
```

### 2. Internal / Unit Tests
These tests check the internal functionality of backend components. They are run inside dedicated Docker services to provide the correct environment.

**Test Files:** `tests/test_whisper.py`, `tests/test_logging.py`

```bash
# Run the internal whisper model test using its dedicated service
sudo docker compose run --rm whisper-test

# Run the internal logging test against the running backend service
sudo docker compose exec whisper-backend python3 -m tests.test_logging
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

## Next Steps (Future Phases)

See `spec.md` for detailed specifications on upcoming features.

- **Phase 2: WebSocket Streaming**
- **Phase 4: Windows Client**
- **Phase 5: Dynamic Model Loading**

