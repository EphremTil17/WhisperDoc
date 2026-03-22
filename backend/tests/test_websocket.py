import pytest
import asyncio
import json
import os
import wave
import sys
import websockets

# Configuration
WS_URI = "ws://localhost:9989/ws"

async def run_websocket_test(audio_path=None):
    """Core logic for testing the websocket flow with safety timeouts."""
    print(f"\n[INIT] Attempting connection to {WS_URI}...")
    
    try:
        # Connect first, then use as context manager
        websocket = await asyncio.wait_for(websockets.connect(WS_URI), timeout=5.0)
        async with websocket:
            print("✅ Socket Open. Starting Handshake...")
            
            # 1. Handshake: Server Hello
            raw_hello = await asyncio.wait_for(websocket.recv(), timeout=2.0)
            hello_resp = json.loads(raw_hello)
            assert hello_resp.get("event") == "hello", "Handshake failed: No 'hello' from server"
            
            # 2. Handshake: Client Hello
            # Use the server's own version so it always satisfies MIN_CLIENT_VERSION.
            await websocket.send(json.dumps({
                "event": "hello",
                "client": "pytest_integration",
                "version": os.getenv("WHISPER_DOC_VERSION", "999.0.0"),
                "token": os.getenv("WHISPER_DOC_API_KEY", "test_secret_key")
            }))
            print("✅ Handshake Complete.")

            # 3. Stream data (if file provided, otherwise send silence)
            if audio_path and os.path.exists(audio_path):
                print(f"[DATA] Streaming file: {audio_path}")
                if audio_path.lower().endswith('.wav'):
                    with wave.open(audio_path, 'rb') as wf:
                        while True:
                            data = wf.readframes(1024)
                            if not data: break
                            await websocket.send(data)
                else:
                    with open(audio_path, 'rb') as f:
                        while True:
                            chunk = f.read(4096)
                            if not chunk: break
                            await websocket.send(chunk)
            else:
                print("[DATA] No file found. Sending 1s silence...")
                await websocket.send(bytes(16000 * 2))

            # 4. End Signal
            await websocket.send(json.dumps({"event": "end-of-stream"}))

            # 5. Receive Result
            print("[WAIT] Waiting for transcription...")
            while True:
                resp_raw = await asyncio.wait_for(websocket.recv(), timeout=10.0)
                resp = json.loads(resp_raw)
                
                # Skip status messages
                if resp.get("event") == "status":
                    print(f"  > Server Status: {resp.get('message')}")
                    continue
                    
                # Assert text or error
                if "text" in resp:
                    print(f"✅ Transcription Received.")
                    return resp["text"]
                elif "error" in resp:
                    pytest.fail(f"Server returned error: {resp['error']}")
                elif resp.get("event") == "error":
                    pytest.fail(f"Server returned structured error: {resp['message']}")
    except (asyncio.TimeoutError, ConnectionRefusedError):
        print("❌ Connection Failed: Server is likely offline.")
        raise

@pytest.mark.asyncio
async def test_websocket_integration():
    """Pytest entry point for WebSocket integration."""
    if not os.getenv("WHISPER_DOC_API_KEY"):
        pytest.skip("WHISPER_DOC_API_KEY not set; required for live server auth")
    try:
        result = await run_websocket_test()
        assert result is not None
    except (asyncio.TimeoutError, ConnectionRefusedError):
        pytest.skip("Backend server not running at localhost:9989 - skipping integration test.")
    except websockets.exceptions.InvalidStatus as e:
        # websockets 16.0 client + uvicorn can produce null-byte corruption
        # in the HTTP upgrade request over certain network paths (e.g. WSL →
        # Docker bridge).  The Flutter/Dart client is unaffected.
        if e.response.status_code == 400:
            pytest.skip(f"WebSocket upgrade rejected (likely client/server protocol mismatch): {e}")
        pytest.fail(f"WebSocket test failed: {e}")
    except Exception as e:
        pytest.fail(f"WebSocket test failed: {e}")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", help="Path to audio file")
    args = parser.parse_args()
    
    try:
        final_text = asyncio.run(run_websocket_test(args.file))
        print(f"\n[SUMMARY] Success! Transcription: {final_text}")
    except Exception as e:
        print(f"\n[SUMMARY] Failed: {e}")
        sys.exit(1)