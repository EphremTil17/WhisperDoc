"""
Authentication Module - Public API
Orchestrates dual-door authentication: Static API Key + OIDC/JWT tokens
"""

from .oidc import validate_oidc_token, warmup_oidc

# Import authentication strategies
from .static_key import get_api_key, validate_static_key


def validate_token(token: str) -> bool:
    """
    Dual-door authentication validator.

    Door #1: Static API Key (constant-time comparison)
    Door #2: OIDC JWT Token (cryptographic verification)

    Used by the WebSocket handshake and by the HTTP upload guard, which checks
    the Authorization header before any request body is read.

    Args:
        token: The authentication token to validate

    Returns:
        bool: True if token is valid via either door, False otherwise
    """
    if not token or not token.strip():
        return False

    token = token.strip()

    # Door #1: Static API Key
    if validate_static_key(token):
        return True

    # Door #2: OIDC JWT Token (auto-detect by presence of 2 dots)
    if token.count(".") == 2:
        payload = validate_oidc_token(token)
        if payload:
            return True

    return False


# Re-export public functions for convenience
__all__ = ["validate_token", "get_api_key", "warmup_oidc"]
