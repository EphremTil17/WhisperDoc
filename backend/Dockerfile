# Basic test Dockerfile - just faster-whisper
FROM nvidia/cuda:12.3.2-cudnn9-runtime-ubuntu22.04

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install faster-whisper and FastAPI dependencies
RUN pip3 install faster-whisper fastapi uvicorn python-multipart

# Copy application files
COPY test_whisper.py .
COPY api_server.py .

# Expose port 9989
EXPOSE 9989

# Run the API server by default
CMD ["python3", "api_server.py"]
