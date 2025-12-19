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

# Import the WebSocket handler
from websocket_handler import ConnectionManager

# Global model instance
model: Optional[WhisperModel] = None
manager: Optional[ConnectionManager] = None

app = FastAPI(
    title="WhisperDoc API",
    description="Speech-to-text transcription service using faster-whisper",
    version="1.0.0"
)

@app.on_event("startup")
async def startup_event():
    """Load the Whisper model and initialize the connection manager on startup"""
    global model, manager
    log.info("Starting WhisperDoc API server...")
    
    try:
        log.info(f"Loading Whisper model ({MODEL_NAME})...")
        start_time = time.time()
        
        # Load model with configuration from environment
        model = WhisperModel(MODEL_NAME, device=MODEL_DEVICE, compute_type=MODEL_COMPUTE_TYPE)
        manager = ConnectionManager(model)
        
        load_time = time.time() - start_time
        log.success(f"Model loaded successfully in {load_time:.2f}s")
        log.info(f"Model device: {model.model.device}")
        
    except Exception as e:
        log.error(f"Failed to load model: {e}")
        # Try CPU fallback
        try:
            log.info("Attempting CPU fallback...")
            model = WhisperModel(MODEL_NAME, device="cpu")
            manager = ConnectionManager(model)
            log.success("Model loaded on CPU")
        except Exception as cpu_error:
            log.error(f"CPU fallback also failed: {cpu_error}")
            model = None
            manager = None

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    if model is None:
        log.warning("Health check failed: model not loaded.")
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "message": "Whisper model not loaded",
                "timestamp": time.time()
            }
        )
    
    log.info("Health check passed.")
    return {
        "status": "healthy",
        "model_loaded": True,
        "device": str(model.model.device) if hasattr(model.model, 'device') else "unknown",
        "timestamp": time.time()
    }

@app.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    """Transcribe uploaded audio file"""
    if model is None:
        log.error("Transcription failed: model not available.")
        raise HTTPException(status_code=503, detail="Whisper model not available")
    
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

@app.post("/log")
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
    except Exception as e:
        log.error(f"WebSocket error: {e}")
        manager.disconnect(websocket)

