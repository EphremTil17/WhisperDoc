#!/bin/bash
# WhisperDoc Setup Script
# This script helps new users get started with WhisperDoc

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}WhisperDoc Setup Script${NC}"
echo "=========================="

# --- Environment File Setup ---
echo -e "${YELLOW}[STEP 1]${NC} Setting up environment file..."
if [ -f ".env" ]; then
    echo -e "${GREEN}[OK]${NC} .env file already exists."
else
    if [ -f ".env.template" ]; then
        cp .env.template .env
        echo -e "${GREEN}[OK]${NC} Created .env from template."
    else
        echo -e "${RED}[ERROR]${NC} .env.template not found!"
        exit 1
    fi
fi

# --- Python Dependencies ---
echo -e "\n${YELLOW}[STEP 2]${NC} Setting up Python dependencies..."
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} python3 could not be found."
    exit 1
fi

echo "Which components would you like to set up?"
echo "1) Full Developer Environment (Everything)"
echo "2) Backend Only (Faster-Whisper + API)"
echo "3) Client Only (Terminal Transcription Script)"
read -p "Selection (1-3): " -n 1 -r
echo
case $REPLY in
    1)
        pip install -r requirements.txt
        pip install -r backend/requirements.txt
        pip install -r client/requirements.txt
        echo -e "${GREEN}[OK]${NC} Full environment installed."
        ;;
    2)
        pip install -r backend/requirements.txt
        echo -e "${GREEN}[OK]${NC} Backend dependencies installed."
        ;;
    3)
        pip install -r client/requirements.txt
        echo -e "${GREEN}[OK]${NC} Client dependencies installed."
        ;;
    *)
        echo -e "${YELLOW}[INFO]${NC} Skipping automated installation."
        ;;
esac

# --- GPU / NVIDIA Setup ---
echo -e "\n${YELLOW}[STEP 3]${NC} Checking for GPU support (NVIDIA Container Toolkit)..."
if command -v nvidia-smi &> /dev/null; then
    echo -e "${GREEN}[OK]${NC} NVIDIA GPU detected."
    if ! command -v nvidia-ctk &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} NVIDIA Container Toolkit (nvidia-ctk) not found."
        echo "This is required for Docker to access the GPU."
        echo "Please follow official instructions: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
        echo "After installation, remember to run: sudo nvidia-ctk runtime configure --runtime=docker"
    else
        echo -e "${GREEN}[OK]${NC} NVIDIA Container Toolkit is installed."
    fi
else
    echo -e "${YELLOW}[INFO]${NC} No NVIDIA GPU detected or drivers not installed."
    echo -e "      The system will fall back to CPU transcription."
fi

# --- Docker Setup ---
echo -e "\n${YELLOW}[STEP 4]${NC} Docker setup..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker could not be found. Please install Docker and ensure it is running."
    exit 1
fi

# Create assets directory if it doesn't exist
if [ ! -d "assets/recordings" ]; then
    mkdir -p assets/recordings
    echo -e "${GREEN}[OK]${NC} Created assets/recordings directory."
fi

# Create model cache directory if it doesn't exist
if [ ! -d "model-cache" ]; then
    mkdir -p model-cache
    echo -e "${GREEN}[OK]${NC} Created model-cache directory."
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo "--------------------"
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. (Optional) Edit your .env file: nano .env"
echo "2. Build and start the backend service:"
echo "   docker compose build whisper-backend && docker compose up -d whisper-backend"
echo "3. Run your first integration test:"
echo "   cd backend && python tests/test_api.py --health-only"
echo "4. Check the server logs:"
echo "   docker compose logs -f whisper-backend"
