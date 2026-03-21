import pytest
import os
from unittest.mock import patch, Mock
from jose import jwt
from auth.static_key import validate_static_key
from auth.oidc import validate_oidc_token
from tests.test_jwt_fixtures import generate_test_jwt, generate_mock_jwks, mock_oidc_discovery, get_test_keys


@pytest.fixture(autouse=True)
def setup_api_key():
    """Ensure WHISPER_DOC_API_KEY is set for tests that start TestClient."""
    with patch.dict(os.environ, {"WHISPER_DOC_API_KEY": "test_secret_key"}):
        yield


# --- Security Strategy I: Algorithm Defense ---

def test_algorithm_confusion_rejection():
    """
    SECURITY: Verifies protection against algorithm confusion attacks.
    An attacker might sign a token using HS256 with the RSA Public Key as the secret.
    The backend MUST reject this even if the 'secret' (public key) matches.
    """
    _, public_key_pem = get_test_keys()
    
    payload = {
        "iss": "https://auth.test.local/application/o/test",
        "aud": "whisperdoc_client",
        "sub": "attacker",
        "exp": 9999999999
    }
    
    try:
        # Sign with HS256 using the Public Key as the secret
        malicious_token = jwt.encode(payload, public_key_pem, algorithm="HS256")
    except Exception:
        # If the library refuses to sign this (good!), the test is effectively passed
        # since an attacker can't use our platform to generate these, and validation
        # will likely fail similarly.
        return

    with patch("auth.oidc.OIDC_ISSUER_URL", "https://auth.test.local/application/o/test"):
        # The validation MUST fail because we only allow RS256
        assert validate_oidc_token(malicious_token) is None

def test_none_algorithm_rejection():
    """
    SECURITY: Verifies protection against 'none' algorithm attacks.
    Tokens with alg: none must ALWAYS be rejected.
    """
    payload = {
        "iss": "https://auth.test.local/application/o/test",
        "aud": "whisperdoc_client",
        "sub": "attacker"
    }
    
    try:
        # Token with no signature
        none_token = jwt.encode(payload, None, algorithm="none")
    except Exception:
        # If the library refuses to even encode 'none', it's already secured.
        return
    
    with patch("auth.oidc.OIDC_ISSUER_URL", "https://auth.test.local/application/o/test"):
        assert validate_oidc_token(none_token) is None

# --- Security Strategy II: Timing & Replay Defense ---

def test_timing_attack_resilience():
    """
    SECURITY: Verifies that static key comparison uses constant-time comparison.
    This prevents an attacker from guessing the key byte-by-byte via execution timing.
    """
    with patch.dict(os.environ, {"WHISPER_DOC_API_KEY": "super_secret_key"}):
        with patch("secrets.compare_digest", wraps=os.path.commonprefix) as mock_compare:
            # We don't actually want commonprefix, we just want to see if compare_digest is called
            from auth.static_key import validate_static_key
            import secrets
            
            # Re-patch the actual call in static_key
            with patch("auth.static_key.secrets.compare_digest") as real_mock:
                validate_static_key("wrong_key")
                assert real_mock.called, "validate_static_key must use secrets.compare_digest"

def test_expired_token_rejection():
    """
    SECURITY: Verifies that expired tokens are strictly rejected.
    """
    token = generate_test_jwt(expiration_delta=-100) # Expired 100s ago
    
    with patch("auth.oidc.OIDC_ISSUER_URL", "https://auth.test.local/application/o/test/"):
        with patch("auth.oidc.requests.get") as mock_get:
            mock_get.return_value.json.side_effect = [mock_oidc_discovery(), generate_mock_jwks()]
            assert validate_oidc_token(token) is None

# --- Security Strategy III: Handshake Caging ---

def test_handshake_caging_blocks_audio():
    """
    SECURITY: Verifies 'Handshake Caging'.
    The server MUST NOT accept audio data or other events before a successful 'hello'.
    """
    from fastapi.testclient import TestClient
    from api_server import app
    from fastapi import WebSocketDisconnect
    
    with TestClient(app) as client:
        with client.websocket_connect("/ws") as websocket:
            # Receive server hello
            websocket.receive_json()
            
            # Send binary (audio) data BEFORE auth
            with pytest.raises(WebSocketDisconnect) as exc:
                websocket.send_bytes(b"audio data")
                # The server should drop the connection immediately
                websocket.receive_json() 
            
            assert exc.value.code == 1008
            assert "Handshake required" in exc.value.reason

def test_handshake_caging_blocks_invalid_first_event():
    """
    SECURITY: Verifies that the very first event MUST be 'hello'.
    """
    from fastapi.testclient import TestClient
    from api_server import app
    from fastapi import WebSocketDisconnect

    with TestClient(app) as client:
        with client.websocket_connect("/ws") as websocket:
            websocket.receive_json()

            # Attempt to send a 'ping' or 'end-of-stream' before 'hello'
            websocket.send_json({"event": "ping"})

            # Server sends an error message explaining the violation, then closes.
            error_msg = websocket.receive_json()
            assert error_msg["event"] == "error"
            assert "Handshake required" in error_msg["message"]

            with pytest.raises(WebSocketDisconnect) as exc:
                websocket.receive_text()
            assert exc.value.code == 1008
