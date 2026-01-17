import pytest
import os
import time
from unittest.mock import patch, MagicMock, Mock

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
    with patch("engine.model_manager.ModelManager") as MockModelManager:
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
    with patch("engine.model_manager.ModelManager"):
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

# --- OIDC/JWT Authentication Tests ---

def test_jwt_valid_authentication():
    """Verify that a valid JWT token passes authentication."""
    from auth import validate_token
    from tests.test_jwt_fixtures import generate_test_jwt, generate_mock_jwks, mock_oidc_discovery
    
    # Setup environment for OIDC
    with patch.dict(os.environ, {
        "WHISPER_DOC_API_KEY": "test_key",
        "OIDC_ISSUER_URL": "https://auth.test.local/application/o/test/",
        "OIDC_CLIENT_ID": "whisperdoc_client"
    }):
        # Mock OIDC configuration and JWKS endpoints
        with patch("auth.oidc.requests.get") as mock_get, \
             patch("auth.oidc.OIDC_ISSUER_URL", "https://auth.test.local/application/o/test/"), \
             patch("auth.oidc.OIDC_CLIENT_ID", "whisperdoc_client"):
            # Setup mock responses
            def mock_response(url, *args, **kwargs):
                response = Mock()
                if "openid-configuration" in url:
                    response.json.return_value = mock_oidc_discovery()
                elif "jwks" in url:
                    response.json.return_value = generate_mock_jwks()
                response.raise_for_status = Mock()
                return response
            
            mock_get.side_effect = mock_response
            
            # Generate valid JWT
            token = generate_test_jwt(
                issuer="https://auth.test.local/application/o/test/",
                audience="whisperdoc_client",
                email="user@example.com"
            )
            
            # Test validation
            assert validate_token(token) is not None

def test_jwt_expired_token():
    """Verify that expired JWT tokens are rejected."""
    from auth import validate_token
    from tests.test_jwt_fixtures import generate_test_jwt, generate_mock_jwks, mock_oidc_discovery
    
    with patch.dict(os.environ, {
        "WHISPER_DOC_API_KEY": "test_key",
        "OIDC_ISSUER_URL": "https://auth.test.local/application/o/test/",
        "OIDC_CLIENT_ID": "whisperdoc_client"
    }):
        with patch("auth.oidc.requests.get") as mock_get, \
             patch("auth.oidc.OIDC_ISSUER_URL", "https://auth.test.local/application/o/test/"), \
             patch("auth.oidc.OIDC_CLIENT_ID", "whisperdoc_client"):
            def mock_response(url, *args, **kwargs):
                response = Mock()
                if "openid-configuration" in url:
                    response.json.return_value = mock_oidc_discovery()
                elif "jwks" in url:
                    response.json.return_value = generate_mock_jwks()
                response.raise_for_status = Mock()
                return response
            
            mock_get.side_effect = mock_response
            
            # Generate expired token (expired 1 hour ago)
            token = generate_test_jwt(
                issuer="https://auth.test.local/application/o/test/",
                audience="whisperdoc_client",
                expiration_delta=-3600
            )
            
            assert validate_token(token) is False

def test_jwt_wrong_audience():
    """Verify that JWT with wrong audience is rejected."""
    from auth import validate_token
    from tests.test_jwt_fixtures import generate_test_jwt, generate_mock_jwks, mock_oidc_discovery
    
    with patch.dict(os.environ, {
        "WHISPER_DOC_API_KEY": "test_key",
        "OIDC_ISSUER_URL": "https://auth.test.local/application/o/test/",
        "OIDC_CLIENT_ID": "whisperdoc_client"
    }):
        with patch("auth.oidc.requests.get") as mock_get, \
             patch("auth.oidc.OIDC_ISSUER_URL", "https://auth.test.local/application/o/test/"), \
             patch("auth.oidc.OIDC_CLIENT_ID", "whisperdoc_client"):
            def mock_response(url, *args, **kwargs):
                response = Mock()
                if "openid-configuration" in url:
                    response.json.return_value = mock_oidc_discovery()
                elif "jwks" in url:
                    response.json.return_value = generate_mock_jwks()
                response.raise_for_status = Mock()
                return response
            
            mock_get.side_effect = mock_response
            
            # Generate token for different audience
            token = generate_test_jwt(
                issuer="https://auth.test.local/application/o/test/",
                audience="different_app"
            )
            
            assert validate_token(token) is False

def test_jwt_wrong_issuer():
    """Verify that JWT from wrong issuer is rejected."""
    from auth import validate_token
    from tests.test_jwt_fixtures import generate_test_jwt, generate_mock_jwks, mock_oidc_discovery
    
    with patch.dict(os.environ, {
        "WHISPER_DOC_API_KEY": "test_key",
        "OIDC_ISSUER_URL": "https://auth.test.local/application/o/test/",
        "OIDC_CLIENT_ID": "whisperdoc_client"
    }):
        with patch("auth.oidc.requests.get") as mock_get, \
             patch("auth.oidc.OIDC_ISSUER_URL", "https://auth.test.local/application/o/test/"), \
             patch("auth.oidc.OIDC_CLIENT_ID", "whisperdoc_client"):
            def mock_response(url, *args, **kwargs):
                response = Mock()
                if "openid-configuration" in url:
                    response.json.return_value = mock_oidc_discovery()
                elif "jwks" in url:
                    response.json.return_value = generate_mock_jwks()
                response.raise_for_status = Mock()
                return response
            
            mock_get.side_effect = mock_response
            
            # Generate token from different issuer
            token = generate_test_jwt(
                issuer="https://evil.attacker.com/",
                audience="whisperdoc_client"
            )
            
            assert validate_token(token) is False

def test_jwt_multi_audience():
    """Verify that JWT with valid Resource Indicator or Client ID is accepted."""
    from auth import validate_token
    from tests.test_jwt_fixtures import generate_test_jwt, generate_mock_jwks, mock_oidc_discovery
    
    with patch.dict(os.environ, {
        "WHISPER_DOC_API_KEY": "test_key",
        "OIDC_ISSUER_URL": "https://auth.test.local/application/o/test/",
        "OIDC_CLIENT_ID": "whisperdoc_client",
        "OIDC_API_RESOURCE": "https://api.whisperdoc.com"
    }):
        with patch("auth.oidc.requests.get") as mock_get, \
             patch("auth.oidc.OIDC_ISSUER_URL", "https://auth.test.local/application/o/test/"), \
             patch("auth.oidc.OIDC_CLIENT_ID", "whisperdoc_client"), \
             patch("auth.oidc.OIDC_API_RESOURCE", "https://api.whisperdoc.com"):
            
            def mock_response(url, *args, **kwargs):
                response = Mock()
                if "openid-configuration" in url:
                    response.json.return_value = mock_oidc_discovery()
                elif "jwks" in url:
                    response.json.return_value = generate_mock_jwks()
                response.raise_for_status = Mock()
                return response
            
            mock_get.side_effect = mock_response
            
            # Case 1: Token with ONLY API Resource as audience
            token_only_resource = generate_test_jwt(
                issuer="https://auth.test.local/application/o/test/",
                audience="https://api.whisperdoc.com"
            )
            assert validate_token(token_only_resource) is not None

            # Case 2: Token with both Client ID and API Resource
            token_multi = generate_test_jwt(
                issuer="https://auth.test.local/application/o/test/",
                audience=["whisperdoc_client", "https://api.whisperdoc.com"]
            )
            assert validate_token(token_multi) is not None

            # Case 3: Token with INVALID audience
            token_invalid = generate_test_jwt(
                issuer="https://auth.test.local/application/o/test/",
                audience="https://malicious.com"
            )
            assert validate_token(token_invalid) is False

def test_jwt_malformed_token():
    """Verify that malformed JWT tokens are rejected."""
    from auth import validate_token
    
    with patch.dict(os.environ, {
        "WHISPER_DOC_API_KEY": "test_key",
        "OIDC_ISSUER_URL": "https://auth.test.local/application/o/test/"
    }):
        # Test various malformed tokens
        assert validate_token("not.a.valid.jwt.token") is False
        assert validate_token("only.two.parts") is False
        assert validate_token("") is False
        assert validate_token("   ") is False

def test_static_key_still_works():
    """Regression test: Ensure static API key authentication still works with OIDC enabled."""
    from auth import validate_token
    
    with patch.dict(os.environ, {
        "WHISPER_DOC_API_KEY": "my_secret_static_key",
        "OIDC_ISSUER_URL": "https://auth.test.local/application/o/test/"
    }):
        # Static key should still work (Door #1)
        assert validate_token("my_secret_static_key") is True
        assert validate_token("wrong_key") is False

def test_oidc_disabled_fallback():
    """Verify system works when OIDC is not configured (static key only)."""
    from auth import validate_token
    
    with patch.dict(os.environ, {
        "WHISPER_DOC_API_KEY": "static_only_key",
        "OIDC_ISSUER_URL": ""  # OIDC disabled
    }):
        assert validate_token("static_only_key") is True
        assert validate_token("any.jwt.token") is False
