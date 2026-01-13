# --- STAGE 1: Builder ---
FROM python:3.10-slim AS builder

WORKDIR /app

# Install basic build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --upgrade pip

ENV PATH=/root/.local/bin:$PATH

# Copy only requirements
COPY requirements.txt .

# Install dependencies to a local folder
# We use cache mounts to reuse downloaded wheels across builds
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --user -r requirements.txt


# --- STAGE 2: Runner ---
FROM python:3.10-slim AS runner

WORKDIR /app

# 1. Environment & Performance Settings
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/app/model-cache
ENV PATH=/root/.local/bin:$PATH
# added the "Belt & Suspenders" environment variables ensures that any underlying C-libraries used by PyTorch or FFmpeg will also default to the RAM-disk at /tmp.
ENV TMPDIR=/tmp
ENV TEMP=/tmp
ENV TMP=/tmp

# The "Secret Sauce": Tell the system where the CUDA libs are hidden in Python site-packages
ENV LD_LIBRARY_PATH=/root/.local/lib/python3.10/site-packages/nvidia/cublas/lib:/root/.local/lib/python3.10/site-packages/nvidia/cudnn/lib:$LD_LIBRARY_PATH

# 2. Install ONLY runtime essentials (ffmpeg is mandatory for audio)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 3. Copy the 7.5GB of dependencies from the builder stage
COPY --from=builder /root/.local /root/.local

# 4. Copy application code
COPY api_server.py websocket_handler.py logging_config.py auth.py .env.template ./
COPY tests/ ./tests/

# 5. Network & Execution
ARG API_PORT=9989
EXPOSE ${API_PORT}

# Bake version into the image metadata
# Users can verify with: docker inspect -f '{{.Config.Labels.version}}' whisper-backend
ARG VERSION
LABEL version=${VERSION} 
# Note: Docker/BuildKit tricky with dynamic labels from files. 
# Best practice: pass it as a build-arg from the compose file.

HEALTHCHECK --interval=10m --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:9989/health || exit 1

CMD ["uvicorn", "api_server:app", "--host", "0.0.0.0", "--port", "9989", "--proxy-headers", "--forwarded-allow-ips='*'", "--timeout-keep-alive", "300"]
