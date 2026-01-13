import os
from fastapi import Security, HTTPException, status
from fastapi.security import APIKeyHeader

# Define the scheme but don't auto-error so we can handle it manually
# We access the Authorization header directly
api_key_header = APIKeyHeader(name="Authorization", auto_error=False)

def get_api_key() -> str:
    """
    Retrieves the API key from the environment.
    Raises a RuntimeError if the key is missing or empty to enforce 'Fail Secure'.
    """
    key = os.getenv("WHISPER_DOC_API_KEY")
    if not key or not key.strip():
        raise RuntimeError("FATAL: WHISPER_DOC_API_KEY is not set. Server cannot start securely.")
    return key

def validate_token(token: str) -> bool:
    """
    Validates a raw token against the servers configured API key.
    """
    try:
        expected_key = get_api_key()
        if not token:
            return False
        # In a real production system, use secrets.compare_digest for constant-time comparison
        return token == expected_key
    except RuntimeError:
        return False

async def verify_api_key(header_value: str = Security(api_key_header)):
    """
    FastAPI dependency for HTTP route authentication.
    Expects 'Authorization: Bearer <key>'
    """
    if not header_value:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization Header"
        )
    
    token = header_value
    if token.lower().startswith("bearer "):
        token = token[7:] # Strip "Bearer "
        
    if not validate_token(token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API Key"
        )
    return True
