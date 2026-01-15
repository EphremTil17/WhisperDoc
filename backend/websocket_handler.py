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

# Project dependencies
from auth import validate_token
from logging_config import log

# --- Configuration ---
# Max buffer size (in bytes) for 5 minutes of 16kHz, 16-bit mono audio
MAX_BUFFER_SIZE = 9600000
MAX_CONNECTIONS = 10  # Limit concurrent clients to protect GPU/RAM
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
            self.model = WhisperModel(
                self.model_name, 
                device=self.device, 
                compute_type=self.compute_type,
                download_root="/app/model-cache"  # Force usage of mounted volume
            )
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
    def __init__(self, model_manager: ModelManager, app_version: str):
        self.active_connections = {}
        self.model_manager = model_manager
        self.app_version = app_version
        # Start the background cleanup task
        self.cleanup_task = asyncio.create_task(self._cleanup_inactive_connections())
        log.info(f"ConnectionManager initialized. Max Connections: {MAX_CONNECTIONS}")

    async def _cleanup_inactive_connections(self):
        """Background task to close connections that are idle or failed to handshake."""
        while True:
            try:
                await asyncio.sleep(10)  # Check more frequently
                now = time.time()
                to_disconnect = []

                for websocket, data in self.active_connections.items():
                    idle_time = now - data["last_activity"]
                    
                    # Rule 1: Kill un-handshaked connections after 15 seconds
                    if not data["handshake_completed"] and idle_time > 15:
                        log.warning(f"Closing un-handshaked connection from {websocket.client} (Timeout)")
                        to_disconnect.append((websocket, 1008, "Handshake timeout"))
                        continue

                    # Rule 2: Kill idle connections after IDLE_TIMEOUT_SECONDS
                    if idle_time > IDLE_TIMEOUT_SECONDS:
                        log.warning(f"Closing inactive connection for client {websocket.client}")
                        to_disconnect.append((websocket, 4000, "Inactivity timeout"))

                for websocket, code, reason in to_disconnect:
                    try:
                        await websocket.close(code=code, reason=reason)
                    except:
                        pass
                    self.disconnect(websocket)
            except Exception as e:
                log.error(f"Error in cleanup task: {e}")

    async def connect(self, websocket: WebSocket):
        if len(self.active_connections) >= MAX_CONNECTIONS:
            log.warning(f"Connection rejected for {websocket.client}: Max connections reached.")
            await websocket.close(code=1008, reason="Max concurrent connections reached")
            return

        await websocket.accept()
        # Create a unique short ID for this connection to track logs
        conn_id = str(id(websocket))[-4:]
        now = time.time()
        self.active_connections[websocket] = {
            "buffer": bytearray(), 
            "last_activity": now,
            "connected_at": now,
            "handshake_completed": False,
            "id": conn_id,
            "incognito": False
        }
        log.info(f"[{conn_id}] WebSocket client connected from {websocket.client.host}")
        
        # Send Server Hello
        await websocket.send_json({
            "event": "hello",
            "server": "WhisperDoc Backend",
            "version": self.app_version,
            "status": "ready" if self.model_manager.model else "idle",
            "cid": conn_id
        })

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            conn_id = self.active_connections.get(websocket, {}).get("id", "????")
            del self.active_connections[websocket]
            log.info(f"[{conn_id}] WebSocket client disconnected: {websocket.client}")

    async def handle_message(self, websocket: WebSocket, message):
        connection_data = self.active_connections.get(websocket)
        if not connection_data:
            return

        # Update activity timestamp
        connection_data["last_activity"] = time.time()
        conn_id = connection_data.get("id", "????")
        handshake_done = connection_data.get("handshake_completed", False)

        # --- PROTOCOL STATE MACHINE ---
        if isinstance(message, str):
            try:
                # 1. Parsing & Sanity Check
                try:
                    data = json.loads(message)
                except json.JSONDecodeError:
                    log.warning(f"[{conn_id}] Protocol Violation: Malformed JSON. Terminating.")
                    await websocket.close(code=1008, reason="Malformed JSON")
                    return

                event = data.get("event")

                # 2. Handle Authentication State (Pre-Handshake)
                if not handshake_done:
                    if event != "hello":
                        log.warning(f"[{conn_id}] Protocol Violation: Expected 'hello' event, got '{event}'. Disconnecting.")
                        await websocket.close(code=1008, reason="Handshake required")
                        return

                    # Process Handshake
                    token = data.get("token")
                    if not validate_token(token):
                        log.warning(f"[{conn_id}] Authentication Failed: Invalid Key.")
                        await websocket.send_json({"event": "error", "code": 403, "message": "Auth Failed"})
                        await websocket.close(code=1008)
                        return

                    # Successful Auth
                    connection_data["handshake_completed"] = True
                    connection_data["incognito"] = data.get("incognito", False)
                    
                    client_info = data.get("client", "unknown")
                    client_ver = data.get("version", "unknown")
                    log.info(f"[{conn_id}] Handshake Verified. Client: {client_info} (v{client_ver}) Incognito: {connection_data['incognito']}")

                    await websocket.send_json({
                        "event": "authenticated",
                        "status": "success",
                        "cid": conn_id
                    })
                    return

                # 3. Handle Authenticated State (Post-Handshake)
                if event == "hello":
                    log.warning(f"[{conn_id}] Protocol Violation: Duplicate 'hello' attempt. Terminating.")
                    await websocket.close(code=1008, reason="Handshake already completed")
                    return
                
                if event == "end-of-stream":
                    log.info(f"[{conn_id}] Received EOS triggered by client.")
                    await self.transcribe_and_send(websocket)
                elif event == "ping":
                    await websocket.send_json({"event": "pong"})
                else:
                    log.warning(f"[{conn_id}] Protocol Violation: Unknown event '{event}'. Closing.")
                    await websocket.close(code=1008, reason=f"Invalid event: {event}")
            
            except Exception as e:
                log.error(f"[{conn_id}] Error in text handler: {e}")
                try: await websocket.close(code=1011)
                except: pass

        elif isinstance(message, bytes):
            # Strict Enforcement: No audio data allowed before authentication
            if not handshake_done:
                log.warning(f"[{conn_id}] Protocol Violation: Binary data before handshake. Disconnecting.")
                await websocket.close(code=1008, reason="Handshake required")
                return
            
            # Process Valid Audio
            buffer = connection_data["buffer"]
            if len(buffer) < MAX_BUFFER_SIZE:
                buffer.extend(message)
            else:
                log.warning(f"[{conn_id}] Resource Exhaustion: Buffer limit reached. Closing.")
                await websocket.close(code=1009, reason="Buffer limit exceeded")
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

        temp_path = None
        try:
            # Create a temporary WAV file
            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_audio_file:
                with wave.open(temp_audio_file, 'wb') as wav_file:
                    wav_file.setnchannels(1)  # Mono
                    wav_file.setsampwidth(2)  # 16-bit
                    wav_file.setframerate(16000)  # 16kHz
                    wav_file.writeframes(audio_data)
                temp_path = temp_audio_file.name
            
            log.info(f"Transcribing {len(audio_data)} bytes from {websocket.client.host}")

            def run_transcription():
                segments, info = model.transcribe(temp_path, language="en")
                return list(segments), info

            segments_list, info = await asyncio.to_thread(run_transcription)
            full_text = " ".join([segment.text.strip() for segment in segments_list])

            # Conditional Logging based on Privacy Mode
            is_incognito = connection_data.get("incognito", False)
            if is_incognito:
                log.log("PRIVACY", f"Transcription completed [REDACTED]")
            else:
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
            if temp_path and os.path.exists(temp_path):
                os.unlink(temp_path)