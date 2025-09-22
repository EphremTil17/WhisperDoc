# Basic test Dockerfile - just faster-whisper
FROM nvidia/cuda:12.3.2-cudnn9-runtime-ubuntu22.04

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set environment variable for model cache
ENV HF_HOME=/app/model-cache

# Install dependencies, including loguru
RUN pip3 install faster-whisper fastapi 'uvicorn[standard]' python-multipart loguru

# Copy all files from the build context (the 'backend' directory)
COPY . .

# Declare and use a build-time argument for the API port
ARG API_PORT=9989
EXPOSE ${API_PORT}

# Run the API server using uvicorn, sourcing the port from the runtime environment
CMD uvicorn api_server:app --host 0.0.0.0 --port ${API_PORT}
