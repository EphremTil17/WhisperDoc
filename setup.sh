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

# Check if .env exists
if [ -f ".env" ]; then
    echo -e "${GREEN}[OK]${NC} .env file already exists"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}[INFO]${NC} Keeping existing .env file"
        exit 0
    fi
fi

# Copy .env.template to .env
if [ -f ".env.template" ]; then
    cp .env.template .env
    echo -e "${GREEN}[OK]${NC} Created .env from template"
else
    echo -e "${RED}[ERROR]${NC} .env.template not found!"
    exit 1
fi

# Create assets directory if it doesn't exist
if [ ! -d "assets" ]; then
    mkdir -p assets/recordings
    echo -e "${GREEN}[OK]${NC} Created assets directory"
fi

echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "- Edit .env to customize your settings"
echo "- Default port: 9989"
echo "- Default model: medium.en"
echo "- Default device: cuda"

echo ""
echo -e "${GREEN}Quick Start:${NC}"
echo "1. Edit .env file if needed:"
echo "   nano .env"
echo ""
echo "2. Build and start the backend:"
echo "   sudo docker compose build whisper-backend"
echo "   sudo docker compose up -d whisper-backend"
echo ""
echo "3. Test the API:"
echo "   python3 test_api.py --health-only"
echo ""
echo "4. Test transcription (with your audio file):"
echo "   python3 test_api.py --file your_audio.wav"

echo ""
echo -e "${GREEN}[OK]${NC} Setup complete! Check the README.md for more details."
