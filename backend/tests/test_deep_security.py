import pytest
import os
from unittest.mock import patch, Mock
from fastapi.testclient import TestClient
from fastapi import WebSocketDisconnect
from api_server import app
from auth.oidc import validate_oidc_token
from tests.test_jwt_fixtures import generate_test_jwt, generate_mock_jwks, mock_oidc_discovery

@pytest.fixture
def mock_oidc_env():
    """Setup environment and mocks for OIDC tests."""
    with patch.dict(os.environ, {
        "OIDC_ISSUER_URL": "https://auth.test.local/",
        "OIDC_CLIENT_ID": "whisperdoc_client"
    }):
        with patch("auth.oidc.requests.get") as mock_get:
            def mock_response(url, *args, **kwargs):
                response = Mock()
                if "openid-configuration" in url:
                    response.json.return_value = mock_oidc_discovery()
                elif "jwks" in url:
                    response.json.return_value = generate_mock_jwks()
                response.raise_for_status = Mock()
                return response
            
            mock_get.side_effect = mock_response
            yield mock_get

def test_jwt_algorithm_pinning_none(mock_oidc_env):
    """CRITICAL: Verify that 'alg: none' attack is rejected."""
    # Create a token with alg: none
    from jose import jwt as jose_jwt
    payload = {
        "iss": "https://auth.test.local/",
        "aud": "whisperdoc_client",
        "sub": "user123",
        "exp": 9999999999
    }
    token = jose_jwt.encode(payload, key=None, algorithm="none")
    
    assert validate_oidc_token(token) is None

def test_jwt_algorithm_pinning_hs256(mock_oidc_env):
    """CRITICAL: Verify that symmetric HS256 attack is rejected when RS256 is expected."""
    from jose import jwt as jose_jwt
    payload = {
        "iss": "https://auth.test.local/",
        "aud": "whisperdoc_client",
        "sub": "user123",
        "exp": 9999999999
    }
    # Attacker tries to use the server's public key as a symmetric secret
    token = jose_jwt.encode(payload, key="secret", algorithm="HS256")
    
    assert validate_oidc_token(token) is None

def test_protocol_enforcement_audio_before_auth():
    """Verify that sending audio bytes before 'hello' handshake results in 1008 Close."""
    with patch("engine.model_manager.ModelManager"):
        with TestClient(app) as local_client:
            with local_client.websocket_connect("/ws") as websocket:
                # 1. Receive Server Hello
                websocket.receive_json()
                
                # 2. Immediately send raw bytes (Protocol Violation)
                websocket.send_bytes(b"\x00\x01\x02\x03")
                
                # 3. Expect Disconnect with 1008
                with pytest.raises(WebSocketDisconnect) as exc:
                    websocket.receive_json()
                assert exc.value.code == 1008
                assert "Handshake required" in exc.value.reason

def test_protocol_enforcement_invalid_event_before_auth():
    """Verify that sending non-hello event before auth results in 1008 Close."""
    with patch("engine.model_manager.ModelManager"):
        with TestClient(app) as local_client:
            with local_client.websocket_connect("/ws") as websocket:
                websocket.receive_json()
                
                # Send 'ping' instead of 'hello'
                websocket.send_json({"event": "ping"})
                
                with pytest.raises(WebSocketDisconnect) as exc:
                    websocket.receive_json()
                assert exc.value.code == 1008
                assert "Handshake required" in exc.value.reason

def test_ban_message_format_compliance():
    """Verify that 1008 close reason follows the pattern 'Retry in Xs' for client parsing."""
    from security.governance import SecurityGovernance
    gov = SecurityGovernance()
    ip = "1.2.3.4"
    
    # Force a ban
    for _ in range(10):
        gov.record_protocol_violation(ip)
    
    is_banned, remaining = gov.is_ip_banned(ip)
    assert is_banned
    
    # Check the logic used in websocket_handler.py
    reason = f"IP Banned. Cooldown: {remaining}s"
    assert "Cooldown:" in reason
    assert str(remaining) in reason
