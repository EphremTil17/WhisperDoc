import asyncio
import time
from fastapi import WebSocket
from faster_whisper import WhisperModel
import tempfile
import wave
import os

# Import the configured logger
from logging_config import log

# --- Configuration ---
# Max buffer size (in bytes) for 60 seconds of 16kHz, 16-bit mono audio
# 16000 samples/sec * 2 bytes/sample * 60 seconds = 1,920,000 bytes
MAX_BUFFER_SIZE = 1920000
INACTIVITY_TIMEOUT = 30  # seconds

class ConnectionManager:
    def __init__(self, model: WhisperModel):
        self.active_connections = {}
        self.model = model
        self.cleanup_task = asyncio.create_task(self._cleanup_inactive_connections())

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[websocket] = {"buffer": bytearray(), "last_activity": time.time()}
        log.info(f"WebSocket client connected: {websocket.client}")

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            del self.active_connections[websocket]
            log.info(f"WebSocket client disconnected: {websocket.client}")

    async def handle_message(self, websocket: WebSocket, message):
        if websocket not in self.active_connections:
            log.warn(f"Received message from unknown client: {websocket.client}")
            return

        self.active_connections[websocket]["last_activity"] = time.time()

        if isinstance(message, str):
            if message == '{"event": "end-of-stream"}':
                log.info(f"Received end-of-stream from {websocket.client}")
                await self.transcribe_and_send(websocket)
            else:
                log.warn(f"Received invalid text message from {websocket.client}: {message}")
                await websocket.send_text("Invalid message")
        elif isinstance(message, bytes):
            buffer = self.active_connections[websocket]["buffer"]
            if len(buffer) < MAX_BUFFER_SIZE:
                buffer.extend(message)
            else:
                log.warn(f"Audio buffer limit reached for client {websocket.client}. Closing connection.")
                await websocket.close(code=1009, reason="Audio buffer limit reached")
                self.disconnect(websocket)

    async def transcribe_and_send(self, websocket: WebSocket):
        connection_data = self.active_connections.get(websocket)
        if not connection_data or not connection_data["buffer"]:
            log.warn(f"No audio data received from {websocket.client} before transcription request.")
            await websocket.send_text('{"error": "No audio data received."}')
            return

        audio_data = connection_data["buffer"]
        # Reset buffer
        connection_data["buffer"] = bytearray()

        try:
            # Create a temporary WAV file
            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_audio_file:
                with wave.open(temp_audio_file, 'wb') as wav_file:
                    wav_file.setnchannels(1)  # Mono
                    wav_file.setsampwidth(2)  # 16-bit
                    wav_file.setframerate(16000)  # 16kHz
                    wav_file.writeframes(audio_data)
                temp_path = temp_audio_file.name
            
            log.info(f"Transcribing {len(audio_data)} bytes of audio from {websocket.client} saved to {temp_path}")

            # Transcribe
            segments, info = self.model.transcribe(temp_path, language="en")
            
            # Collect all segments
            segments_list = list(segments)
            full_text = " ".join([segment.text.strip() for segment in segments_list])

            log.success(f"Transcription successful for {websocket.client}: {full_text[:50]}...")

            # Send transcription
            await websocket.send_json({
                "text": full_text,
                "language": info.language,
                "duration": info.duration,
            })

        except Exception as e:
            log.error(f"Transcription failed for {websocket.client}: {e}")
            await websocket.send_text(f'{{"error": "Transcription failed: {e}"}}')
        finally:
            # Clean up temp file
            if 'temp_path' in locals() and os.path.exists(temp_path):
                os.unlink(temp_path)
                log.debug(f"Cleaned up temp file: {temp_path}")

    async def _cleanup_inactive_connections(self):
        while True:
            await asyncio.sleep(10)  # Check every 10 seconds
            now = time.time()
            inactive_clients = []
            for websocket, data in self.active_connections.items():
                if now - data["last_activity"] > INACTIVITY_TIMEOUT:
                    inactive_clients.append(websocket)
            
            for websocket in inactive_clients:
                log.warn(f"Closing inactive connection for client {websocket.client}")
                await websocket.close(code=1000, reason="Inactivity timeout")
                self.disconnect(websocket)