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
from datetime import datetime
from typing import Annotated, List, Optional

from fastapi import (
    Depends,
    FastAPI,
    File,
    HTTPException,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from auth import get_api_key, verify_api_key, warmup_oidc
from engine.engine_factory import create_engine
from logging_config import log
from protocol.websocket_handler import ConnectionManager

# Initialize uvloop for performance before anything else
try:
    uvloop = importlib.import_module("uvloop")
    asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
except ImportError:
    pass


# --- Pydantic Models for Log Ingestion ---
class RemoteLogRecord(BaseModel):
    source: str
    level: str
    message: str
    timestamp: str


class LogBatch(BaseModel):
    logs: List[RemoteLogRecord]


# Load configuration from environment variables
API_PORT = int(os.getenv("API_PORT", "9989"))

# Read version from environment variable (Docker)
APP_VERSION = os.getenv("WHISPER_DOC_VERSION", "0.0.0-dev")

# Versioning requirements for clients
# Minimum: Blocking version (below this, client is rejected)
# Security: Advisory version (below this, client is prompted to update)
MIN_CLIENT_VERSION = os.getenv("MIN_CLIENT_VERSION", "0.0.0")
SEC_CLIENT_VERSION = os.getenv("SEC_CLIENT_VERSION", "0.0.0")

# --- Security & Validation Configuration ---
MAX_FILE_SIZE = 25 * 1024 * 1024  # 25MB limit for single HTTP uploads

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

        # Warmup OIDC (graceful degradation: logs warnings if provider unreachable)
        warmup_oidc()

        log.success("System initialized successfully.")

    except Exception as e:
        log.error(f"Failed to initialize backend: {e}")
        manager = None

    yield  # Server runs here

    # --- Shutdown Logic ---
    log.info("Shutting down WhisperDoc API server...")
    if manager:
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


@app.get("/health")
async def health_check():
    """Opaque health check to prevent information disclosure."""
    if manager is None or manager.engine is None:
        return JSONResponse(status_code=503, content={"status": "uninitialized"})

    engine_ready = manager.engine.is_loaded()
    status_code = 200 if engine_ready else 503
    return JSONResponse(
        status_code=status_code,
        content={
            "status": "online" if engine_ready else "degraded",
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
    """Write uploaded file to a temporary path and validate size (sync, for use with to_thread).

    The size check is performed here (off the event loop) rather than in the
    async caller, avoiding a synchronous seek/tell on Starlette's
    SpooledTemporaryFile that would block the event loop for large uploads.
    """
    file_obj.seek(0, os.SEEK_END)
    file_size = file_obj.tell()
    file_obj.seek(0)

    if file_size > MAX_FILE_SIZE:
        log.warning(
            f"File upload rejected: {file_size} bytes exceeds limit of {MAX_FILE_SIZE}"
        )
        raise HTTPException(
            status_code=413,
            detail=f"File too large. Maximum size is {MAX_FILE_SIZE} bytes.",
        )

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        shutil.copyfileobj(file_obj, tmp)
        return tmp.name


@app.post(
    "/transcribe",
    dependencies=[Depends(verify_api_key)],
    responses={
        400: {"description": "Invalid file type or unsupported audio format"},
        413: {"description": "File too large"},
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
        proc = await asyncio.to_thread(
            subprocess.run,
            [
                "ffmpeg",
                "-y",
                "-i",
                temp_path,
                "-ar",
                "16000",
                "-ac",
                "1",
                "-sample_fmt",
                "s16",
                wav_path,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        if proc.returncode != 0:
            log.error(
                f"FFmpeg conversion failed: {proc.stderr.decode(errors='replace')}"
            )
            raise HTTPException(status_code=400, detail="Unsupported audio format")

        log.debug(
            f"FFmpeg conversion OK: {temp_path} → {wav_path} ({os.path.getsize(wav_path)} bytes)"
        )

        # Transcribe via engine (load-on-demand handled internally)
        result = await asyncio.to_thread(manager.engine.transcribe, wav_path)

        log.success(f"Transcription completed in {result.processing_time:.2f}s")
        log.info(
            f"Result: {result.text[:100]}{'...' if len(result.text) > 100 else ''}"
        )

        return {
            "text": result.text,
            "language": result.language,
            "segments": [
                {"start": s.start, "end": s.end, "text": s.text}
                for s in result.segments
            ],
            "processing_time": result.processing_time,
            "timestamp": time.time(),
        }

    except HTTPException:
        raise  # Re-raise client errors (400, 413) as-is
    except Exception as e:
        log.error(f"Transcription failed: {e}")
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

    finally:
        for path in (temp_path, wav_path):
            if path:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass


@app.post("/log", dependencies=[Depends(verify_api_key)])
async def ingest_logs(batch: LogBatch):
    """Receive and process a batch of log records from a remote client."""
    log.info(f"Received log batch with {len(batch.logs)} records.")
    for record in batch.logs:
        # Convert timestamp to datetime object
        client_time = datetime.fromisoformat(record.timestamp)

        def _inject_time(entry, _t=client_time):
            entry["time"] = _t

        # Patch the emitted record so the stored timestamp reflects the client event time.
        log.patch(_inject_time).bind(source=record.source).log(
            record.level, record.message
        )
    return {"status": "ok"}


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
