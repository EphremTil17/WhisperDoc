# WhisperDoc - Speech-to-Text System v2.23.2

A high-performance, **multi-layered secure**, and production-ready speech-to-text system. It features a **pluggable multi-engine ASR architecture** (faster-whisper, NVIDIA Parakeet) with GPU acceleration within a **hardened, read-only enclosure**, paired with modern, zero-trust client applications for seamless, identity-verified dictation.

<img width="3375" height="3363" alt="WhisperDoc Github Preview" src="https://github.com/user-attachments/assets/c2c3037a-171c-42dc-a3e6-e72b8ef94d09" />

## Demo Video:

https://github.com/user-attachments/assets/906170ee-6d2a-4bf5-a881-926f03e0862a

## Prerequisites

Before starting, ensure your system meets the following requirements:

### Standard Requirements

- **Linux/Ubuntu** (Tested on Ubuntu 22.04/24.04) for automated setup
- **Windows/MacOS/Linux** for manual setup
- **Python 3.10+** and [uv](https://docs.astral.sh/uv/) (or `pip`)
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
   - First make sure to have a python virtual environment activated
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
   # Create .env file from template and secure it
   cp backend/.env.template .env
   chmod 600 .env   # Linux/Mac only

   # (Optional) Set ASR_ENGINE=whisper or ASR_ENGINE=parakeet in .env
   ```

2. **Build and Start the Backend** (Docker handles all backend dependencies)

   ```bash
   # Build and start — automatically selects the correct Dockerfile
   # based on the ASR_ENGINE value in your .env (default: whisper)
   docker compose build whisper-backend
   docker compose up -d whisper-backend
   ```

3. **(Optional) Local Client Setup**

   ```bash
   # Only needed if running the Python terminal client locally
   python3 -m venv venv
   source venv/bin/activate          # Linux/Mac
   # .\venv\Scripts\Activate.ps1     # Windows PowerShell

   pip install uv
   uv pip install -r terminal_client/requirements.txt
   ```

4. **Test the API**
   You can run the test suite locally or directly inside the running Docker container.

**Run Inside Docker (Recommended):**

```bash
# Run all tests inside the active container
docker compose exec whisper-backend python3 -m pytest tests/

# To run a specific test file:
docker compose exec whisper-backend python3 -m pytest tests/test_api.py
```

**Run Locally:**

```bash
# Requires a local venv with backend/requirements.txt installed
pytest backend/tests
```

**API Endpoints:**

- `GET /health` - Check API status and model readiness
- `POST /transcribe` - Upload audio file for transcription
- `POST /log` - Ingest a batch of logs from a remote client
- `GET /ws` - WebSocket connection (JSON handshake with token required)

## 🛡️ Architecture & Security Deep-Dive (Hardened v2.14.0)

- **Backend Core**: Dockerized FastAPI server with a **pluggable ASR engine layer** (faster-whisper, NVIDIA Parakeet) and GPU acceleration, operating within a **read-only container runtime** for maximum enclosure security.
  WhisperDoc v2.13.0 represents a significant leap in enterprise-grade security, moving beyond simple API keys to a comprehensive **Zero-Trust Identity Federation**.

### 1. Identity Federation & Cryptographic Hardening

- **OIDC with PKCE (Zitadel)**: Transitioned to industry-standard OAuth2 with **Proof Key for Code Exchange (PKCE)**. The system enforces strict identity verification via **Asymmetrical RS256 signing**.
- **Cryptographic Mathematical Verification**: The implementation has been rigorously audited and mathematically verified to reject **Algorithm Confusion attacks** (HS256) and `none` algorithm bypass attempts.
- **System Browser Integration**: OIDC flows are executed via the native system browser, leveraging the OS's existing security posture and preventing "In-App Webview" credential interception.

### 2. The "Handshake Cage" Protocol

- **Strict Sequencing**: A rigid WebSocket state machine that prevents any data processing or audio ingestion until a valid handshake is acknowledged.
- **Server-Side Enforcement**: The backend is hardened to immediately drop and black-list IPs that attempt to stream audio before a successful identity verification.

### 3. Native Instance Integrity (Single Instance Mutex)

- **Win32 Named Mutex**: Implemented a native Windows Mutex (`WhisperDocSingleInstanceMutex`) to ensure only one instance of the application is active.
- **Resource Protection**: This prevents critical resource contention on global hotkeys and microphone handles, ensuring a deterministic and stable environment during system sleep/wake cycles.

### 4. Active Defense & Infrastructure Hardening

- **Circuit Breaker Circuitry**: An automated **Active Defense** system that issues `1008 (Policy Violation)` codes to clients attempting flood attacks or protocol violations.
- **Read-Only Enclosure**: The backend operates in a strictly **read-only container runtime**, making the environment resistant to unauthorized filesystem modifications.
- **Dynamic VRAM Scaling**: Intelligent engine orchestration that unloads models from VRAM after periods of inactivity, optimizing performance for multi-tenant GPU environments.

### 5. Privacy-First (Ghost Mode)

- **Incognito State**: Protocol-level privacy flag that redacts server-side logs and enforces zero-disk persistence, ensuring that sensitive transcriptions leave no trace in backend telemetry.

### 6. "Weight Shedding" & Performance (v2.14.0)

- **Digital Liposuction (Docker Slimming)**: Reduced image size and build complexity by implementing **Static FFmpeg** binaries and **CPU-only PyTorch** foundations. Faster-Whisper continues to use GPU-accelerated `ctranslate2` independently, resulting in a ~40% reduction in production image footprint.
- **High-Performance Infrastructure**: Integrated **uvloop** (high-speed C-based event loop) and **orjson** (sub-millisecond JSON serialization) to minimize I/O latency and CPU overhead during heavy concurrency.
- **Memory Hygiene (malloc_trim)**: Aggressive RAM reclamation using `malloc_trim` to force the Linux kernel to reclaim heap memory immediately after models are unloaded from VRAM.
- **Drift-Proof Security Tracking**: Re-engineered the security maintenance loop to be time-interval based rather than clock-modulo based, ensuring robust IP-ban cleanup regardless of event-loop timing.

### 7. Error Handling & Update Controls

- **Standardized 1008 Rejections**: Full support for the backend's JSON-to-Close protocol, ensuring descriptive error messages for bans or version mismatches.
- Added **Profile-Based Logic** to prevent "Update Available" notifications from appearing during active transcription sessions and Ensures that if a security patch is available, the user is immediately notified and blocked from using the service until updated.

## Configuration

WhisperDoc is entirely configuration-driven via the `.env` file. These variables are passed to the backend during startup.

### Core Settings

| Variable       | Description                                        | Default          |
| -------------- | -------------------------------------------------- | ---------------- |
| `ASR_ENGINE`   | ASR backend (`whisper` or `parakeet`).             | `whisper`        |
| `API_PORT`     | Port the backend server will listen on.            | `9989`           |
| `MODEL_NAME`   | Whisper model (e.g., `tiny.en`, `large-v3-turbo`). | `large-v3-turbo` |
| `MODEL_DEVICE` | Hardware allocation (`cuda` or `cpu`).             | `cuda`           |
| `LOG_LEVEL`    | Logging verbosity (DEBUG, INFO, SUCCESS).          | `INFO`           |

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

### ASR Engine Benchmarks

Benchmarks from the [Open ASR Leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard) on standardized evaluation datasets:

| Engine | Model | WER (%) ↓ | RTFx ↑ | Language | VRAM (fp16) |
|--------|-------|-----------|--------|----------|-------------|
| **Parakeet** | `nvidia/parakeet-tdt-0.6b-v2` | **6.05** | **3,386** | English | ~2.4 GB |
| **Whisper** | `openai/whisper-large-v3-turbo` | 7.83 | 200 | Multilingual | ~3.5 GB |

- **WER** (Word Error Rate): Lower is better. Parakeet achieves 23% lower WER than Whisper Turbo.
- **RTFx** (Real-Time Factor): Higher is better. Parakeet is ~17x faster than Whisper Turbo due to its non-autoregressive TDT architecture.
- Both engines run in **float16** precision with negligible accuracy loss vs float32.

> **Research to watch**:
> - [LiteASR](https://github.com/efeslab/LiteASR) (EMNLP 2025) — PCA-based encoder compression that reduces Whisper encoder size by ~33-40% with near-zero WER degradation. Currently requires HuggingFace Transformers inference (no CTranslate2 or NeMo support), but if CTranslate2 adds low-rank layer support, this could meaningfully reduce VRAM for the Whisper engine.
> - [CrisperWhisper](https://github.com/nyrahealth/CrisperWhisper) (INTERSPEECH 2024) — Fine-tuned Whisper Large v3 for verbatim transcription (6.66% avg WER vs 7.7% for standard v3) with filler detection (`[UM]`, `[UH]`) and hallucination mitigation. An official [CTranslate2 conversion](https://huggingface.co/nyrahealth/faster_CrisperWhisper) exists for faster-whisper, though word-level timestamp precision degrades outside their custom pipeline. Licensed CC-BY-NC-4.0 (non-commercial only).

### Infrastructure

- **Model Loading**: First time is slow (downloads model). Subsequent starts are fast due to caching in the `./model-cache` directory.
- **Transcription**: ~1s for a 10-second audio file on an RTX 3060TI.
- **GPU Acceleration**: CUDA-enabled for faster processing using the `ctranslate2` engine (Whisper) or native PyTorch (Parakeet).
- **Weight Efficiency**: Multi-stage build with aggressive layer pruning of static libraries and bytecode to ensure a minimal runtime environment.

## Clients

### Flutter Client (Windows) v2.23.2

A high-performance Windows desktop application built with a **Smart Modular Architecture**. Features include:

- **Zero-Latency Recording**: Parallelized initialization of audio capture and transport layers for instant dictation.
- **Enterprise Security**: Windows Credential Manager enclave storage, Encrypted local history (AES-256), and automated JWT expiry warnings.
- **Handshake Cage Protocol**: Native implementation of the buffer-then-flush security strategy to ensure zero-data leakage before identity verification.
- **Native System Integration**: Single-instance enforcement via Win32 Named Mutex and deep-sleep resilient global hotkeys.
- **Privacy Core**: Integrated **Incognito Mode** with explicit memory hygiene and protocol-level log redaction.
- **Verification Suite**: Bundled security tests validating PKCE cryptographic integrity and state-parameter protection.

📖 **[Flutter Client Documentation](flutter_client/README.md)**

### Python Terminal Client v2.23.2

A secure, modular, and production-ready terminal client for high-performance dictation.

- **Secure API Key Storage** (OS Enclave)
- **Active Defense Awareness** (Handles 1008 Ban states)
- **Fail-Secure Handshake**
- **Auto Copy/Paste**
- **Automated First-Time Setup**
- **Incognito Mode** (Ghost Mode)

📖 **[Terminal Client Documentation](terminal_client/README.md)**

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

| Phase    | Description                                            | Status         |
| -------- | ------------------------------------------------------ | -------------- |
| Phase 1  | Core Backend & REST API                                | ✅ Complete    |
| Phase 2  | WebSocket Streaming                                    | ✅ Complete    |
| Phase 3  | Robust Dev Terminal Client                             | ✅ Complete    |
| Phase 4  | Flutter Windows Client                                 | ✅ Complete    |
| Phase 5  | Dynamic Model Loading                                  | ✅ Complete    |
| Phase 6  | Architecture Refactoring                               | ✅ Complete    |
| Phase 7  | Infrastructure Hardening                               | ✅ Complete    |
| Phase 8  | Client and Backend Hardening                           | ✅ Complete    |
| Phase 9  | OIDC Identity Hardening & Verification Suite (v2.13.0) | ✅ Complete    |
| Phase 10 | Optimization and Weight Shedding (v2.14.0)             | ✅ Complete    |
| Phase 11 | Error Handling & Update Controls (v2.20.0)             | ✅ Complete    |
| Phase 12 | UI and Functional Improvements                         | 🚧 In Progress |
| Phase 13 | Multi-Engine ASR Abstraction (v2.23.0)                 | ✅ Complete    |
