import asyncio
import websockets
import logging
import argparse
import os
import json

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

import asyncio
import websockets
import logging
import argparse
import os
import json
import wave

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def test_websocket_transcription(audio_path: str):
    uri = "ws://localhost:9989/ws"

    if not os.path.exists(audio_path):
        logger.error(f"Audio file not found: {audio_path}")
        return False

    try:
        async with websockets.connect(uri) as websocket:
            logger.info(f"Connected to {uri}")

            if audio_path.lower().endswith('.wav'):
                logger.info(f"Streaming PCM frames from WAV: {audio_path}")
                with wave.open(audio_path, 'rb') as wf:
                    # Verify it matches server expectations (16kHz, Mono, 16-bit)
                    if wf.getnchannels() != 1 or wf.getframerate() != 16000 or wf.getsampwidth() != 2:
                        logger.warning("WAV file format doesn't match server expectations (16kHz, Mono, S16LE).")
                        logger.warning("Transcription might fail or be inaccurate.")
                    
                    while True:
                        data = wf.readframes(1024)
                        if not data:
                            break
                        await websocket.send(data)
                        await asyncio.sleep(0.01) # Simulate real-time
            else:
                logger.warning(f"Sending raw bytes from non-WAV file: {audio_path}")
                logger.warning("If this is a compressed format (FLAC, MP3), transcription WILL fail.")
                with open(audio_path, 'rb') as f:
                    while True:
                        chunk = f.read(4096)
                        if not chunk:
                            break
                        await websocket.send(chunk)
                        await asyncio.sleep(0.01)

            # Send end-of-stream message
            await websocket.send('{"event": "end-of-stream"}')
            logger.info("Sent end-of-stream message.")

            # Receive the transcription
            response = await websocket.recv()
            logger.info(f"Received response: {response}")

            # Verify the response
            try:
                transcription_data = json.loads(response)
                if "text" in transcription_data and transcription_data["text"]:
                    logger.info("✅ WebSocket transcription test passed!")
                    logger.info(f"Transcription: {transcription_data['text']}")
                    return True
                else:
                    logger.error(f"❌ WebSocket transcription test failed! Invalid response: {response}")
                    return False
            except json.JSONDecodeError:
                logger.error(f"❌ WebSocket transcription test failed! Invalid JSON response: {response}")
                return False

    except Exception as e:
        logger.error(f"❌ WebSocket connection failed: {e}")
        return False

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test WebSocket transcription")
    parser.add_argument("--file", type=str, default="assets/jfk.flac", help="Path to the audio file to transcribe")
    args = parser.parse_args()

    if asyncio.run(test_websocket_transcription(args.file)):
        # Exit with success code
        exit(0)
    else:
        # Exit with failure code
        exit(1)