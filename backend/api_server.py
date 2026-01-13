#!/usr/bin/env python3
"""
Minimal FastAPI server for speech-to-text transcription
Uses faster-whisper with GPU acceleration
"""

import os
import time
import asyncio
from typing import Optional, List
from datetime import datetime, timezone
from fastapi import FastAPI, File, UploadFile, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uvicorn
import uuid
import torch
from faster_whisper import WhisperModel
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
API_HOST = os.getenv('API_HOST', '0.0.0.0')
MODEL_NAME = os.getenv('MODEL_NAME', 'medium.en')
MODEL_DEVICE = os.getenv('MODEL_DEVICE', 'cuda')
MODEL_COMPUTE_TYPE = os.getenv('MODEL_COMPUTE_TYPE', 'float16')
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')

# Read version from environment variable (Docker)
APP_VERSION = os.getenv("WHISPER_DOC_VERSION", "0.0.0-dev")
WHISPER_DOC_API_KEY = os.getenv("WHISPER_DOC_API_KEY")

# --- Security & Validation Configuration ---
MAX_FILE_SIZE = 25 * 1024 * 1024  # 25MB limit for single HTTP uploads

from fastapi import Security, Depends
from fastapi.security.api_key import APIKeyHeader

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

async def verify_api_key(api_key: str = Security(api_key_header)):
    """Verifies the API key provided in the request headers."""
    # If no key is configured in the environment, we allow all for local dev
    if not WHISPER_DOC_API_KEY:
        return True
        
    if api_key == WHISPER_DOC_API_KEY:
        return True
        
    log.warning(f"Unauthorized access attempt with invalid API Key.")
    raise HTTPException(
        status_code=401,
        detail="Unauthorized: Invalid or missing API Key"
    )

# Import the WebSocket handler
from websocket_handler import ConnectionManager

# Global model instance
model: Optional[WhisperModel] = None
manager: Optional[ConnectionManager] = None

app = FastAPI(
    title="WhisperDoc API",
    description="Speech-to-text transcription service using faster-whisper",
    version=APP_VERSION
)

# --- Infrastructure Hardening (Middleware & Security) ---
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.middleware.gzip import GZipMiddleware

# Compress responses to save bandwidth on large transcription results
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Configure CORS for Cloudflare and Client security
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Adjust this for your specific deployment
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# Ensure the app trusts the proxy headers (Cloudflare)
# This is handled by uvicorn's proxy_headers, but we add host validation here
ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS", "*").split(",")
app.add_middleware(TrustedHostMiddleware, allowed_hosts=ALLOWED_HOSTS)

@app.on_event("startup")
async def startup_event():
    """Load the Whisper model and initialize the connection manager on startup"""
    global model, manager
    log.info("Starting WhisperDoc API server...")
    
    try:
        log.info(f"Initializing Model Manager ({MODEL_NAME})...")
        
        # Initialize ModelManager (which handles loading/unloading)
        from websocket_handler import ModelManager
        model_manager = ModelManager(MODEL_NAME, device=MODEL_DEVICE, compute_type=MODEL_COMPUTE_TYPE)
        
        # Pass manager to ConnectionManager
        manager = ConnectionManager(model_manager, app_version=APP_VERSION)
        
        # We no longer set 'model' globally as it's dynamic now
        model = None 
        
        log.success(f"System initialized successfully.")
        
    except Exception as e:
        log.error(f"Failed to initialize backend: {e}")
        model = None
        manager = None

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup resources on shutdown"""
    log.info("Shutting down WhisperDoc API server...")
    if manager and manager.model_manager:
        manager.model_manager.unload_model()
    log.success("Cleanup completed.")

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
    """Enhanced health check with GPU status verification"""
    if manager is None or manager.model_manager is None:
        log.warning("Health check failed: system not initialized.")
        return JSONResponse(
             status_code=503,
             content={"status": "unhealthy", "message": "System not initialized"}
        )
    
    # Check GPU "Zombification"
    cuda_available = torch.cuda.is_available() if torch.cuda.is_available() else False
    
    # Check if model is loaded (don't force load)
    is_loaded = manager.model_manager.model is not None
    
    status = "healthy" if cuda_available else "degraded"
    status_code = 200 if cuda_available else 500 # Return 500 if GPU is dead so Docker restarts
    
    log.info(f"Health check: {status}. Model loaded: {is_loaded}, CUDA: {cuda_available}")
    
    return JSONResponse(
        status_code=status_code,
        content={
            "status": status,
            "model_loaded": is_loaded,
            "cuda_available": cuda_available,
            "device": str(manager.model_manager.device),
            "timestamp": time.time(),
            "version": APP_VERSION
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

