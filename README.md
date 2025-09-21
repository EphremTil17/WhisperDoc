# WhisperDoc - Speech-to-Text System

A minimal but production-ready speech-to-text system that combines faster-whisper GPU acceleration with a clean client-server architecture.

## Quick Start

### Option 1: Automated Setup (Recommended)

```bash
# Run the setup script
./setup.sh

# Follow the instructions to build and start
sudo docker compose build whisper-backend
sudo docker compose up -d whisper-backend

# Test the API
python3 test_api.py --health-only
```

### Option 2: Manual Setup

1. **Configure Environment**
   ```bash
   # Copy environment template
   cp .env.example .env
   
   # Edit configuration (optional)
   nano .env
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
   # Test health endpoint
   python3 test_api.py --health-only
   
   # Test transcription with an audio file
   python3 test_api.py --file your_audio.wav --verbose
   
   # Test with curl
   curl http://localhost:9989/health
   curl -X POST -F "file=@your_audio.wav" http://localhost:9989/transcribe
   ```

## Current Status

### ✅ **Phase 1: Backend Core (COMPLETED)**
- [x] Docker CUDA environment with faster-whisper
- [x] FastAPI server with `/health` and `/transcribe` endpoints  
- [x] GPU acceleration verified (CUDA support)
- [x] HTTP API endpoints working
- [x] Model: medium.en loaded successfully (~62s initial load)
- [x] Test client with CLI arguments support

**API Endpoints:**
- `GET /health` - Check API status and model readiness
- `POST /transcribe` - Upload audio file for transcription

**Supported Audio Formats:** WAV, MP3, M4A, FLAC, OGG

## Architecture

- **Backend**: Docker containerized FastAPI server with faster-whisper + CUDA
- **API**: HTTP endpoints for health checks and file transcription
- **Model**: Whisper medium.en optimized for GPU acceleration
- **Port**: 9989

## Testing

### Test Client Usage
```bash
# Health check only
python3 test_api.py --health-only

# Transcribe audio file
python3 test_api.py --file audio.wav

# Verbose output with detailed logs
python3 test_api.py --file audio.wav --verbose

# Custom API endpoint
python3 test_api.py --url http://localhost:9989 --file audio.wav
```

### Docker Commands
```bash
# View logs
sudo docker compose logs -f whisper-backend

# Stop the service
sudo docker compose down

# Rebuild after changes
sudo docker compose build whisper-backend
sudo docker compose up -d whisper-backend
```

## Performance

- **Model Loading**: ~62 seconds (one-time on startup)
- **Transcription**: ~0.6s for 3-second audio file
- **GPU Acceleration**: CUDA-enabled for faster processing
- **Memory**: Optimized for RTX 3060TI (8GB VRAM)

## Next Steps (Future Phases)

### **Phase 2: WebSocket Streaming (Planned)**
- [ ] Add WebSocket endpoint for real-time streaming
- [ ] Implement chunked audio processing
- [ ] Add push-to-talk session management

### **Phase 3: Windows Client (Planned)**
- [ ] PyQt6 floating window UI
- [ ] Global hotkey registration (PTT functionality)
- [ ] Real-time audio capture with sounddevice
- [ ] System tray integration
- [ ] Audio recording storage (last 10 files)

## Development

### Project Structure
```
WhisperDoc/
├── README.md                    # This file
├── docker-compose.yml           # Docker orchestration
├── test_api.py                  # API test client
├── backend/                     # Containerized transcription service
│   ├── Dockerfile              # CUDA + faster-whisper + FastAPI
│   ├── api_server.py           # FastAPI server (main file)
│   └── test_whisper.py         # Original GPU validation script
└── assets/                     # Audio files storage
```

### Requirements
- Docker with NVIDIA runtime support
- CUDA-compatible GPU (tested on RTX 3060TI)
- Python 3 with requests library (for test client)

## API Response Format

### Health Check Response
```json
{
  "status": "healthy",
  "model_loaded": true,
  "device": "cuda",
  "timestamp": 1758441478.17
}
```

### Transcription Response
```json
{
  "text": "Your transcribed text here",
  "language": "en",
  "language_probability": 1.0,
  "duration": 3.0,
  "segments": [
    {
      "start": 0.0,
      "end": 2.0,
      "text": "Your transcribed text here"
    }
  ],
  "processing_time": 0.64,
  "timestamp": 1758441478.17
}
```

---

**Status**: ✅ **Phase 1 Complete** - Working backend API with GPU acceleration
