#!/bin/bash
# WhisperDoc Setup Script
# This script helps new users get started with WhisperDoc

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}WhisperDoc Setup Script${NC}"
echo "=========================="

# Resolve repo root so the script works even when invoked from another directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Environment File Setup ---
echo -e "${YELLOW}[STEP 1]${NC} Setting up environment file..."
if [ -f ".env" ]; then
    echo -e "${GREEN}[OK]${NC} .env file already exists."
else
    if [ -f "backend/.env.template" ]; then
        cp backend/.env.template .env
        chmod 600 .env
        echo -e "${GREEN}[OK]${NC} Created .env from backend/.env.template (permissions: 600)."
    else
        echo -e "${RED}[ERROR]${NC} backend/.env.template not found!"
        exit 1
    fi
fi

# --- Python Dependencies ---
echo -e "\n${YELLOW}[STEP 2]${NC} Setting up Python dependencies..."
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} python3 could not be found."
    exit 1
fi

# Ensure uv is available
if ! command -v uv &> /dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Installing uv package manager..."
    python3 -m pip install --user uv
    export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v uv &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} uv could not be installed automatically."
    echo "  Install it manually: https://docs.astral.sh/uv/getting-started/installation/"
    exit 1
fi

ASR_ENGINE=$(grep -oP '(?<=^ASR_ENGINE=)\S+' .env 2>/dev/null || echo "whisper")
if [[ "$ASR_ENGINE" != "whisper" && "$ASR_ENGINE" != "parakeet" && "$ASR_ENGINE" != "parakeet_cpp" ]]; then
    echo -e "${YELLOW}[WARN]${NC} Unsupported ASR_ENGINE='$ASR_ENGINE' in .env. Falling back to 'whisper' for local setup."
    ASR_ENGINE="whisper"
fi

install_backend_env() {
    local engine="$1"
    echo -e "${CYAN}[UV]${NC} Syncing backend dev environment for: ${engine}"
    (
        cd backend
        if [[ "$engine" == "parakeet_cpp" ]]; then
            uv sync --group dev
        else
            uv sync --group dev --extra "$engine"
        fi
    )
}

set_env_key() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '\n%s=%s\n' "$key" "$value" >> .env
    fi
}

echo ""
echo "Which backend engine would you like to prepare?"
echo -e "  ${CYAN}1)${NC} Whisper backend"
echo -e "  ${CYAN}2)${NC} Parakeet.cpp CUDA sidecar ${YELLOW}(experimental)${NC}"
echo -e "  ${CYAN}3)${NC} NVIDIA NeMo Parakeet ${YELLOW}(legacy/rollback)${NC}"
echo -e "  ${YELLOW}[INFO]${NC} Current .env ASR_ENGINE=${ASR_ENGINE}"
read -p "Selection (1-3, Enter to keep current): " -n 1 -r
echo
case $REPLY in
    1)
        ASR_ENGINE="whisper"
        ;;
    2)
        ASR_ENGINE="parakeet_cpp"
        ;;
    3)
        ASR_ENGINE="parakeet"
        ;;
    *)
        echo -e "${YELLOW}[INFO]${NC} Keeping backend engine from .env: ${ASR_ENGINE}"
        ;;
esac

set_env_key "ASR_ENGINE" "$ASR_ENGINE"
case "$ASR_ENGINE" in
    whisper)
        BACKEND_DOCKERFILE="Dockerfile.whisper"
        COMPOSE_PROFILES=""
        ;;
    parakeet)
        BACKEND_DOCKERFILE="Dockerfile.parakeet"
        COMPOSE_PROFILES=""
        ;;
    parakeet_cpp)
        BACKEND_DOCKERFILE="Dockerfile.api"
        COMPOSE_PROFILES="parakeet-cpp"
        ;;
esac
set_env_key "BACKEND_DOCKERFILE" "$BACKEND_DOCKERFILE"
set_env_key "COMPOSE_PROFILES" "$COMPOSE_PROFILES"
install_backend_env "$ASR_ENGINE"
if [[ "$ASR_ENGINE" == "parakeet_cpp" ]]; then
    echo -e "${CYAN}[MODEL]${NC} Provisioning the digest-verified parakeet.cpp model..."
    uv run --project backend python backend/tools/provision_parakeet_cpp.py
fi
echo -e "${GREEN}[OK]${NC} Backend local environment set up with ${CYAN}${ASR_ENGINE}${NC}."
echo -e "${YELLOW}[NOTE]${NC} Backend setup uses native UV project sync from backend/pyproject.toml."

# --- GPU / NVIDIA Setup ---
echo -e "\n${YELLOW}[STEP 3]${NC} Checking for GPU support (NVIDIA Container Toolkit)..."
if command -v nvidia-smi &> /dev/null; then
    echo -e "${GREEN}[OK]${NC} NVIDIA GPU detected."
    if ! command -v nvidia-ctk &> /dev/null; then
        echo -e "${RED}[WARN]${NC} NVIDIA Container Toolkit (nvidia-ctk) not found."
        echo "  This is required for Docker to access the GPU."
        echo "  Install: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
        echo "  Then run: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
    else
        echo -e "${GREEN}[OK]${NC} NVIDIA Container Toolkit is installed."
    fi
else
    echo -e "${YELLOW}[INFO]${NC} No NVIDIA GPU detected or drivers not installed."
    echo -e "      The system will fall back to CPU transcription (set MODEL_DEVICE=cpu in .env)."
fi

# --- Docker Setup ---
echo -e "\n${YELLOW}[STEP 4]${NC} Docker setup..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker could not be found. Please install Docker and ensure it is running."
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Docker is available."

# Create required directories
for dir in "assets/recordings" "model-cache"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo -e "${GREEN}[OK]${NC} Created $dir directory."
    fi
done

# --- Build & Launch ---
echo ""
echo -e "${YELLOW}[STEP 5]${NC} Build and start backend? (Engine: ${CYAN}${ASR_ENGINE}${NC})"
echo -e "  This will run: docker compose build whisper-backend && docker compose up -d whisper-backend"
read -p "Proceed? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}[BUILD]${NC} Building image (${BACKEND_DOCKERFILE})..."
    docker compose build whisper-backend
    echo -e "${YELLOW}[START]${NC} Starting backend service..."
    docker compose up -d whisper-backend
    echo -e "${GREEN}[OK]${NC} Backend is running."
    echo ""
    echo -e "${GREEN}Setup complete!${NC}"
    echo "--------------------"
    echo -e "${YELLOW}Verify:${NC}"
    echo "  docker compose logs -f whisper-backend"
    echo "  curl http://localhost:${API_PORT:-9989}/health"
else
    echo ""
    echo -e "${GREEN}Setup complete!${NC}"
    echo "--------------------"
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. (Optional) Edit your .env file: nano .env"
    echo "     - Set WHISPER_DOC_API_KEY to a secure value"
    echo "     - Review ASR_ENGINE=${ASR_ENGINE} if you want to switch engines later"
    echo "  2. Build and start the backend:"
    echo "     docker compose build whisper-backend && docker compose up -d whisper-backend"
    echo "  3. Check the server logs:"
    echo "     docker compose logs -f whisper-backend"
fi
