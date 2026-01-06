import asyncio
import time
import tempfile
import wave
import os
import json
import gc
import torch
from fastapi import WebSocket
from faster_whisper import WhisperModel

# Import the configured logger
from logging_config import log

# --- Configuration ---
# Max buffer size (in bytes) for 5 minutes of 16kHz, 16-bit mono audio
MAX_BUFFER_SIZE = 9600000
IDLE_TIMEOUT_SECONDS = 300  # 5 minutes idle timeout (Connection)
MODEL_TIMEOUT_SECONDS = 1800  # 30 minutes idle timeout (GPU Model)

class ModelManager:
    """Manages the lifecycle of the WhisperModel for dynamic GPU loading."""
    def __init__(self, model_name, device, compute_type):
        self.model_name = model_name
        self.device = device
        self.compute_type = compute_type
        self.model = None
        self.last_used = time.time()
        
        # Initial load
        self.load_model()
        
        # Start cleanup task
        asyncio.create_task(self._monitor_usage())

    def load_model(self):
        if self.model: return
        log.info(f"Loading Whisper model ({self.model_name}) into {self.device}...")
        try:
            start = time.time()
            self.model = WhisperModel(self.model_name, device=self.device, compute_type=self.compute_type)
            log.success(f"Model loaded in {time.time() - start:.2f}s")
        except Exception as e:
            log.error(f"Failed to load model: {e}")
            raise

    def unload_model(self):
        if not self.model: return
        log.info("Unloading IDLE model from GPU...")
        del self.model
        self.model = None
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        log.success("Model unloaded. GPU memory freed.")

    def get_model(self):
        self.last_used = time.time()
        if not self.model:
            self.load_model()
            return self.model, True # Tuple: (model, was_reloaded)
        return self.model, False

    async def _monitor_usage(self):
        while True:
            await asyncio.sleep(60) # Check every minute
            if self.model and (time.time() - self.last_used > MODEL_TIMEOUT_SECONDS):
                self.unload_model()


class ConnectionManager:
    def __init__(self, model_manager: ModelManager):
        self.active_connections = {}
        self.model_manager = model_manager
        # Start the background cleanup task
        self.cleanup_task = asyncio.create_task(self._cleanup_inactive_connections())
        log.info(f"ConnectionManager initialized. Connection Idle: {IDLE_TIMEOUT_SECONDS}s, Model Idle: {MODEL_TIMEOUT_SECONDS}s")

    async def _cleanup_inactive_connections(self):
        """Background task to close connections that have been idle for too long."""
        while True:
            try:
                await asyncio.sleep(30)  # Check every 30 seconds
                now = time.time()
                to_disconnect = []

                for websocket, data in self.active_connections.items():
                    if now - data["last_activity"] > IDLE_TIMEOUT_SECONDS:
                        to_disconnect.append(websocket)

                for websocket in to_disconnect:
                    log.warning(f"Closing inactive connection for client {websocket.client}")
                    try:
                        await websocket.close(code=4000, reason="Inactivity timeout")
                    except:
                        pass
                    self.disconnect(websocket)
            except Exception as e:
                log.error(f"Error in cleanup task: {e}")

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[websocket] = {
            "buffer": bytearray(), 
            "last_activity": time.time(),
            "handshake_completed": False
        }
        log.info(f"WebSocket client connected: {websocket.client}")
        
        # Send Server Hello
        await websocket.send_json({
            "event": "hello",
            "server": "WhisperDoc Backend",
            "version": "1.0.0",
            "status": "ready" if self.model_manager.model else "idle"
        })

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            del self.active_connections[websocket]
            log.info(f"WebSocket client disconnected: {websocket.client}")

    async def handle_message(self, websocket: WebSocket, message):
        if websocket not in self.active_connections:
            return

        # Update activity timestamp for any message received
        self.active_connections[websocket]["last_activity"] = time.time()

        if isinstance(message, str):
            try:
                # Handle potentially JSON-encoded control messages
                if message.startswith('{'):
                    data = json.loads(message)
                    event = data.get("event")
                    
                    if event == "hello":
                        self.active_connections[websocket]["handshake_completed"] = True
                        client_info = data.get("client", "unknown")
                        log.info(f"Handshake complete. Client: {client_info}")
                        
                    elif event == "end-of-stream":
                        log.info(f"Received end-of-stream from {websocket.client}")
                        await self.transcribe_and_send(websocket)
                    elif event == "ping":
                        await websocket.send_json({"event": "pong"})
                    else:
                        log.warning(f"Unknown event '{event}' from {websocket.client}")
                else:
                    # Legacy support for plain-text '{"event": "end-of-stream"}'
                    if 'end-of-stream' in message:
                         await self.transcribe_and_send(websocket)
                    else:
                        log.warning(f"Received invalid text message from {websocket.client}: {message[:100]}...")
            except Exception as e:
                log.error(f"Error handling text message: {e}")
                
        elif isinstance(message, bytes):
            buffer = self.active_connections[websocket]["buffer"]
            if len(buffer) < MAX_BUFFER_SIZE:
                buffer.extend(message)
            else:
                log.warning(f"Audio buffer limit reached for {websocket.client}. Closing.")
                await websocket.close(code=1009, reason="Audio buffer limit reached")
                self.disconnect(websocket)

    async def transcribe_and_send(self, websocket: WebSocket):
        connection_data = self.active_connections.get(websocket)
        if not connection_data or not connection_data["buffer"]:
            log.warning(f"No audio data received from {websocket.client}")
            await websocket.send_json({"event": "error", "code": "NO_AUDIO", "message": "No audio data received"})
            return

        audio_data = connection_data["buffer"]
        connection_data["buffer"] = bytearray()  # Reset buffer

        # --- Dynamic Model Retrieval ---
        try:
            model, was_reloaded = self.model_manager.get_model()
            
            if was_reloaded:
                # Notify client that we just woke up the GPU
                await websocket.send_json({
                    "event": "status", 
                    "code": "MODEL_LOADING", 
                    "message": "Waking up GPU..."
                })
        except Exception as e:
            log.error(f"Model load failed: {e}")
            await websocket.send_json({"event": "error", "code": "MODEL_ERROR", "message": "Failed to load model"})
            return
        # -------------------------------

        try:
            # Create a temporary WAV file
            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_audio_file:
                with wave.open(temp_audio_file, 'wb') as wav_file:
                    wav_file.setnchannels(1)  # Mono
                    wav_file.setsampwidth(2)  # 16-bit
                    wav_file.setframerate(16000)  # 16kHz
                    wav_file.writeframes(audio_data)
                temp_path = temp_audio_file.name
            
            log.info(f"Transcribing {len(audio_data)} bytes for {websocket.client}")

            def run_transcription():
                segments, info = model.transcribe(temp_path, language="en")
                return list(segments), info

            segments_list, info = await asyncio.to_thread(run_transcription)
            full_text = " ".join([segment.text.strip() for segment in segments_list])

            log.success(f"Transcription successful: {full_text[:50]}...")

            await websocket.send_json({
                "text": full_text,
                "language": info.language,
                "duration": info.duration,
            })

        except Exception as e:
            log.error(f"Transcription failed: {e}")
            await websocket.send_json({
                "event": "error", 
                "code": "TRANSCRIPTION_FAILED", 
                "message": str(e)
            })
        finally:
            if 'temp_path' in locals() and os.path.exists(temp_path):
                os.unlink(temp_path)