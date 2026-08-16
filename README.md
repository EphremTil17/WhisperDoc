# WhisperDoc - Speech-to-Text System v2.24.8

A high-performance, **multi-layered secure**, and production-ready speech-to-text system. It features a **pluggable multi-engine ASR architecture** (faster-whisper, NVIDIA Parakeet) with GPU acceleration within a **hardened, read-only enclosure**, paired with modern, zero-trust client applications for seamless, identity-verified dictation.

<img width="3375" height="3363" alt="WhisperDoc Github Preview" src="https://github.com/user-attachments/assets/c2c3037a-171c-42dc-a3e6-e72b8ef94d09" />

## Demo Video:

https://github.com/user-attachments/assets/906170ee-6d2a-4bf5-a881-926f03e0862a

## Prerequisites

Before starting, ensure your system meets the following requirements:

### Standard Server Requirements

- **Linux/Ubuntu** (Tested on Ubuntu 22.04/24.04) for automated setup
- **Windows/MacOS/Linux** for manual setup
- **Python 3.10+** and [uv](https://docs.astral.sh/uv/)
  - Use **Python 3.12** for local backend development (`backend/pyproject.toml`)
- **Docker** and **Docker Compose**

### GPU Requirements (Optional, but Recommended)

For high-performance transcription, an NVIDIA GPU is required [VRAM>4GB]:

- **NVIDIA Drivers** (Run `nvidia-smi` to verify)
- **NVIDIA Container Toolkit**: Required for Docker to access the GPU.
  - [Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  - After installing, run: `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`

## Quick Start

### Option 1: Automated Setup (Recommended) - Linux Only

1. **Check Prerequisites**: Ensure Docker and (optionally) NVIDIA drivers are installed.
2. **Run Setup**:
   - First make sure to have a Python virtual environment activated
   ```bash
   uv venv
   source .venv/bin/activate
   # Run the setup script to choose a backend engine, sync the backend UV
   # environment, and create the root .env file from backend/.env.template
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

   # Choose whisper, parakeet_cpp, or legacy parakeet in .env.
   # parakeet_cpp also uses BACKEND_DOCKERFILE=Dockerfile.api and
   # COMPOSE_PROFILES=parakeet-cpp (setup.sh configures these together).
   ```

2. **Build and Start the Backend** (Docker handles all backend dependencies via native UV)

   ```bash
   # Build and start using BACKEND_DOCKERFILE from .env (default: Whisper).
   # The images install from backend/pyproject.toml + backend/uv.lock.
   # For parakeet_cpp, first provision its digest-verified model:
   uv run --project backend python backend/tools/provision_parakeet_cpp.py

   docker compose build whisper-backend
   docker compose up -d whisper-backend
   ```

   The experimental parakeet.cpp path requires these coordinated `.env`
   values (the interactive `setup.sh` writes them together):

   ```dotenv
   ASR_ENGINE=parakeet_cpp
   BACKEND_DOCKERFILE=Dockerfile.api
   COMPOSE_PROFILES=parakeet-cpp
   ```

3. **(Optional) Local Backend Setup** - Linux/WSL recommended

   ```bash
   cd backend

   # Choose exactly one engine extra for the local environment
   uv sync --group dev --extra whisper
   # or
   uv sync --group dev --extra parakeet
   # parakeet.cpp needs only the core API dependencies:
   uv sync --group dev
   ```

4. **(Optional) Local Terminal Client Setup**

   ```bash
   # Lightweight Windows fallback/debug client if the Flutter app is unavailable
   # (separate from the backend setup.sh flow)
   cd terminal_client
   uv sync --group dev
   ```

5. **Test the API**
   You can run the test suite locally or directly inside the running Docker container.

**Run Inside Docker (Recommended):**

```bash
# Run all tests inside the active container
docker compose exec whisper-backend python -m pytest tests/

# To run a specific test file:
docker compose exec whisper-backend python -m pytest tests/test_api.py
```

**Run Locally:**

```bash
cd backend

# Choose one engine extra first, then run the backend quality gates
uv sync --group dev --extra whisper
# or
uv sync --group dev --extra parakeet

uv run pyright .
uv run pytest tests
```

**Developer Recommendation: Install repo-wide pre-commit hooks**

```bash
# Install the shared hooks once from the repository root
uvx pre-commit install

# Run all configured hooks across the repo on demand
uvx pre-commit run --all-files
```

The shared pre-commit config runs Ruff separately for `backend/` and
`terminal_client/`, using each project's own `pyproject.toml`. The
`ruff` hook runs with `--fix`, then `ruff format` runs after it. If
files still need manual attention after auto-fixes, the commit fails.
If you're actively developing in this repository, install these hooks.

**API Endpoints:**

- `GET /health` - Check API status and model readiness
- `POST /transcribe` - Upload audio file for transcription
- `POST /log` - Ingest a batch of logs from a remote client
- `GET /ws` - WebSocket connection (JSON handshake with token required)

## 🛡️ Architecture & Security Deep-Dive (Hardened v2.14.0)

- **Backend Core**: Dockerized FastAPI server with a **pluggable ASR engine layer** (faster-whisper, isolated parakeet.cpp, or legacy NVIDIA NeMo) and GPU acceleration, operating within a **read-only container runtime** for maximum enclosure security.
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

### 7. Structured Error Codes & Update Controls

- **Structured Error Protocol**: All WebSocket error payloads include both a numeric `code` (for backwards compatibility) and a structured `error_code` string (e.g., `AUTH_FAILED`, `VERSION_OUTDATED`, `IP_BANNED`) for precise client-side error routing.
- **Standardized 1008 Rejections**: Full support for the backend's JSON-to-Close protocol, ensuring descriptive error messages for bans or version mismatches.
- Added **Profile-Based Logic** to prevent "Update Available" notifications from appearing during active transcription sessions and ensures that if a security patch is available, the user is immediately notified and blocked from using the service until updated.

## Configuration

WhisperDoc is entirely configuration-driven via the `.env` file. These variables are passed to the backend during startup.

### Core Settings

| Variable       | Description                                        | Default          |
| -------------- | -------------------------------------------------- | ---------------- |
| `ASR_ENGINE`   | ASR backend (`whisper`, `parakeet_cpp`, or legacy `parakeet`). | `whisper` |
| `BACKEND_DOCKERFILE` | API image (`Dockerfile.whisper`, `.api`, or `.parakeet`). | `Dockerfile.whisper` |
| `BACKEND_IMAGE_NAME` | Optional Docker image repository/name override. | `whisperdoc-backend` |
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

The table below contains published model-level figures and is not directly
comparable to end-to-end WhisperDoc latency. The local RTX 3060 Ti evaluation,
including HTTP overhead, VRAM, long-form behavior, and rejected approaches, is
recorded in [the parakeet.cpp benchmark report](backend/engine/PARAKEET_CPP_BENCHMARK.md).

Benchmarks from the [Open ASR Leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard) on standardized evaluation datasets:

| Engine       | Model                           | WER (%) ↓ | RTFx ↑    | Language     | VRAM (fp16) |
| ------------ | ------------------------------- | --------- | --------- | ------------ | ----------- |
| **Parakeet** | `nvidia/parakeet-tdt-0.6b-v2`   | **6.05**  | **3,386** | English      | ~2.4 GB     |
| **Whisper**  | `openai/whisper-large-v3-turbo` | 7.83      | 200       | Multilingual | ~3.5 GB     |

- **WER** (Word Error Rate): Lower is better. Parakeet achieves 23% lower WER than Whisper Turbo.
- **RTFx** (Real-Time Factor): Higher is better. Parakeet is ~17x faster than Whisper Turbo due to its non-autoregressive TDT architecture.
- Both engines run in **float16** precision with negligible accuracy loss vs float32.

> **Research to watch**:
>
> - [LiteASR](https://github.com/efeslab/LiteASR) (EMNLP 2025) — PCA-based encoder compression that reduces Whisper encoder size by ~33-40% with near-zero WER degradation. Currently requires HuggingFace Transformers inference (no CTranslate2 or NeMo support), but if CTranslate2 adds low-rank layer support, this could meaningfully reduce VRAM for the Whisper engine.
> - [CrisperWhisper](https://github.com/nyrahealth/CrisperWhisper) (INTERSPEECH 2024) — Fine-tuned Whisper Large v3 for verbatim transcription (6.66% avg WER vs 7.7% for standard v3) with filler detection (`[UM]`, `[UH]`) and hallucination mitigation. An official [CTranslate2 conversion](https://huggingface.co/nyrahealth/faster_CrisperWhisper) exists for faster-whisper, though word-level timestamp precision degrades outside their custom pipeline. Licensed CC-BY-NC-4.0 (non-commercial only).

### Infrastructure

- **Model Loading**: First time is slow (downloads model). Subsequent starts are fast due to caching in the `./model-cache` directory.
- **Transcription**: Engine-dependent; the local 9.16-second RTX 3060 Ti test measured 74.6 ms median end-to-end with parakeet.cpp and 319.4 ms with Whisper Turbo. See the linked benchmark report for methodology and limits.
- **GPU Acceleration**: CUDA-enabled using CTranslate2 (Whisper), parakeet.cpp/ggml in an isolated sidecar, or native PyTorch (legacy NeMo Parakeet).
- **Weight Efficiency**: Multi-stage build with aggressive layer pruning of static libraries and bytecode to ensure a minimal runtime environment.

## Clients

### Flutter Client (Windows) v2.24.8

A high-performance Windows desktop application built with a **Smart Modular Architecture**. Features include:

- **Groq Cloud Direct Transcription**: Backend-independent speech-to-text via Groq's `whisper-large-v3-turbo` REST API. Works as a standalone fallback when the backend is down, under maintenance, or by user preference. Free-tier compliant with local rate-limit tracking and conservative buffer guards.
- **Zero-Latency Recording**: Parallelized initialization of audio capture and transport layers for instant dictation.
- **Enterprise Security**: Windows Credential Manager enclave storage, Encrypted local history (AES-256), and automated JWT expiry warnings.
- **Handshake Cage Protocol**: Native implementation of the buffer-then-flush security strategy to ensure zero-data leakage before identity verification.
- **Native System Integration**: Single-instance enforcement via Win32 Named Mutex and deep-sleep resilient global hotkeys.
- **Privacy Core**: Integrated **Incognito Mode** with explicit memory hygiene and protocol-level log redaction (Local Only in Groq mode).
- **Verification Suite**: Bundled security tests validating PKCE cryptographic integrity and state-parameter protection.

📖 **[Flutter Client Documentation](flutter_client/README.md)**

### Python Terminal Client v2.24.8

A secure, modular, and production-ready Windows terminal client for high-performance dictation.

- **Secure API Key Storage** (OS Enclave)
- **Structured Error Handling** (Routes all 12 `error_code` types with user-specific guidance)
- **Keepalive Ping** (Prevents Cloudflare Tunnel idle drops)
- **Exponential Backoff Reconnection** (Jittered retries, max 10 attempts)
- **Granular Handshake State Machine** (BANNED, VERSION_OUTDATED, FAILED states)
- **Fail-Secure Handshake**
- **Auto Copy/Paste**
- **Automated First-Time Setup**
- **Incognito Mode** (Ghost Mode)
- **Pytest + Pyright + Ruff Quality Gates** for the fallback/debug client

This client is intended for Windows desktop use. Linux/WSL users should treat it as an unsupported runtime and use the Flutter client or direct backend tooling instead.

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
| Phase 14 | Multi-Connection Path [Groq Cloud] (v2.24.0)           | ✅ Complete    |
