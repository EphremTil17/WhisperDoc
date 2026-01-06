# --- STAGE 1: Builder ---
# We use the same base for the builder to ensure CUDA compatibility during install
FROM nvidia/cuda:12.3.2-cudnn9-runtime-ubuntu22.04 AS builder

WORKDIR /app

# Install pip and system build tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y python3 python3-pip

# Copy only requirements to build the environment
COPY requirements.txt .

# Install dependencies to a local folder
# We use cache mounts to reuse downloaded wheels across builds
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --user --no-cache-dir -r requirements.txt


# --- STAGE 2: Runner (Production Image) ---
FROM nvidia/cuda:12.3.2-cudnn9-runtime-ubuntu22.04 AS runner

WORKDIR /app

# 1. Performance and Logging Tweaks
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/app/model-cache
ENV PATH=/root/.local/bin:$PATH

# 2. Install ONLY runtime system dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 3. Copy only the installed python packages from the builder stage
COPY --from=builder /root/.local /root/.local

# 4. Explicitly copy application code (Avoids context bloat)
COPY api_server.py websocket_handler.py logging_config.py .env.template ./
COPY tests/ ./tests/

# 5. Network and Execution
ARG API_PORT=9989
EXPOSE ${API_PORT}

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${API_PORT}/health || exit 1

CMD uvicorn api_server:app --host 0.0.0.0 --port 9989
