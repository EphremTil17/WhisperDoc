"""
Authentication Module - Public API
Orchestrates dual-door authentication: Static API Key + OIDC/JWT tokens
"""
from typing import Optional
from fastapi import Security, HTTPException, status
from fastapi.security import APIKeyHeader

# Import authentication strategies
from .static_key import get_api_key, validate_static_key
from .oidc import validate_oidc_token, warmup_oidc

# Define the scheme but don't auto-error so we can handle it manually
api_key_header = APIKeyHeader(name="Authorization", auto_error=False)

def validate_token(token: str) -> bool:
    """
    Dual-door authentication validator.
    
    Door #1: Static API Key (constant-time comparison)
    Door #2: OIDC JWT Token (cryptographic verification)
    
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
    if token.count('.') == 2:
        payload = validate_oidc_token(token)
        if payload:
            return True
    
    return False

async def verify_api_key(header_value: str = Security(api_key_header)):
    """
    FastAPI dependency for HTTP route authentication.
    Expects 'Authorization: Bearer <token>'
    
    Args:
        header_value: The Authorization header value
        
    Returns:
        bool: True if authentication succeeds
        
    Raises:
        HTTPException: If authentication fails
    """
    if not header_value:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization Header"
        )
    
    token = header_value
    if token.lower().startswith("bearer "):
        token = token[7:]  # Strip "Bearer "
        
    if not validate_token(token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API Key"
        )
    return True

# Re-export public functions for convenience
__all__ = [
    'validate_token',
    'verify_api_key', 
    'get_api_key',
    'warmup_oidc'
]
