#!/bin/bash
# WhisperDoc Setup Script
# Prepares .env, picks the ASR engine and CPU or GPU mode, then builds and
# starts the backend in Docker and waits until it reports healthy.
# Run ./setup.sh --help for the flags that make it non-interactive.

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

ENV_FILE=".env"
CPU_COMPOSE_FILE="docker-compose.yml:docker-compose.cpu.yml"
# The first start downloads the Whisper model before /health answers.
HEALTH_TIMEOUT_SECONDS=600

# Empty means "ask or detect"; flags fill them in.
ENGINE=""
DEVICE=""
DEV_ENV=""
ASSUME_YES=false

step() { echo -e "\n${YELLOW}[STEP $1]${NC} $2"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${YELLOW}[INFO]${NC} $*"; }
warn() { echo -e "${RED}[WARN]${NC} $*"; }
die() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: ./setup.sh [options]

Prepares .env, then builds and starts the WhisperDoc backend in Docker and
waits for http://localhost:<API_PORT>/health. Without options it asks.

  --engine whisper|parakeet  ASR engine (default: ask, keeping .env's ASR_ENGINE)
  --cpu                      Run on the CPU (Whisper only)
  --gpu                      Run on an NVIDIA GPU (default: auto-detect)
  --dev                      Also sync the local backend dev environment (uv)
  -y, --yes                  Build and start without asking; skip all prompts
  -h, --help                 Show this help
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --engine)
                (($# >= 2)) || die "--engine needs a value: whisper or parakeet."
                ENGINE="$2"
                shift
                ;;
            --engine=*) ENGINE="${1#*=}" ;;
            --cpu) DEVICE="cpu" ;;
            --gpu) DEVICE="gpu" ;;
            --dev) DEV_ENV=true ;;
            -y | --yes) ASSUME_YES=true ;;
            -h | --help)
                usage
                exit 0
                ;;
            *) die "Unknown option: $1 (see ./setup.sh --help)" ;;
        esac
        shift
    done
    case "$ENGINE" in
        "" | whisper | parakeet) ;;
        *) die "Unsupported engine '$ENGINE'. Choose whisper or parakeet." ;;
    esac
}

# Reads one answer into REPLY. --yes or a closed stdin leaves it empty, which
# every prompt treats as its default.
ask() {
    REPLY=""
    if [[ "$ASSUME_YES" == false ]]; then
        read -r -p "$1" REPLY || true
    fi
}

confirm() {
    ask "$1 (y/N): "
    [[ "$REPLY" =~ ^[Yy] ]]
}

# --- .env helpers (values are never echoed) ---
env_value() {
    local value
    value=$(sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1)
    value="${value%$'\r'}"
    value="${value#[\"\']}"
    printf '%s' "${value%[\"\']}"
}

set_env_key() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        printf '\n%s=%s\n' "$key" "$value" >>"$ENV_FILE"
    fi
}

unset_env_key() {
    sed -i "/^$1=/d" "$ENV_FILE"
}

# --- Steps ---
check_docker() {
    step 1 "Checking Docker..."
    command -v docker &>/dev/null ||
        die "Docker could not be found. Install Docker Engine: https://docs.docker.com/engine/install/"
    docker compose version &>/dev/null ||
        die "The Docker Compose plugin is missing. Install it: https://docs.docker.com/compose/install/linux/"
    docker info &>/dev/null ||
        die "Cannot reach the Docker daemon. Start Docker; on 'permission denied', run: sudo usermod -aG docker \$USER (then log out and back in)."
    command -v curl &>/dev/null || die "curl could not be found. Install it, e.g.: sudo apt install curl"
    ok "Docker and Docker Compose $(docker compose version --short) are available."
}

ensure_env_file() {
    step 2 "Setting up the .env file..."
    if [[ -f "$ENV_FILE" ]]; then
        ok ".env already exists; keeping your settings."
    else
        [[ -f backend/.env.template ]] || die "backend/.env.template not found!"
        cp backend/.env.template "$ENV_FILE"
        ok "Created .env from backend/.env.template."
    fi
    chmod 600 "$ENV_FILE"
    ensure_api_key
}

ensure_api_key() {
    if [[ -n "$(env_value WHISPER_DOC_API_KEY)" ]]; then
        ok "WHISPER_DOC_API_KEY is already set in .env."
        return
    fi
    # 32 random bytes as 64 hex characters, written straight into .env.
    set_env_key WHISPER_DOC_API_KEY "$(od -An -vtx1 -N32 /dev/urandom | tr -d ' \n')"
    ok "Generated a random WHISPER_DOC_API_KEY in .env (permissions: 600)."
    echo "  Clients authenticate with it. Show it with: grep WHISPER_DOC_API_KEY .env"
}

nvidia_toolkit_installed() {
    command -v nvidia-ctk &>/dev/null || command -v nvidia-container-runtime-hook &>/dev/null
}

choose_device() {
    step 3 "Choosing CPU or GPU..."
    if [[ -n "$DEVICE" ]]; then
        info "Using the ${DEVICE^^} as requested."
    elif ! nvidia-smi &>/dev/null; then
        DEVICE="cpu"
        info "No NVIDIA GPU detected: transcribing on the CPU."
    elif ! nvidia_toolkit_installed; then
        DEVICE="cpu"
        warn "NVIDIA GPU found, but Docker cannot use it without the NVIDIA Container Toolkit."
        echo "  Install: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
        echo "  Then run: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
        echo "  and rerun ./setup.sh. Using the CPU for now."
    else
        DEVICE="gpu"
        ok "NVIDIA GPU and Container Toolkit detected: transcribing on the GPU (--cpu overrides)."
    fi
}

choose_engine() {
    step 4 "Choosing the ASR engine..."
    local current
    current=$(env_value ASR_ENGINE)
    if [[ "$current" != "whisper" && "$current" != "parakeet" ]]; then
        warn "Unsupported ASR_ENGINE='$current' in .env. Falling back to 'whisper'."
        current="whisper"
    fi

    if [[ "$ENGINE" == "parakeet" && "$DEVICE" == "cpu" ]]; then
        die "Parakeet needs an NVIDIA GPU. On the CPU use: --engine whisper"
    elif [[ -z "$ENGINE" && "$DEVICE" == "cpu" ]]; then
        ENGINE="whisper"
        info "Parakeet needs an NVIDIA GPU, so the CPU runs Whisper."
    elif [[ -z "$ENGINE" ]]; then
        prompt_engine "$current"
    fi
    ok "Engine: ${CYAN}${ENGINE}${NC}"
}

prompt_engine() {
    echo "Which backend engine would you like to run?"
    echo -e "  ${CYAN}1)${NC} Whisper (faster-whisper, multilingual)"
    echo -e "  ${CYAN}2)${NC} Parakeet (parakeet.cpp on CUDA, English only)"
    ask "Selection (1-2, Enter keeps ${1}): "
    case "$REPLY" in
        1) ENGINE="whisper" ;;
        2) ENGINE="parakeet" ;;
        *) ENGINE="$1" ;;
    esac
}

write_settings() {
    set_env_key ASR_ENGINE "$ENGINE"
    # Literal ${ASR_ENGINE}: Compose interpolates it, so the parakeet profile
    # follows the engine choice and the two can never disagree.
    # shellcheck disable=SC2016
    set_env_key COMPOSE_PROFILES '${ASR_ENGINE}'

    if [[ "$DEVICE" == "cpu" ]]; then
        # Compose reads COMPOSE_FILE from .env, so plain `docker compose`
        # commands keep the CPU override.
        set_env_key COMPOSE_FILE "$CPU_COMPOSE_FILE"
        set_model_device cpu int8
        info "CPU transcription is slower; a smaller MODEL_NAME in .env (e.g. small.en) answers faster."
    else
        if [[ "$(env_value COMPOSE_FILE)" == "$CPU_COMPOSE_FILE" ]]; then
            unset_env_key COMPOSE_FILE
        fi
        set_model_device cuda float16
    fi
    ok "Saved ASR_ENGINE=${ENGINE} and MODEL_DEVICE=$(env_value MODEL_DEVICE) to .env."
}

# Keeps a custom MODEL_COMPUTE_TYPE unless the device itself changes.
set_model_device() {
    if [[ "$(env_value MODEL_DEVICE)" != "$1" ]]; then
        set_env_key MODEL_DEVICE "$1"
        set_env_key MODEL_COMPUTE_TYPE "$2"
    fi
}

prepare_local_files() {
    step 5 "Preparing local files..."
    local dir
    for dir in "assets/recordings" "model-cache"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            ok "Created $dir directory."
        fi
    done
    if [[ "$ENGINE" == "parakeet" ]]; then
        provision_parakeet
    fi
    setup_dev_env
}

provision_parakeet() {
    command -v python3 &>/dev/null || die "python3 is needed to download the Parakeet model."
    echo -e "${CYAN}[MODEL]${NC} Provisioning the digest-verified Parakeet model..."
    python3 backend/tools/provision_parakeet.py
}

setup_dev_env() {
    if [[ -z "$DEV_ENV" ]] &&
        confirm "Also set up the local backend dev environment with uv (only for backend development)?"; then
        DEV_ENV=true
    fi
    if [[ "$DEV_ENV" != true ]]; then
        info "Skipping the local dev environment; Docker installs the backend's dependencies."
        return
    fi
    ensure_uv
    echo -e "${CYAN}[UV]${NC} Syncing backend dev environment for: ${ENGINE}"
    if [[ "$ENGINE" == "parakeet" ]]; then
        (cd backend && uv sync --group dev)
    else
        (cd backend && uv sync --group dev --extra whisper)
    fi
    ok "Backend dev environment ready in backend/.venv."
}

ensure_uv() {
    if command -v uv &>/dev/null; then
        return
    fi
    info "Installing uv with its official installer (https://docs.astral.sh/uv/)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv &>/dev/null ||
        die "uv could not be installed. Install it manually: https://docs.astral.sh/uv/getting-started/installation/"
}

# --- Build & Launch ---
# The shell overrides .env, as it does for Compose.
api_port() {
    local port="${API_PORT:-$(env_value API_PORT)}"
    printf '%s' "${port:-9989}"
}

validate_compose() {
    docker compose config --quiet ||
        die "Docker Compose rejected the configuration above (the CPU override needs Compose 2.24 or newer)."
}

build_and_start() {
    step 6 "Build and start the backend? (Engine: ${CYAN}${ENGINE}${NC}, ${DEVICE^^})"
    echo "  This will run: docker compose build backend && docker compose up -d backend"
    if [[ "$ASSUME_YES" != true ]] && ! confirm "Proceed?"; then
        print_next_steps
        return
    fi
    echo -e "${YELLOW}[BUILD]${NC} Building image (Dockerfile.${ENGINE})..."
    docker compose build backend
    echo -e "${YELLOW}[START]${NC} Starting backend service..."
    docker compose up -d backend
    wait_for_health
    print_success
}

# True once the backend container has stopped or restarted.
backend_crashed() {
    local id
    id=$(docker compose ps -aq backend)
    [[ -z "$id" || "$(docker inspect -f '{{.State.Status}} {{.RestartCount}}' "$id")" != "running 0" ]]
}

wait_for_health() {
    local url started="$SECONDS"
    url="http://127.0.0.1:$(api_port)/health"
    echo -e "${YELLOW}[WAIT]${NC} Waiting for ${url} (the first start downloads the model; up to $((HEALTH_TIMEOUT_SECONDS / 60)) min)..."
    while ((SECONDS - started < HEALTH_TIMEOUT_SECONDS)); do
        if curl -fsS --max-time 5 "$url" &>/dev/null; then
            ok "Backend is healthy after $((SECONDS - started))s."
            return
        fi
        if backend_crashed; then
            break
        fi
        sleep 5
    done
    echo -e "${RED}[ERROR]${NC} The backend did not become healthy. Last log lines:" >&2
    docker compose logs --tail 40 backend >&2 || true
    exit 1
}

print_success() {
    local port
    port=$(api_port)
    echo ""
    echo -e "${GREEN}Setup complete!${NC}"
    echo "--------------------"
    echo "  Health:  curl http://localhost:${port}/health"
    echo "  API key: WHISPER_DOC_API_KEY in .env (grep WHISPER_DOC_API_KEY .env)"
    echo "  Logs:    docker compose logs -f backend"
    echo "  Stop:    docker compose down"
}

print_next_steps() {
    echo ""
    echo -e "${GREEN}Setup complete!${NC}"
    echo "--------------------"
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. (Optional) Review .env, e.g. MODEL_NAME: nano .env"
    echo "  2. Build and start the backend:"
    echo "     docker compose build backend && docker compose up -d backend"
    echo "  3. Check it:"
    echo "     docker compose logs -f backend"
    echo "     curl http://localhost:$(api_port)/health"
}

main() {
    parse_args "$@"
    echo -e "${GREEN}WhisperDoc Setup Script${NC}"
    echo "=========================="
    # Resolve repo root so the script works even when invoked from another directory.
    cd "$(dirname "${BASH_SOURCE[0]}")"

    check_docker
    ensure_env_file
    choose_device
    choose_engine
    write_settings
    prepare_local_files
    validate_compose
    build_and_start
}

main "$@"
