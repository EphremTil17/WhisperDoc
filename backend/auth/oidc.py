"""
OIDC/JWT Authentication Module
Handles OpenID Connect provider discovery, JWKS caching, and JWT validation
"""
import os
import requests
from typing import Optional, Dict, Any
from jose import jwt, JWTError
from jose.exceptions import ExpiredSignatureError, JWTClaimsError
from cachetools import TTLCache
from logging_config import log

# OIDC Configuration
OIDC_ISSUER_URL = os.getenv("OIDC_ISSUER_URL", "").strip()
OIDC_CLIENT_ID = os.getenv("OIDC_CLIENT_ID", "whisperdoc_client").strip()
OIDC_JWKS_CACHE_SECONDS = int(os.getenv("OIDC_JWKS_CACHE_SECONDS", "3600"))

# Validate OIDC URL to prevent injection attacks
def _validate_oidc_url(url: str) -> bool:
    """Validates OIDC issuer URL for security."""
    if not url:
        return True  # Empty is valid (OIDC disabled)
    
    # Must be HTTPS in production (allow HTTP for localhost testing)
    if not url.startswith(("https://", "http://localhost", "http://127.0.0.1")):
        log.error(f"OIDC_ISSUER_URL must use HTTPS (or localhost): {url}")
        return False
    
    # Basic URL structure check
    if " " in url or "\n" in url or "\t" in url:
        log.error("OIDC_ISSUER_URL contains invalid characters")
        return False
    
    return True

if OIDC_ISSUER_URL and not _validate_oidc_url(OIDC_ISSUER_URL):
    log.warning("OIDC configuration invalid. OIDC authentication disabled.")
    OIDC_ISSUER_URL = ""

# JWKS Cache (thread-safe, TTL-based)
_jwks_cache: TTLCache = TTLCache(maxsize=10, ttl=OIDC_JWKS_CACHE_SECONDS)
_oidc_config_cache: Optional[Dict[str, Any]] = None

def fetch_oidc_configuration() -> Optional[Dict[str, Any]]:
    """
    Fetches OIDC provider configuration from .well-known/openid-configuration.
    Uses module-level cache to avoid repeated network calls.
    Returns None if OIDC is not configured or fetch fails.
    """
    global _oidc_config_cache
    
    if not OIDC_ISSUER_URL:
        return None
    
    if _oidc_config_cache:
        return _oidc_config_cache
    
    try:
        # Normalize issuer URL (remove trailing slash)
        issuer = OIDC_ISSUER_URL.rstrip('/')
        discovery_url = f"{issuer}/.well-known/openid-configuration"
        
        log.info(f"Fetching OIDC configuration from {discovery_url}")
        response = requests.get(discovery_url, timeout=10)
        response.raise_for_status()
        
        config = response.json()
        _oidc_config_cache = config
        log.success(f"OIDC configuration loaded. Issuer: {config.get('issuer')}")
        return config
    except Exception as e:
        log.warning(f"Failed to fetch OIDC configuration: {e}")
        return None

def fetch_jwks() -> Optional[Dict[str, Any]]:
    """
    Fetches JWKS (JSON Web Key Set) from the OIDC provider.
    Uses TTL cache to minimize network requests.
    Returns None if OIDC is not configured or fetch fails.
    """
    if "jwks" in _jwks_cache:
        return _jwks_cache["jwks"]
    
    config = fetch_oidc_configuration()
    if not config:
        return None
    
    jwks_uri = config.get("jwks_uri")
    if not jwks_uri:
        log.error("OIDC configuration missing jwks_uri")
        return None
    
    try:
        log.debug(f"Fetching JWKS from {jwks_uri}")
        response = requests.get(jwks_uri, timeout=10)
        response.raise_for_status()
        
        jwks = response.json()
        _jwks_cache["jwks"] = jwks
        log.success(f"JWKS loaded and cached ({len(jwks.get('keys', []))} keys)")
        return jwks
    except Exception as e:
        log.error(f"Failed to fetch JWKS: {e}")
        return None

def validate_oidc_token(token: str) -> Optional[Dict[str, Any]]:
    """
    Validates an OIDC JWT token by verifying its signature and claims.
    
    Returns:
        dict: Decoded token payload if valid
        None: If token is invalid or OIDC is not configured
    """
    if not OIDC_ISSUER_URL:
        return None
    
    jwks = fetch_jwks()
    if not jwks:
        log.warning("Cannot validate JWT: JWKS unavailable")
        return None
    
    try:
        # Decode header to find key ID
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")
        
        if not kid:
            log.warning("JWT missing 'kid' in header")
            return None
        
        # Find matching public key
        rsa_key = None
        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                rsa_key = key
                break
        
        if not rsa_key:
            log.warning(f"No matching key found for kid: {kid}")
            return None
        
        # Verify signature and claims
        payload = jwt.decode(
            token,
            rsa_key,
            algorithms=["RS256"],  # Strict algorithm pinning
            audience=OIDC_CLIENT_ID,
            issuer=OIDC_ISSUER_URL.rstrip('/'),
            options={
                "verify_signature": True,
                "verify_exp": True,
                "verify_nbf": True,
                "verify_iat": True,
                "verify_aud": True,
                "verify_iss": True,
                "leeway": 10  # 10-second tolerance for clock skew
            }
        )
        
        # Extract user identity for audit logging
        user_id = payload.get("sub", "unknown")
        email = payload.get("email") or payload.get("preferred_username")
        log.info(f"JWT validated for user: {email or user_id}")
        
        return payload
        
    except ExpiredSignatureError:
        log.warning("JWT validation failed: Token expired")
        return None
    except JWTClaimsError as e:
        log.warning(f"JWT validation failed: Claims error - {e}")
        return None
    except JWTError as e:
        log.warning(f"JWT validation failed: {e}")
        return None
    except Exception as e:
        log.error(f"Unexpected error during JWT validation: {e}")
        return None

def warmup_oidc():
    """
    Pre-fetches OIDC configuration and JWKS during server startup.
    This ensures the first request doesn't experience cache-miss latency.
    Implements graceful degradation: logs warnings but doesn't fail startup.
    """
    if not OIDC_ISSUER_URL:
        log.info("OIDC authentication disabled (OIDC_ISSUER_URL not set)")
        return
    
    log.info(f"Warming up OIDC authentication (Issuer: {OIDC_ISSUER_URL})")
    
    config = fetch_oidc_configuration()
    if not config:
        log.warning("OIDC warmup failed: Could not fetch configuration. OIDC authentication will be unavailable until provider is reachable.")
        return
    
    jwks = fetch_jwks()
    if not jwks:
        log.warning("OIDC warmup failed: Could not fetch JWKS. OIDC authentication will be unavailable until provider is reachable.")
        return
    
    log.success("OIDC warmup complete. JWT authentication ready.")
