# --- STAGE 0: FFmpeg Source ---
# We use a specialized static build to avoid 600MB of apt-dependencies
FROM mwader/static-ffmpeg:latest AS ffmpeg-source

# --- STAGE 1: Builder ---
FROM python:3.10-slim AS builder

WORKDIR /app

# Install minimal build tools (gcc/g++ instead of the heavy build-essential)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    python3-dev \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --upgrade pip

ENV PATH=/root/.local/bin:$PATH

# Copy only requirements
COPY requirements.txt .

# Install dependencies to a local folder
# We use cache mounts to reuse downloaded wheels across builds
# We aggressively prune unnecessary files (.a, .pyc, etc) to prevent layer expansion
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install --user -r requirements.txt && \
    find /root/.local -name "*.a" -delete && \
    find /root/.local -name "__pycache__" -type d -exec rm -rf {} + && \
    find /root/.local -name "*.pyc" -delete


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

# 2. Install ONLY runtime essentials (libgomp1 is required for Whisper's math)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 3. Copy static FFmpeg binaries from Stage 0
COPY --from=ffmpeg-source /ffmpeg /ffprobe /usr/local/bin/

# 4. Copy the dependencies from the builder stage
# /root/.local contains all pip-installed packages (via --user)
COPY --from=builder /root/.local /root/.local

# 5. Copy application code
# We use a single COPY . . which respects .dockerignore
# This is cleaner and ensures __init__.py and other files are not missed
COPY . .

# 6. Network & Execution
ARG API_PORT=9989
ENV API_PORT=${API_PORT}
EXPOSE ${API_PORT}

# Bake version into the image metadata
ARG VERSION
LABEL version=${VERSION} 

# Use Python for healthcheck to avoid installing curl
HEALTHCHECK --interval=10m --timeout=10s --start-period=10s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:${API_PORT}/health')" || exit 1

# We use shell form for CMD to allow environment variable expansion
CMD uvicorn api_server:app --host 0.0.0.0 --port ${API_PORT} --proxy-headers --forwarded-allow-ips='*' --timeout-keep-alive 300
