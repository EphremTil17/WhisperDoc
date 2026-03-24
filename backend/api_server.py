#!/usr/bin/env python3
"""
Minimal FastAPI server for speech-to-text transcription
Uses faster-whisper with GPU acceleration
"""

import asyncio
import importlib
import logging
import os
import subprocess
import time

# Initialize uvloop for performance before anything else
try:
    uvloop = importlib.import_module("uvloop")
    asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
except ImportError:
    pass

# ---------------------------------------------------------------------------
# h11 WebSocket Upgrade Fix: workaround for b" " object corruption after
# NeMo inference.
#
# After the first NeMo model.transcribe() call, the b" " bytes object used
# in uvicorn's handle_websocket_upgrade() is observed to change from 0x20
# to 0x00 (null byte).  Two independent code paths (h11_impl and our
# diagnostic patch) share the same id() for b" ", and both see the
# corruption — consistent with CPython interning the single-byte literal.
#
# The corrupted object breaks the h11→WebSocket handoff: the reconstructed
# request line becomes b"GET\x00/ws HTTP/1.1\r\n", which the websockets
# legacy HTTP parser rejects (split on b" " yields 2 parts instead of 3).
#
# Workaround: replace the b" " literal with bytes([0x20]) — a fresh heap
# allocation that does not share the corrupted object.
#
# Root cause is unconfirmed: the corruption is temporally correlated with
# NeMo inference and absent with the Whisper engine, but the specific
# native component (NeMo, PyTorch, gRPC, CUDA, numba) has not been
# identified via memory debugging tools.
#
# See git_exclude/NEMO_CPYTHON_MEMORY_CORRUPTION.md for full investigation.
# ---------------------------------------------------------------------------
try:
    from uvicorn.protocols.http import h11_impl as _h11mod

    # Pre-allocate the space byte outside the function to avoid per-call
    # allocation.  bytes([0x20]) creates a NEW object on the heap —
    # it does NOT resolve to the interned b" " singleton.
    _SAFE_SPACE = bytes([0x20])

    def _fixed_ws_upgrade(self, event):
        """Patched handle_websocket_upgrade that is immune to b" " corruption."""
        self.connections.discard(self)
        output = [
            event.method,
            _SAFE_SPACE,
            event.target,
            _SAFE_SPACE + b"HTTP/1.1\r\n",
        ]
        for name, value in self.headers:
            output += [name, b": ", value, b"\r\n"]
        output.append(b"\r\n")
        protocol = self.ws_protocol_class(
            config=self.config,
            server_state=self.server_state,
            app_state=self.app_state,
        )
        protocol.connection_made(self.transport)
        protocol.data_received(b"".join(output))
        self.transport.set_protocol(protocol)

    _h11mod.H11Protocol.handle_websocket_upgrade = _fixed_ws_upgrade

except Exception as exc:
    # If the patch fails (uvicorn internals changed), fall through —
    # the original code path still works when NeMo is not loaded.
    logging.getLogger("uvicorn.error").warning(
        "WhisperDoc h11 WebSocket upgrade patch was not applied; "
        "startup continues without the NeMo workaround: %s",
        exc,
    )

import shutil
import tempfile
import uuid
from datetime import datetime
from typing import List, Optional

from fastapi import (
    FastAPI,
    File,
    HTTPException,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.responses import JSONResponse

# Import the configured logger
from logging_config import log
from pydantic import BaseModel


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

from contextlib import asynccontextmanager

from auth import get_api_key, verify_api_key, warmup_oidc
from engine.engine_factory import create_engine
from fastapi import Depends
from protocol.websocket_handler import ConnectionManager

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

# Configure CORS — wildcard origins with allow_credentials=True violates the
# CORS spec (browsers reject it).  Credentials are only enabled when specific
# origins are configured via ALLOWED_ORIGINS.
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials="*" not in ALLOWED_ORIGINS,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)
# Trusted Host Check: default "*" disables the check (matches .env.template).
# Cloudflare Tunnel forwards with the public hostname as Host header, not
# "localhost", so restricting to "localhost" would silently reject all tunnel
# traffic.  The real auth gate is OIDC / API key, not the Host header.
# Restrict to specific hostnames only when running without a reverse proxy.
ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS", "*").split(",")
app.add_middleware(TrustedHostMiddleware, allowed_hosts=ALLOWED_HOSTS)


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


@app.post("/transcribe", dependencies=[Depends(verify_api_key)])
async def transcribe_audio(file: UploadFile = File(...)):
    """Transcribe uploaded audio file"""
    if manager is None:
        raise HTTPException(status_code=503, detail="System not initialized")

    filename = file.filename or "upload"

    # Validate file type
    if not file.content_type or not file.content_type.startswith("audio/"):
        # Also accept common audio file extensions
        allowed_extensions = [".wav", ".mp3", ".m4a", ".flac", ".ogg"]
        if not any(filename.lower().endswith(ext) for ext in allowed_extensions):
            log.warning(f"Invalid file type received: {file.content_type}")
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type. Expected audio file, got: {file.content_type}",
            )

    log.info(f"Processing file: {filename} ({file.content_type})")

    # Optional: Check file size if content-length is provided
    # Note: For UploadFile, we may need to read it to be 100% sure
    file.file.seek(0, os.SEEK_END)
    file_size = file.file.tell()
    file.file.seek(0)

    if file_size > MAX_FILE_SIZE:
        log.warning(
            f"File upload rejected: {file_size} bytes exceeds limit of {MAX_FILE_SIZE}"
        )
        raise HTTPException(
            status_code=413,
            detail=f"File too large. Maximum size is {MAX_FILE_SIZE} bytes.",
        )

    # Save uploaded file and normalize to 16kHz mono WAV via FFmpeg.
    # This makes the endpoint engine-agnostic: Whisper can ingest any
    # format, but NeMo (Parakeet) expects WAV.  FFmpeg is present in
    # both Docker images (static binary copied at build time).
    temp_path = None
    wav_path = None
    try:
        suffix = os.path.splitext(filename)[1] or ".tmp"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            shutil.copyfileobj(file.file, temp_file)
            temp_path = temp_file.name

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
            capture_output=True,
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
            if path and os.path.exists(path):
                try:
                    os.unlink(path)
                except Exception:
                    pass


@app.post("/log", dependencies=[Depends(verify_api_key)])
async def ingest_logs(batch: LogBatch):
    """Receive and process a batch of log records from a remote client."""
    log.info(f"Received log batch with {len(batch.logs)} records.")
    for record in batch.logs:
        # Convert timestamp to datetime object
        client_time = datetime.fromisoformat(record.timestamp)

        def _inject_time(entry):
            entry["time"] = client_time

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
