# Setup

There are two ways to use WhisperDoc:

- **Just the Windows app**, with your own [Groq](https://console.groq.com) key (free) or [OpenRouter](https://openrouter.ai/keys) key (paid). No server needed.
- **Your own server**: the backend runs Whisper or Parakeet on your GPU (or CPU) in Docker, and the clients connect to it.

## Install the Windows app

1. Download `WhisperDoc_Setup_<version>.exe` from the [latest release](https://github.com/EphremTil17/WhisperDoc/releases/latest) and run it.
2. Open **Account** and pick a source at the top: **Groq**, **OpenRouter** or **Self-hosted**.
3. Paste your key (Groq or OpenRouter), or the address of your server (Self-hosted).
4. Press the hotkey (shown on the home screen), speak, press it again. The text lands where your cursor is.

More in the [Flutter client guide](../flutter_client/README.md). A terminal client for Windows is also available: [terminal client guide](../terminal_client/README.md).

## Run your own server

### Requirements

- **Docker Engine with the Compose plugin, 2.24 or newer**, and a user that can run `docker` (in the `docker` group).
- `curl`.
- **For a GPU (recommended)**: an NVIDIA GPU with more than 4 GB of VRAM, its driver (`nvidia-smi` works), and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) configured for Docker:
  ```bash
  sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
  ```
- Python 3 only for the Parakeet engine (to download its model), and [uv](https://docs.astral.sh/uv/) only for local backend development.

Without a GPU the server runs Whisper on the CPU; Parakeet needs the GPU.

### Quick start (Linux)

```bash
git clone https://github.com/EphremTil17/WhisperDoc.git
cd WhisperDoc
./setup.sh
```

It asks up to three questions (engine, developer environment, build now), then:

1. creates `.env` from `backend/.env.template` (mode 600) and generates a random `WHISPER_DOC_API_KEY` into it if it is empty;
2. picks GPU or CPU: the GPU only when `nvidia-smi` works and the Container Toolkit is installed;
3. downloads the Parakeet model if you chose Parakeet;
4. builds and starts the backend, and waits until `http://localhost:9989/health` answers (the first start downloads the model, which can take a few minutes).

Unattended, or to force a choice:

| Flag | Effect |
|---|---|
| `--engine whisper\|parakeet` | The engine (default: ask, keeping `.env`'s `ASR_ENGINE`) |
| `--cpu` / `--gpu` | Force the device (default: auto-detect). The CPU runs Whisper only |
| `--dev` | Also set up the local backend development environment (uv) |
| `-y`, `--yes` | No prompts: build and start |

```bash
./setup.sh --engine whisper --yes
```

Your API key is in `.env`; show it with `grep WHISPER_DOC_API_KEY .env`.

### Manual setup (any OS with Docker)

1. Create `.env` and set an API key:
   ```bash
   cp backend/.env.template .env
   chmod 600 .env        # Linux/macOS
   ```
   Set `WHISPER_DOC_API_KEY` in `.env` to a long random value (for example the output of `openssl rand -hex 32`). Compose refuses to start without it ("No API KEY set").
2. Choose the engine with `ASR_ENGINE=whisper` or `parakeet`. `COMPOSE_PROFILES=${ASR_ENGINE}` makes the Parakeet container start only for Parakeet. For Parakeet, download its digest-verified model once:
   ```bash
   python3 backend/tools/provision_parakeet.py
   ```
3. **No NVIDIA GPU?** Add these lines to `.env` (Whisper only):
   ```dotenv
   COMPOSE_FILE=docker-compose.yml:docker-compose.cpu.yml
   MODEL_DEVICE=cpu
   MODEL_COMPUTE_TYPE=int8
   ```
   A smaller `MODEL_NAME` such as `small.en` answers faster on a CPU.
4. Build, start and check:
   ```bash
   docker compose build backend
   docker compose up -d backend
   curl http://localhost:9989/health
   ```

With Whisper, only the `backend` container runs and holds the model. With Parakeet, `backend` is a model-free API and the `parakeet` container runs the native model, so exactly one model is loaded either way.

### Connect a client

The server listens on `127.0.0.1:9989` only. Clients connect to `ws://localhost:9989/ws` on the same machine. To reach it from elsewhere, put it behind TLS (a reverse proxy or a tunnel such as Cloudflare Tunnel) and connect with `wss://`; the clients refuse plain `ws://` to anything but a local or private address.

- **Flutter app**: Account → **Self-hosted** → **Server address**, then **Sign in** (if the server has OIDC configured) or **Developer key** (the `WHISPER_DOC_API_KEY`).
- **Terminal client**: see its [guide](../terminal_client/README.md).

### Sign-in (optional)

Without OIDC the server accepts only the API key. Sign-in works with any OIDC provider that publishes a discovery document and signs its tokens with RS256; the reference setup uses Authentik.

1. At the provider, create a public client (no secret) that uses PKCE, with the redirect URI `http://localhost:4242/callback` and the scopes `openid profile email offline_access`. In Authentik, that is an OAuth2/OpenID provider of client type *Public*; also pick a **signing key**, or Authentik signs with HS256, which the server refuses.
2. In `.env`, set `OIDC_ISSUER_URL` to the issuer (in Authentik, `https://<host>/application/o/<app-slug>/`) and `OIDC_CLIENT_ID` to the client ID.
3. Build the Flutter app with the same values in `env.json` (see [development](development.md)).

## Configuration

Everything is set in `.env`; `backend/.env.template` documents every variable, including the security limits (bans, flood control, timeouts) and OIDC sign-in.

| Variable | Description | Default |
|---|---|---|
| `ASR_ENGINE` | `whisper` or `parakeet` | `whisper` |
| `MODEL_NAME` | Whisper model, e.g. `tiny.en`, `large-v3-turbo` | `large-v3-turbo` |
| `MODEL_DEVICE` | `cuda` or `cpu` | `cuda` |
| `MODEL_COMPUTE_TYPE` | `float16` on a GPU, `int8` on a CPU | `float16` |
| `API_PORT` | Port the server listens on | `9989` |
| `WHISPER_DOC_API_KEY` | Key for clients without sign-in | none (required) |
| `PARAKEET_ACCELERATOR` | parakeet.cpp device (`CUDA0` is the first GPU) | `CUDA0` |
| `PARAKEET_MAX_AUDIO_SECONDS` | Longest piece sent to Parakeet at once; longer audio is split at quiet points | `30` |
| `BACKEND_IMAGE_NAME` | Docker image name | `whisperdoc-backend` |
| `LOG_LEVEL` | `DEBUG`, `INFO` or `SUCCESS` | `INFO` |

## Everyday commands

```bash
docker compose logs -f backend     # follow the server log
docker compose down                # stop
docker compose build backend && docker compose up -d --force-recreate backend   # after an update
```

The model cache lives in `./model-cache`, so restarts don't download again. The container writes it as root, so deleting it needs `sudo`.

## Troubleshooting

**"No API KEY set" when starting.** `WHISPER_DOC_API_KEY` is empty in `.env`. Run `./setup.sh` (it generates one) or set it by hand.

**A GPU error on `docker compose up`** (Docker can't satisfy the NVIDIA device request). Install and configure the NVIDIA Container Toolkit (see Requirements), or switch to the CPU with `./setup.sh --cpu` or the three `.env` lines under Manual setup.

**"permission denied" on the Docker socket.** Add yourself to the `docker` group (`sudo usermod -aG docker $USER`), then log out and in.

**"Read-only file system" inside the container.** Expected: the container's root filesystem is read-only by design. Only `/tmp` is writable.

**`/health` takes minutes the first time.** The model is downloading into `./model-cache`. `./setup.sh` waits up to 10 minutes and prints the log if the container stops.
