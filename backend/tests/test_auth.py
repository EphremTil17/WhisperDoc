import pytest
import os
from unittest.mock import patch, MagicMock

# Setup environment before importing app
# We use a fixture to patch the environment safely instead of global assignment

from fastapi.testclient import TestClient
from fastapi import WebSocketDisconnect
# Import app after setting env
from api_server import app
import auth

@pytest.fixture(autouse=True)
def setup_auth_env():
    """Ensure a consistent API key for unit tests in this file."""
    with patch.dict(os.environ, {"WHISPER_DOC_API_KEY": "test_secret_key"}):
        yield

client = TestClient(app)

def test_startup_fails_without_key():
    """Verify fail-secure enforcement on startup."""
    with patch.dict(os.environ, {"WHISPER_DOC_API_KEY": ""}):
        with pytest.raises(RuntimeError) as excinfo:
            auth.get_api_key()
        assert "FATAL" in str(excinfo.value)

def test_http_auth_valid():
    """Verify HTTP endpoints accept valid Bearer token."""
    with patch("api_server.manager", MagicMock()):
        response = client.post(
            "/transcribe", 
            headers={"Authorization": "Bearer test_secret_key"},
            files={"file": ("test.wav", b"RIFF....WAVE", "audio/wav")}
        )
        # Authentication passed if not 401. 
        # Might return 503 (System not initialized) or 400 (Invalid file) but NOT 401.
        assert response.status_code != 401

def test_http_auth_invalid_token():
    """Verify HTTP endpoints reject invalid token."""
    response = client.post(
        "/transcribe", 
        headers={"Authorization": "Bearer WRONG_KEY"},
        files={"file": ("test.wav", b"dummy", "audio/wav")}
    )
    assert response.status_code == 401
    assert "Invalid API Key" in response.json()["detail"]

def test_http_auth_missing_header():
    """Verify HTTP endpoints reject missing header."""
    response = client.post(
        "/transcribe", 
        files={"file": ("test.wav", b"dummy", "audio/wav")}
    )
    # FastAPI returns 401 when Security/Depends fails
    assert response.status_code == 401

def test_websocket_handshake_flow():
    """Verify complete handshake flow with valid token."""
    # Patch ModelManager to avoid loading real GPU model during test
    with patch("websocket_handler.ModelManager") as MockModelManager:
        mock_mm = MagicMock()
        mock_mm.model = "MockModel" # Simulate loaded model
        MockModelManager.return_value = mock_mm
        
        # Use a fresh client context to ensure startup_event runs with our patch
        with TestClient(app) as local_client:
            with local_client.websocket_connect("/ws") as websocket:
                # 1. Receive Server Hello
                data = websocket.receive_json()
                assert data["event"] == "hello"
                assert "server" in data
                
                # 2. Send Client Hello with Token
                websocket.send_json({
                    "event": "hello",
                    "client": "test_client",
                    "version": "1.0.0",
                    "token": "test_secret_key"
                })
                
                # 3. Receive Authenticated
                auth_response = websocket.receive_json()
                assert auth_response["event"] == "authenticated"
                
def test_websocket_handshake_invalid_token():
    """Verify WebSocket rejects invalid token during handshake."""
    with patch("websocket_handler.ModelManager"):
        with TestClient(app) as local_client:
            with local_client.websocket_connect("/ws") as websocket:
                # 1. Server Hello
                websocket.receive_json()
                
                # 2. Send Invalid Token
                websocket.send_json({
                    "event": "hello",
                    "token": "INVALID_KEY"
                })
                
                # 3. Expect Error Message
                error_resp = websocket.receive_json()
                assert error_resp["event"] == "error"
                assert "Authentication failed" in error_resp["message"]
                
                # 4. Expect Disconnect
                with pytest.raises(WebSocketDisconnect) as exc:
                    websocket.receive_text()
                assert exc.value.code == 1008
