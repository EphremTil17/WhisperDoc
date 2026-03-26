"""
OIDC/JWT Authentication Module
Handles OpenID Connect provider discovery, JWKS caching, and JWT validation
"""

import os
from typing import Any, Dict, Optional
from urllib.parse import urlparse

import requests
from cachetools import TTLCache
from jose import JWTError, jwt
from jose.exceptions import ExpiredSignatureError, JWTClaimsError
from logging_config import log

# OIDC Configuration
OIDC_ISSUER_URL = os.getenv("OIDC_ISSUER_URL", "").strip()
OIDC_CLIENT_ID = os.getenv("OIDC_CLIENT_ID", "").strip()
OIDC_API_RESOURCE = os.getenv("OIDC_API_RESOURCE", "https://api.whisperdoc.com").strip()
OIDC_CONFIG_CACHE_SECONDS = int(
    os.getenv("OIDC_CONFIG_CACHE_SECONDS", os.getenv("OIDC_JWKS_CACHE_SECONDS", "3600"))
)
OIDC_JWKS_CACHE_SECONDS = int(os.getenv("OIDC_JWKS_CACHE_SECONDS", "3600"))


# Validate OIDC URL to prevent injection attacks
def _validate_oidc_url(url: str) -> bool:
    """Validates OIDC issuer URL for security."""
    if not url:
        return True  # Empty is valid (OIDC disabled)

    if " " in url or "\n" in url or "\t" in url:
        log.error("OIDC_ISSUER_URL contains invalid characters")
        return False

    parsed = urlparse(url)
    if not parsed.scheme or not parsed.netloc:
        log.error(f"OIDC_ISSUER_URL must be an absolute URL: {url}")
        return False

    # Must be HTTPS in production (allow HTTP for localhost testing)
    if not _is_secure_or_loopback(parsed):
        log.error(f"OIDC_ISSUER_URL must use HTTPS (or localhost): {url}")
        return False

    return True


def _normalize_url(url: str) -> str:
    parsed = urlparse(url)
    path = parsed.path.rstrip("/") or ""
    return parsed._replace(
        scheme=parsed.scheme.lower(),
        netloc=parsed.netloc.lower(),
        path=path,
        params="",
        query="",
        fragment="",
    ).geturl()


def _origin_tuple(url: str) -> tuple[str, str, int]:
    parsed = urlparse(url)
    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme.lower() == "https" else 80
    return parsed.scheme.lower(), (parsed.hostname or "").lower(), port


def _is_loopback_host(hostname: str) -> bool:
    normalized = hostname.lower()
    return normalized in {"localhost", "127.0.0.1", "::1"}


def _is_secure_or_loopback(parsed) -> bool:
    scheme = parsed.scheme.lower()
    hostname = (parsed.hostname or "").lower()
    return scheme == "https" or (scheme == "http" and _is_loopback_host(hostname))


def _validate_same_origin(url: str, label: str) -> bool:
    if not url:
        log.error(f"OIDC discovery missing {label}")
        return False

    parsed = urlparse(url)
    if not parsed.scheme or not parsed.netloc:
        log.error(f"OIDC {label} must be an absolute URL: {url}")
        return False

    if not _is_secure_or_loopback(parsed):
        log.error(f"OIDC {label} must use HTTPS (or localhost): {url}")
        return False

    if _origin_tuple(url) != _origin_tuple(OIDC_ISSUER_URL):
        log.error(
            f"OIDC {label} must stay on the configured issuer origin. "
            f"Expected origin={_origin_tuple(OIDC_ISSUER_URL)}, got origin={_origin_tuple(url)}"
        )
        return False

    return True


if OIDC_ISSUER_URL and not _validate_oidc_url(OIDC_ISSUER_URL):
    log.warning("OIDC configuration invalid. OIDC authentication disabled.")
    OIDC_ISSUER_URL = ""

# OIDC caches (thread-safe, TTL-based)
_oidc_config_cache: TTLCache = TTLCache(maxsize=1, ttl=OIDC_CONFIG_CACHE_SECONDS)
_jwks_cache: TTLCache = TTLCache(maxsize=10, ttl=OIDC_JWKS_CACHE_SECONDS)


def fetch_oidc_configuration() -> Optional[Dict[str, Any]]:
    """
    Fetches OIDC provider configuration from .well-known/openid-configuration.
    Uses module-level cache to avoid repeated network calls.
    Returns None if OIDC is not configured or fetch fails.
    """
    if not OIDC_ISSUER_URL:
        return None

    if "config" in _oidc_config_cache:
        return _oidc_config_cache["config"]

    try:
        # Normalize issuer URL (remove trailing slash)
        issuer = OIDC_ISSUER_URL.rstrip("/")
        discovery_url = f"{issuer}/.well-known/openid-configuration"

        log.info(f"Fetching OIDC configuration from {discovery_url}")
        response = requests.get(discovery_url, timeout=10)
        response.raise_for_status()

        config = response.json()
        discovered_issuer = config.get("issuer")
        if not isinstance(discovered_issuer, str) or not discovered_issuer.strip():
            log.warning("OIDC discovery document missing valid issuer")
            return None

        if _normalize_url(discovered_issuer) != _normalize_url(OIDC_ISSUER_URL):
            log.warning(
                "OIDC discovery issuer mismatch. "
                f"Expected {_normalize_url(OIDC_ISSUER_URL)}, got {_normalize_url(discovered_issuer)}"
            )
            return None

        jwks_uri = config.get("jwks_uri")
        if not isinstance(jwks_uri, str) or not _validate_same_origin(
            jwks_uri, "jwks_uri"
        ):
            return None

        _oidc_config_cache["config"] = config
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
    if not _validate_same_origin(jwks_uri, "jwks_uri"):
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

        # python-jose expects a string or None for the audience parameter.
        # For OIDC ID Tokens, the primary audience is the Client ID.
        # Fallback to OIDC_API_RESOURCE if Client ID is not set.
        target_audience = OIDC_CLIENT_ID or OIDC_API_RESOURCE

        # Pre-decode to verify identity and get the actual 'iss' string from the token
        unverified_claims = jwt.get_unverified_claims(token)
        token_issuer_raw = unverified_claims.get("iss", "")

        # Identify our expected issuer (Discovery config is the source of truth)
        oidc_config = fetch_oidc_configuration()
        if not oidc_config:
            log.warning("OIDC Validation failed: Configuration unavailable.")
            return None

        expected_issuer_raw = oidc_config.get("issuer")
        if not expected_issuer_raw:
            log.warning("OIDC Validation failed: Discovery doc missing 'issuer'.")
            return None

        # Principal-Level Pinning: Direct comparison of raw strings
        # This prevents an attacker from providing a valid token from a DIFFERENT
        # tenant/identity-provider if the server was misconfigured to trust any JWT.
        if token_issuer_raw != expected_issuer_raw:
            log.warning(
                f"OIDC PINNING VIOLATION! Expected: {expected_issuer_raw}, Found: {token_issuer_raw}"
            )
            return None

        # Pass the token's own raw string to jwt.decode to ensure an exact character match
        # for its internal validation logic, now that we've verified they match normalized.
        payload = jwt.decode(
            token,
            rsa_key,
            algorithms=["RS256"],
            audience=target_audience,
            issuer=token_issuer_raw,
            options={
                "verify_signature": True,
                "verify_exp": True,
                "verify_nbf": True,
                "verify_iat": True,
                "verify_aud": True,
                "verify_iss": True,
                "verify_at_hash": False,
                "leeway": 10,
            },
        )

        # Keep auth logs non-PII. The stable subject claim is enough for audit correlation.
        log.info(f"JWT validated successfully for sub={payload.get('sub', 'unknown')}")

        return payload

    except ExpiredSignatureError:
        log.warning("JWT validation failed: Token expired")
        return None
    except JWTClaimsError as e:
        log.warning(f"JWT validation failed: Claims error - {e}")
        return None
    except (JWTError, Exception) as e:
        # Catch all JWT and cryptographic errors as a failed handshake
        log.warning(f"JWT validation failed: {e}")
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
        log.warning(
            "OIDC warmup failed: Could not fetch configuration. OIDC authentication will be unavailable until provider is reachable."
        )
        return

    jwks = fetch_jwks()
    if not jwks:
        log.warning(
            "OIDC warmup failed: Could not fetch JWKS. OIDC authentication will be unavailable until provider is reachable."
        )
        return

    log.success("OIDC warmup complete. JWT authentication ready.")
