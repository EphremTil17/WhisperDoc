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

# Ensure uv is available (10-50x faster than pip)
if ! command -v uv &> /dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Installing uv package manager..."
    pip install uv
fi

echo ""
echo "Which components would you like to set up?"
echo -e "  ${CYAN}1)${NC} Full Developer Environment (Dev tools + Backend tests + Client)"
echo -e "  ${CYAN}2)${NC} Backend Test Runner (Shared deps for running pytest locally)"
echo -e "  ${CYAN}3)${NC} Client Only (Terminal transcription client)"
read -p "Selection (1-3): " -n 1 -r
echo
case $REPLY in
    1)
        uv pip install -r requirements.txt
        uv pip install -r backend/requirements.txt
        uv pip install -r terminal_client/requirements.txt
        echo -e "${GREEN}[OK]${NC} Full environment installed."
        ;;
    2)
        uv pip install -r backend/requirements.txt
        echo -e "${GREEN}[OK]${NC} Backend test dependencies installed."
        echo -e "${YELLOW}[NOTE]${NC} Engine-specific deps (torch, faster-whisper, NeMo) live inside Docker."
        ;;
    3)
        uv pip install -r terminal_client/requirements.txt
        echo -e "${GREEN}[OK]${NC} Client dependencies installed."
        ;;
    *)
        echo -e "${YELLOW}[INFO]${NC} Skipping dependency installation."
        ;;
esac

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
ASR_ENGINE=$(grep -oP '(?<=^ASR_ENGINE=)\S+' .env 2>/dev/null || echo "whisper")
echo -e "${YELLOW}[STEP 5]${NC} Build and start backend? (Engine: ${CYAN}${ASR_ENGINE}${NC})"
echo -e "  This will run: docker compose build whisper-backend && docker compose up -d whisper-backend"
read -p "Proceed? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}[BUILD]${NC} Building image (Dockerfile.${ASR_ENGINE})..."
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
    echo "     - Set ASR_ENGINE=whisper or ASR_ENGINE=parakeet"
    echo "     - Set WHISPER_DOC_API_KEY to a secure value"
    echo "  2. Build and start the backend:"
    echo "     docker compose build whisper-backend && docker compose up -d whisper-backend"
    echo "  3. Check the server logs:"
    echo "     docker compose logs -f whisper-backend"
fi
