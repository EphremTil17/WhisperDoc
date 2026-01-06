# Basic test Dockerfile - just faster-whisper
FROM nvidia/cuda:12.3.2-cudnn9-runtime-ubuntu22.04

WORKDIR /app

# Install system dependencies with cache mount
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    curl \
    ffmpeg

# Set environment variable for model cache
ENV HF_HOME=/app/model-cache

# Copy requirements first to leverage caching
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install -r requirements.txt

# Copy all files from the build context (the 'backend' directory)
COPY . .

# Declare and use a build-time argument for the API port
ARG API_PORT=9989
EXPOSE ${API_PORT}

# Run the API server using uvicorn, sourcing the port from the runtime environment
CMD uvicorn api_server:app --host 0.0.0.0 --port ${API_PORT}
