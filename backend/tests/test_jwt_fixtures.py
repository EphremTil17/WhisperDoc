# Test fixtures and utilities for OIDC/JWT authentication testing
import json
import time
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
from jose import jwt

# Generate RSA key pair for test JWT signing
_test_private_key = None
_test_public_key = None

def get_test_keys():
    """Generate and cache RSA keys for testing"""
    global _test_private_key, _test_public_key
    
    if _test_private_key is None:
        # Generate 2048-bit RSA key
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )
        
        _test_private_key = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        
        public_key = private_key.public_key()
        _test_public_key = public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )
    
    return _test_private_key, _test_public_key

def generate_test_jwt(
    issuer="https://auth.test.local/application/o/test/",
    audience="whisperdoc_client",
    subject="test_user_123",
    email="test@example.com",
    expiration_delta=3600,
    include_nbf=True,
    **extra_claims
):
    """
    Generate a test JWT token signed with the test private key.
    
    Args:
        issuer: Token issuer (iss claim)
        audience: Token audience (aud claim)
        subject: User identifier (sub claim)
        email: User email (optional)
        expiration_delta: Seconds until expiration (default: 1 hour)
        include_nbf: Include not-before claim
        **extra_claims: Additional claims to include
    
    Returns:
        str: Signed JWT token
    """
    private_key, _ = get_test_keys()
    
    now = int(time.time())
    
    payload = {
        "iss": issuer.rstrip('/'),
        "aud": audience,
        "sub": subject,
        "iat": now,
        "exp": now + expiration_delta,
        **extra_claims
    }
    
    if include_nbf:
        payload["nbf"] = now
    
    if email:
        payload["email"] = email
    
    token = jwt.encode(
        payload,
        private_key,
        algorithm="RS256",
        headers={"kid": "test_key_id_001"}
    )
    
    return token

def generate_mock_jwks():
    """
    Generate a mock JWKS response containing the test public key.
    
    Returns:
        dict: JWKS dictionary with the test public key
    """
    _, public_key_pem = get_test_keys()
    
    # Convert PEM to JWK format (simplified)
    # In production, use a library like python-jose or jwcrypto
    # For testing, we'll use a minimal JWK representation
    from cryptography.hazmat.primitives.serialization import load_pem_public_key
    public_key = load_pem_public_key(public_key_pem, backend=default_backend())
    
    # Extract modulus and exponent
    numbers = public_key.public_numbers()
    
    import base64
    def int_to_base64url(num):
        # Convert integer to base64url without padding
        byte_length = (num.bit_length() + 7) // 8
        num_bytes = num.to_bytes(byte_length, 'big')
        return base64.urlsafe_b64encode(num_bytes).rstrip(b'=').decode('utf-8')
    
    n = int_to_base64url(numbers.n)
    e = int_to_base64url(numbers.e)
    
    return {
        "keys": [
            {
                "kty": "RSA",
                "use": "sig",
                "kid": "test_key_id_001",
                "alg": "RS256",
                "n": n,
                "e": e
            }
        ]
    }

def mock_oidc_discovery():
    """
    Generate a mock OIDC discovery document.
    
    Returns:
        dict: OIDC configuration dictionary
    """
    return {
        "issuer": "https://auth.test.local/application/o/test",
        "authorization_endpoint": "https://auth.test.local/application/o/test/authorize",
        "token_endpoint": "https://auth.test.local/application/o/test/token",
        "jwks_uri": "https://auth.test.local/application/o/test/jwks",
        "response_types_supported": ["code", "token"],
        "subject_types_supported": ["public"],
        "id_token_signing_alg_values_supported": ["RS256"]
    }
