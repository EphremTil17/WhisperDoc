#!/usr/bin/env python3
"""
Minimal FastAPI server for speech-to-text transcription
Uses the ASR engine selected by configuration
"""

import asyncio
import importlib
import os
import shutil
import subprocess
import tempfile
import time
import uuid
from contextlib import asynccontextmanager
from typing import Annotated, Optional

from fastapi import (
    FastAPI,
    File,
    HTTPException,
    Request,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.responses import JSONResponse

from auth import get_api_key, validate_token, warmup_oidc
from engine.engine_factory import create_engine
from logging_config import log
from protocol.websocket_handler import (
    MAX_BUFFER_SIZE,
    ConnectionManager,
    sanitized_segments,
)

# Initialize uvloop for performance before anything else
try:
    uvloop = importlib.import_module("uvloop")
    asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
except ImportError:
    pass


# Read version from environment variable (Docker). The port is passed to
# uvicorn on the command line (see Dockerfile.*).
APP_VERSION = os.getenv("WHISPER_DOC_VERSION", "0.0.0-dev")

# Versioning requirements for clients
# Minimum: Blocking version (below this, client is rejected)
# Security: Advisory version (below this, client is prompted to update)
MIN_CLIENT_VERSION = os.getenv("MIN_CLIENT_VERSION", "0.0.0")
SEC_CLIENT_VERSION = os.getenv("SEC_CLIENT_VERSION", "0.0.0")

# --- HTTP Upload Limits ---
# Whole request body (file + multipart framing), enforced before parsing.
MAX_UPLOAD_BYTES = 25 * 1024 * 1024
# Same audio-length ceiling as the WebSocket path (16 kHz, 16-bit mono).
_PCM_BYTES_PER_SECOND = 16000 * 2
MAX_AUDIO_SECONDS = MAX_BUFFER_SIZE // _PCM_BYTES_PER_SECOND
# A small upload can still decode slowly (or hang on a crafted file).
FFMPEG_TIMEOUT_SECONDS = int(os.getenv("FFMPEG_TIMEOUT_SECONDS", "60"))
# HTTP transcriptions share one concurrency slot, like a single WebSocket user.
_HTTP_IDENTITY = "http"

# Global initialized on startup
manager: Optional[ConnectionManager] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan context manager that handles startup and shutdown logic.
    Replaces the deprecated @app.on_event("startup") and ("shutdown").
    """
    global manager
    log.info(f"Starting WhisperDoc API (v{APP_VERSION})...")
    log.info(
        f"Version Requirements: MIN={MIN_CLIENT_VERSION}, ADVISORY={SEC_CLIENT_VERSION}"
    )

    try:
        # Enforce "Fail Secure" Policy
        get_api_key()  # Will raise RuntimeError if no key is set

        log.info("Initializing ASR engine...")

        # Engine selection is driven by ASR_ENGINE env var (see engine_factory.py)
        engine = create_engine()

        # Initialize the connection manager
        manager = ConnectionManager(
            engine,
            app_version=APP_VERSION,
            min_client_version=MIN_CLIENT_VERSION,
            sec_client_version=SEC_CLIENT_VERSION,
        )
        manager.start()

        # Warmup OIDC (graceful degradation: logs warnings if provider unreachable)
        warmup_oidc()

        log.success("System initialized successfully.")

    except Exception as e:
        # Fail fast: exiting lets the container restart policy retry startup.
        # Serving with manager=None left a live process that could never recover.
        log.error(f"Failed to initialize backend: {e}")
        raise

    yield  # Server runs here

    # --- Shutdown Logic ---
    log.info("Shutting down WhisperDoc API server...")
    if manager:
        await manager.stop()
        manager.engine.unload()
    log.success("Cleanup completed.")


app = FastAPI(
    title="WhisperDoc API",
    description="Speech-to-text transcription service using faster-whisper",
    version=APP_VERSION,
    lifespan=lifespan,
)

# --- Infrastructure Hardening (Middleware & Security) ---
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware

# Compress responses to save bandwidth on large transcription results
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Trusted Host Check: default "*" disables the check (matches .env.template).
# Cloudflare Tunnel forwards with the public hostname as Host header, not
# "localhost", so restricting to "localhost" would silently reject all tunnel
# traffic.  The real auth gate is OIDC / API key, not the Host header.
# Restrict to specific hostnames only when running without a reverse proxy.
ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS", "*").split(",")
app.add_middleware(TrustedHostMiddleware, allowed_hosts=ALLOWED_HOSTS)

# Configure CORS — added last so it executes first (FastAPI LIFO ordering).
# This ensures CORS headers are present even on TrustedHost rejections.
# Wildcard origins with allow_credentials=True violates the CORS spec
# (browsers reject it).  Credentials are only enabled when specific
# origins are configured via ALLOWED_ORIGINS.
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials="*" not in ALLOWED_ORIGINS,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


# --- Global Exception Handler (Error Masking) ---
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Catch-all exception handler to mask system errors in production."""
    error_id = str(uuid.uuid4())[:8]
    log.error(f"Unhandled Error [Ref: {error_id}]: {exc}")

    # In development (no API key set), we might want to see the error,
    # but for this "hardened" block we strictly mask it.
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal Server Error",
            "message": "An unexpected error occurred. Please contact support.",
            "ref": error_id,
        },
    )


async def _reject_upload(request: Request) -> JSONResponse | None:
    """Authenticate and size-check an upload before its body is read.

    FastAPI parses (and spools to disk) a multipart body before route
    dependencies run, so checking auth in a dependency let unauthenticated
    clients upload up to the size cap. Both checks happen here, on headers only.
    """
    header = request.headers.get("authorization", "")
    token = header[7:] if header.lower().startswith("bearer ") else header
    if not token or not await asyncio.to_thread(validate_token, token):
        return JSONResponse(status_code=401, content={"detail": "Invalid API Key"})

    length = request.headers.get("content-length")
    if length is None:
        return JSONResponse(
            status_code=411, content={"detail": "Content-Length required"}
        )
    if not length.isdigit() or int(length) > MAX_UPLOAD_BYTES:
        return JSONResponse(
            status_code=413,
            content={
                "detail": f"Upload too large. Maximum is {MAX_UPLOAD_BYTES} bytes."
            },
        )
    return None


@app.middleware("http")
async def guard_transcribe_uploads(request: Request, call_next):
    if request.method == "POST" and request.url.path == "/transcribe":
        rejection = await _reject_upload(request)
        if rejection is not None:
            return rejection
    return await call_next(request)


@app.get("/health")
async def health_check():
    """Opaque health check to prevent information disclosure.

    An unloaded model is healthy: engines load on demand, and Whisper unloads
    itself after MODEL_TIMEOUT_SECONDS of idleness by design.
    """
    if manager is None or manager.engine is None:
        return JSONResponse(status_code=503, content={"status": "uninitialized"})

    return JSONResponse(
        status_code=200,
        content={
            "status": "online",
            "model": "loaded" if manager.engine.is_loaded() else "idle",
            "timestamp": int(time.time()),
        },
    )


def _validate_upload_type(file: UploadFile, filename: str) -> None:
    """Validate file content type, raising HTTPException on failure."""
    if not file.content_type or not file.content_type.startswith("audio/"):
        allowed_extensions = [".wav", ".mp3", ".m4a", ".flac", ".ogg"]
        if not any(filename.lower().endswith(ext) for ext in allowed_extensions):
            log.warning(f"Invalid file type received: {file.content_type}")
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type. Expected audio file, got: {file.content_type}",
            )


def _save_upload_to_temp(file_obj, suffix: str) -> str:
    """Write the uploaded file to a temp path (sync, for use with to_thread).

    Size is already bounded by the upload guard's Content-Length check.
    """
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        shutil.copyfileobj(file_obj, tmp)
        return tmp.name


def _convert_to_pcm_wav(source: str, target: str) -> None:
    """Normalize any audio to 16 kHz mono s16 WAV, bounded in time and length.

    Decoding stops just past MAX_AUDIO_SECONDS so an over-long file is
    detected without decoding all of it.
    """
    try:
        proc = subprocess.run(
            [
                "ffmpeg",
                "-nostdin",
                "-y",
                "-i",
                source,
                "-t",
                str(MAX_AUDIO_SECONDS + 1),
                "-ar",
                "16000",
                "-ac",
                "1",
                "-sample_fmt",
                "s16",
                target,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=FFMPEG_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        log.warning(f"FFmpeg conversion exceeded {FFMPEG_TIMEOUT_SECONDS}s")
        raise HTTPException(
            status_code=400, detail="Audio could not be decoded in time"
        )

    if proc.returncode != 0:
        log.error(f"FFmpeg conversion failed: {proc.stderr.decode(errors='replace')}")
        raise HTTPException(status_code=400, detail="Unsupported audio format")

    if os.path.getsize(target) > MAX_AUDIO_SECONDS * _PCM_BYTES_PER_SECOND + 1024:
        raise HTTPException(
            status_code=413,
            detail=f"Audio too long. Maximum is {MAX_AUDIO_SECONDS} seconds.",
        )


@app.post(
    "/transcribe",
    responses={
        400: {"description": "Invalid file type or unsupported audio format"},
        401: {"description": "Missing or invalid API key"},
        411: {"description": "Content-Length required"},
        413: {"description": "Upload or audio too large"},
        500: {"description": "Transcription failed"},
        503: {"description": "System not initialized"},
    },
)
async def transcribe_audio(file: Annotated[UploadFile, File()]):
    """Transcribe uploaded audio file"""
    if manager is None:
        raise HTTPException(status_code=503, detail="System not initialized")

    filename = file.filename or "upload"
    _validate_upload_type(file, filename)

    log.info(f"Processing file: {filename} ({file.content_type})")

    # Save uploaded file and normalize to 16kHz mono WAV via FFmpeg.
    # This makes the endpoint engine-agnostic: Whisper can ingest any
    # format, while Parakeet expects WAV. FFmpeg is present in both API
    # images as a static binary.
    temp_path = None
    wav_path = None
    try:
        suffix = os.path.splitext(filename)[1] or ".tmp"
        temp_path = await asyncio.to_thread(_save_upload_to_temp, file.file, suffix)

        log.debug(f"Saved to temp file: {temp_path}")

        # Normalize to WAV (16kHz, mono, 16-bit) for engine compatibility
        wav_path = temp_path + ".wav"
        await asyncio.to_thread(_convert_to_pcm_wav, temp_path, wav_path)

        # One HTTP transcription at a time, like a single WebSocket identity.
        async with manager.user_semaphores[_HTTP_IDENTITY]:
            result = await asyncio.to_thread(manager.engine.transcribe, wav_path)

        # Same output gate as the WebSocket path. Transcript text is not
        # logged: HTTP callers cannot request incognito, so treat it as private.
        segments = sanitized_segments(result)
        text = " ".join(seg["text"] for seg in segments)
        log.success(
            f"Transcription completed in {result.processing_time:.2f}s ({len(text)} chars)"
        )

        return {
            "text": text,
            "language": result.language,
            "segments": segments,
            "processing_time": result.processing_time,
            "timestamp": time.time(),
        }

    except HTTPException:
        raise  # Client errors (400, 413) carry safe, specific messages
    except Exception as e:
        ref = str(uuid.uuid4())[:8]
        log.error(f"Transcription failed [Ref: {ref}]: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription failed (ref {ref})")

    finally:
        for path in (temp_path, wav_path):
            if path:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time transcription"""
    if not manager:
        log.error("WebSocket connection failed: ConnectionManager not initialized.")
        await websocket.close(code=1011)
        return

    # Authentication is performed during the 'hello' handshake phase
    # within manager.connect / handle_message to keep tokens out of URL logs.
    await manager.connect(websocket)
    try:
        while True:
            # Receive both text and bytes
            message = await websocket.receive()
            if "text" in message:
                await manager.handle_message(websocket, message["text"])
            elif "bytes" in message:
                await manager.handle_message(websocket, message["bytes"])

    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except RuntimeError:
        # Happens when server closes the connection while loop is waiting for receive()
        manager.disconnect(websocket)
    except Exception as e:
        log.error(f"Unexpected WebSocket error: {e}")
        manager.disconnect(websocket)
