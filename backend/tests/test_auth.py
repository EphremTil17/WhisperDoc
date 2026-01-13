import pytest
import os
from unittest.mock import patch, MagicMock

# Setup environment before importing app
os.environ["WHISPER_DOC_API_KEY"] = "test_secret_key"
os.environ["WHISPER_DOC_VERSION"] = "1.0.0-test"

from fastapi.testclient import TestClient
from fastapi import WebSocketDisconnect
# Import app after setting env
from api_server import app
import auth

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

def test_websocket_auth_valid_query_param():
    """Verify WebSocket accepts token in query param."""
    with patch("api_server.manager") as mock_manager:
        # Mock connect to doing nothing
        mock_manager.connect = MagicMock()
        
        with client.websocket_connect("/ws?token=test_secret_key") as websocket:
            # Connection should be open
            pass

def test_websocket_auth_valid_header():
    """Verify WebSocket accepts token in Authorization header."""
    with patch("api_server.manager") as mock_manager:
        mock_manager.connect = MagicMock()
        
        with client.websocket_connect("/ws", headers={"Authorization": "Bearer test_secret_key"}) as websocket:
            pass

def test_websocket_auth_reject_invalid_token():
    """Verify WebSocket rejects invalid token with 1008."""
    with pytest.raises(WebSocketDisconnect) as excinfo:
        with client.websocket_connect("/ws?token=WRONG_KEY") as websocket:
            pass
    assert excinfo.value.code == 1008

def test_websocket_auth_reject_missing_token():
    """Verify WebSocket rejects missing token with 1008."""
    with pytest.raises(WebSocketDisconnect) as excinfo:
        with client.websocket_connect("/ws") as websocket:
            pass
    assert excinfo.value.code == 1008
