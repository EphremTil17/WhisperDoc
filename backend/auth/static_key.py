"""
Static API Key Authentication
Handles validation of the master API key for local debugging and admin access
"""
import os
import secrets
from logging_config import log

def get_api_key() -> str:
    """
    Retrieves the static API key from the environment.
    Raises a RuntimeError if the key is missing or empty to enforce 'Fail Secure'.
    """
    key = os.getenv("WHISPER_DOC_API_KEY")
    if not key or not key.strip():
        raise RuntimeError("FATAL: WHISPER_DOC_API_KEY is not set. Server cannot start securely.")
    return key.strip()

def validate_static_key(token: str) -> bool:
    """
    Validates a token against the configured static API key.
    Uses constant-time comparison to prevent timing attacks.
    
    Args:
        token: The token to validate
        
    Returns:
        bool: True if token matches the static API key, False otherwise
    """
    try:
        expected_key = get_api_key()
        if secrets.compare_digest(token, expected_key):
            log.debug("Authentication via static API key")
            return True
        return False
    except RuntimeError:
        # If API key is not configured, validation fails
        return False
