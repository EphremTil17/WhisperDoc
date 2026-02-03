#!/usr/bin/env python3
"""
Minimal FastAPI server for speech-to-text transcription
Uses faster-whisper with GPU acceleration
"""

import os
import time
import asyncio
import sys

# Initialize uvloop for performance before anything else
try:
    import uvloop
    asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
except ImportError:
    pass

from typing import Optional, List
from datetime import datetime, timezone
from fastapi import FastAPI, File, UploadFile, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import ORJSONResponse as JSONResponse
from pydantic import BaseModel
import uuid
import ctranslate2
import tempfile
import shutil

# Import the configured logger
from logging_config import log

# --- Pydantic Models for Log Ingestion ---
class RemoteLogRecord(BaseModel):
    source: str
    level: str
    message: str
    timestamp: str

class LogBatch(BaseModel):
    logs: List[RemoteLogRecord]


# Load configuration from environment variables
API_PORT = int(os.getenv('API_PORT', '9989'))
MODEL_NAME = os.getenv('MODEL_NAME', 'medium.en')
MODEL_DEVICE = os.getenv('MODEL_DEVICE', 'cuda')
MODEL_COMPUTE_TYPE = os.getenv('MODEL_COMPUTE_TYPE', 'float16')

# Read version from environment variable (Docker)
APP_VERSION = os.getenv("WHISPER_DOC_VERSION", "0.0.0-dev")

# Versioning requirements for clients
# Minimum: Blocking version (below this, client is rejected)
# Security: Advisory version (below this, client is prompted to update)
MIN_CLIENT_VERSION = os.getenv("MIN_CLIENT_VERSION", "0.0.0")
SEC_CLIENT_VERSION = os.getenv("SEC_CLIENT_VERSION", "0.0.0")

# --- Security & Validation Configuration ---
MAX_FILE_SIZE = 25 * 1024 * 1024  # 25MB limit for single HTTP uploads

from fastapi import Depends
from auth import get_api_key, verify_api_key, validate_token, warmup_oidc
from engine.model_manager import ModelManager
from protocol.websocket_handler import ConnectionManager

from contextlib import asynccontextmanager

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
    log.info(f"Version Requirements: MIN={MIN_CLIENT_VERSION}, ADVISORY={SEC_CLIENT_VERSION}")
    
    try:
        # Enforce "Fail Secure" Policy
        get_api_key() # Will raise RuntimeError if no key is set
        
        log.info(f"Initializing Model Manager ({MODEL_NAME})...")
        
        # Initialize ModelManager (which handles loading/unloading)
        model_manager = ModelManager(MODEL_NAME, device=MODEL_DEVICE, compute_type=MODEL_COMPUTE_TYPE)
        
        # Initialize the connection manager
        manager = ConnectionManager(
            model_manager, 
            app_version=APP_VERSION,
            min_client_version=MIN_CLIENT_VERSION,
            sec_client_version=SEC_CLIENT_VERSION
        )
        
        # Warmup OIDC (graceful degradation: logs warnings if provider unreachable)
        warmup_oidc()
        
        log.success(f"System initialized successfully.")
        
    except Exception as e:
        log.error(f"Failed to initialize backend: {e}")
        manager = None
        
    yield  # Server runs here
    
    # --- Shutdown Logic ---
    log.info("Shutting down WhisperDoc API server...")
    if manager and manager.model_manager:
        manager.model_manager.unload_model()
    log.success("Cleanup completed.")

app = FastAPI(
    title="WhisperDoc API",
    description="Speech-to-text transcription service using faster-whisper",
    version=APP_VERSION,
    lifespan=lifespan
)

# --- Infrastructure Hardening (Middleware & Security) ---
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.middleware.gzip import GZipMiddleware

# Compress responses to save bandwidth on large transcription results
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Configure CORS
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"], # Restrict methods
    allow_headers=["Authorization", "Content-Type"], # Restrict headers
)
# Ensure the app trusts ONLY the local proxy (Cloudflare Tunnel)
# Tunnel runs on the same loop/host, so we only trust 127.0.0.1
ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS", "localhost").split(",")
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
            "ref": error_id
        }
    )

@app.get("/health")
async def health_check():
    """Opaque health check to prevent information disclosure."""
    if manager is None or manager.model_manager is None:
        return JSONResponse(status_code=503, content={"status": "uninitialized"})
    
    # Minimal check for GPU - don't leak device details
    try:
        cuda_available = ctranslate2.get_cuda_device_count() > 0
    except:
        cuda_available = False
    
    # Return binary status only
    status_code = 200 if cuda_available else 503
    return JSONResponse(
        status_code=status_code,
        content={
            "status": "online" if cuda_available else "degraded",
            "timestamp": int(time.time())
        }
    )

@app.post("/transcribe", dependencies=[Depends(verify_api_key)])
async def transcribe_audio(file: UploadFile = File(...)):
    """Transcribe uploaded audio file"""
    if manager is None:
        raise HTTPException(status_code=503, detail="System not initialized")
    
    # Load model if needed
    try:
        model, _ = manager.model_manager.get_model()
    except Exception as e:
        log.error(f"Failed to load model for HTTP request: {e}")
        raise HTTPException(status_code=500, detail="Failed to load model")
    
    # Validate file type
    if not file.content_type or not file.content_type.startswith('audio/'):
        # Also accept common audio file extensions
        allowed_extensions = ['.wav', '.mp3', '.m4a', '.flac', '.ogg']
        if not any(file.filename.lower().endswith(ext) for ext in allowed_extensions):
            log.warning(f"Invalid file type received: {file.content_type}")
            raise HTTPException(
                status_code=400, 
                detail=f"Invalid file type. Expected audio file, got: {file.content_type}"
            )
    
    log.info(f"Processing file: {file.filename} ({file.content_type})")
    
    # Optional: Check file size if content-length is provided
    # Note: For UploadFile, we may need to read it to be 100% sure
    file.file.seek(0, os.SEEK_END)
    file_size = file.file.tell()
    file.file.seek(0)
    
    if file_size > MAX_FILE_SIZE:
        log.warning(f"File upload rejected: {file_size} bytes exceeds limit of {MAX_FILE_SIZE}")
        raise HTTPException(status_code=413, detail=f"File too large. Maximum size is {MAX_FILE_SIZE} bytes.")
    
    # Save uploaded file temporarily
    with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file.filename)[1]) as temp_file:
        try:
            # Copy uploaded file to temp file
            shutil.copyfileobj(file.file, temp_file)
            temp_path = temp_file.name
            
            log.debug(f"Saved to temp file: {temp_path}")
            
            # Transcribe in a thread pool to avoid blocking the event loop
            start_time = time.time()
            
            def run_transcription():
                segments, info = model.transcribe(temp_path, language="en")
                return list(segments), info

            segments_list, info = await asyncio.to_thread(run_transcription)
            transcribe_time = time.time() - start_time
            
            # Build response
            full_text = " ".join([segment.text.strip() for segment in segments_list])
            
            log.success(f"Transcription completed in {transcribe_time:.2f}s")
            log.info(f"Result: {full_text[:100]}{'...' if len(full_text) > 100 else ''}")
            
            return {
                "text": full_text,
                "language": info.language,
                "language_probability": info.language_probability,
                "duration": info.duration,
                "segments": [
                    {
                        "start": segment.start,
                        "end": segment.end,
                        "text": segment.text.strip()
                    }
                    for segment in segments_list
                ],
                "processing_time": transcribe_time,
                "timestamp": time.time()
            }
            
        except Exception as e:
            log.error(f"Transcription failed: {e}")
            raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")
        
        finally:
            # Clean up temp file
            try:
                os.unlink(temp_path)
                log.debug(f"Cleaned up temp file: {temp_path}")
            except Exception as e:
                log.warning(f"Could not clean up temp file {temp_path}: {e}")

@app.post("/log", dependencies=[Depends(verify_api_key)])
async def ingest_logs(batch: LogBatch):
    """Receive and process a batch of log records from a remote client."""
    log.info(f"Received log batch with {len(batch.logs)} records.")
    for record in batch.logs:
        # Convert timestamp to datetime object
        client_time = datetime.fromisoformat(record.timestamp)
        
        # Use opt(record=...) to properly override the record's time
        log.opt(record={"time": client_time}).bind(source=record.source).log(
            record.level, 
            record.message
        )
    return {"status": "ok"}


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time transcription"""
    if not manager:
        log.error("WebSocket connection failed: ConnectionManager not initialized.")
        await websocket.close(code=1011)
        return

    # Connection is upgraded unconditionally. 
    # Authentication is now performed during the 'hello' handshake phase 
    # within the manager.connect / handle_message logic to keep tokens out of URL logs.
    await manager.connect(websocket)
    try:
        while True:
            # Receive both text and bytes
            message = await websocket.receive()
            if 'text' in message:
                await manager.handle_message(websocket, message['text'])
            elif 'bytes' in message:
                await manager.handle_message(websocket, message['bytes'])

    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except RuntimeError:
        # Happens when server closes the connection while loop is waiting for receive()
        manager.disconnect(websocket)
    except Exception as e:
        log.error(f"Unexpected WebSocket error: {e}")
        manager.disconnect(websocket)

