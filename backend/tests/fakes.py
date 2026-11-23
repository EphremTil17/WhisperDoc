"""Test doubles for the backend's heavy edges: the ASR engine and the IdP.

Everything else (FastAPI routing, the WebSocket protocol, governance, JWT
verification) runs for real in the tests that use these.
"""

import io
import json
import threading
import time
import wave
from dataclasses import dataclass, field
from types import SimpleNamespace
from typing import Any

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

from engine.base_engine import BaseEngine, SegmentResult, TranscriptionResult

API_KEY = "e2e-static-api-key"

ISSUER = "https://idp.example.test/application/o/whisperdoc/"
DISCOVERED_ISSUER = "https://idp.example.test/application/o/whisperdoc"
JWKS_URI = "https://idp.example.test/application/o/whisperdoc/jwks/"
CLIENT_ID = "whisperdoc-desktop"
KID = "signing-key-1"


def pcm_wav(pcm: bytes) -> bytes:
    """Wrap raw 16 kHz mono s16 PCM in a WAV container."""
    out = io.BytesIO()
    with wave.open(out, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(16000)
        wf.writeframes(pcm)
    return out.getvalue()


@dataclass
class Heard:
    """What the engine read from one WAV file it was asked to transcribe."""

    path: str
    channels: int
    sample_width: int
    rate: int
    pcm: bytes


class FakeEngine(BaseEngine):
    """An ASR engine that reads the WAV it is given and returns scripted text.

    Each call pops the next scripted outcome: a list of segment texts, or an
    exception instance to raise. When the script is empty it echoes the PCM
    length so tests can tell utterances apart.
    """

    def __init__(self, loaded: bool = False):
        self.loaded = loaded
        self.heard: list[Heard] = []
        self.script: list[Any] = []
        self.warmups = 0
        self.warmed = threading.Event()
        self.unloads = 0

    def transcribe(self, audio_path: str) -> TranscriptionResult:
        with wave.open(audio_path, "rb") as wf:
            heard = Heard(
                path=audio_path,
                channels=wf.getnchannels(),
                sample_width=wf.getsampwidth(),
                rate=wf.getframerate(),
                pcm=wf.readframes(wf.getnframes()),
            )
        self.heard.append(heard)
        outcome = self.script.pop(0) if self.script else [f"{len(heard.pcm)} bytes"]
        if isinstance(outcome, Exception):
            raise outcome
        segments = [
            SegmentResult(start=float(i), end=float(i + 1), text=text)
            for i, text in enumerate(outcome)
        ]
        return TranscriptionResult(
            text=" ".join(outcome),
            segments=segments,
            language="en",
            processing_time=0.25,
        )

    def warmup(self) -> None:
        self.warmups += 1
        self.loaded = True
        self.warmed.set()

    def is_loaded(self) -> bool:
        return self.loaded

    def unload(self) -> None:
        self.unloads += 1
        self.loaded = False


class FakeClock:
    """Stands in for the ``time`` module where a module only reads the clock."""

    def __init__(self, start: float = 1_000_000.0):
        self.now = start

    def time(self) -> float:
        return self.now

    def monotonic(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


class FakeSocket:
    """The slice of Starlette's WebSocket that ConnectionManager talks to."""

    def __init__(self, host: str = "203.0.113.7", fail_close: bool = False):
        self.client = SimpleNamespace(host=host, port=50000)
        self.accepted = False
        self.sent: list[dict] = []
        self.closed: tuple[int, str | None] | None = None
        self.fail_close = fail_close

    async def accept(self) -> None:
        self.accepted = True

    async def send_json(self, data: dict) -> None:
        self.sent.append(data)

    async def close(self, code: int = 1000, reason: str | None = None) -> None:
        if self.fail_close:
            raise RuntimeError("socket already gone")
        self.closed = (code, reason)


# ---------------------------------------------------------------------------
# Identity provider
# ---------------------------------------------------------------------------


def new_rsa_key() -> rsa.RSAPrivateKey:
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def public_jwk(key: rsa.RSAPrivateKey, kid: str) -> dict:
    jwk = json.loads(RSAAlgorithm.to_jwk(key.public_key()))
    jwk.update({"kid": kid, "use": "sig", "alg": "RS256"})
    return jwk


def private_jwk(key: rsa.RSAPrivateKey, kid: str) -> dict:
    jwk = json.loads(RSAAlgorithm.to_jwk(key))
    jwk.update({"kid": kid})
    return jwk


def make_token(
    key: Any,
    *,
    kid: str | None = KID,
    algorithm: str = "RS256",
    iss: str = DISCOVERED_ISSUER,
    aud: str | list[str] = CLIENT_ID,
    sub: str = "user-42",
    exp_in: int = 600,
    nbf_in: int | None = None,
    now: float | None = None,
    **claims: Any,
) -> str:
    issued = int(time.time() if now is None else now)
    payload: dict[str, Any] = {
        "iss": iss,
        "aud": aud,
        "sub": sub,
        "iat": issued,
        "exp": issued + exp_in,
        **claims,
    }
    if nbf_in is not None:
        payload["nbf"] = issued + nbf_in
    headers = {"kid": kid} if kid is not None else {}
    return jwt.encode(payload, key, algorithm=algorithm, headers=headers)


class FakeResponse:
    def __init__(self, body: Any, status: int = 200):
        self._body = body
        self.status_code = status

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}")

    def json(self) -> Any:
        return self._body


@dataclass
class FakeIdP:
    """Serves discovery and JWKS documents; records every URL fetched."""

    jwks: dict
    discovery: dict = field(
        default_factory=lambda: {
            "issuer": DISCOVERED_ISSUER,
            "jwks_uri": JWKS_URI,
            "id_token_signing_alg_values_supported": ["RS256"],
        }
    )
    discovery_status: int = 200
    jwks_status: int = 200
    fetched: list[str] = field(default_factory=list)

    def get(self, url: str, timeout: float | None = None) -> FakeResponse:
        assert timeout, "IdP requests must carry a timeout"
        self.fetched.append(url)
        if url.endswith("/.well-known/openid-configuration"):
            return FakeResponse(self.discovery, self.discovery_status)
        if url == self.discovery.get("jwks_uri"):
            return FakeResponse(self.jwks, self.jwks_status)
        return FakeResponse({}, 404)

    def count(self, suffix: str) -> int:
        return sum(1 for url in self.fetched if url.endswith(suffix))

    @property
    def discovery_fetches(self) -> int:
        return self.count("/.well-known/openid-configuration")

    @property
    def jwks_fetches(self) -> int:
        return sum(1 for url in self.fetched if url == self.discovery.get("jwks_uri"))


def install_idp(
    monkeypatch: Any,
    idp: FakeIdP,
    *,
    issuer: str = ISSUER,
    client_id: str = CLIENT_ID,
    clock: FakeClock | None = None,
) -> FakeClock:
    """Point auth.oidc at ``idp`` with empty caches and a controllable clock.

    The caller must clear the OIDC caches on teardown (see ``clear_oidc_caches``).
    """
    from auth import oidc

    clock = clock or FakeClock()
    monkeypatch.setattr(oidc, "OIDC_ISSUER_URL", issuer)
    monkeypatch.setattr(oidc, "OIDC_CLIENT_ID", client_id)
    monkeypatch.setattr(oidc, "requests", SimpleNamespace(get=idp.get))
    monkeypatch.setattr(oidc, "time", clock)
    monkeypatch.setattr(oidc, "_last_jwks_refetch", 0.0)
    clear_oidc_caches()
    return clock


def clear_oidc_caches() -> None:
    from auth import oidc

    with oidc._cache_lock:
        oidc._oidc_config_cache.clear()
        oidc._jwks_cache.clear()


def configure_server(monkeypatch: Any, engine: FakeEngine) -> None:
    """Make api_server start with ``engine`` and settings independent of .env.

    The OIDC issuer is cleared so a JWT-shaped token can never reach a real
    IdP configured on the host; tests that need OIDC install a FakeIdP.
    """
    import api_server
    from protocol import websocket_handler
    from security import governance

    monkeypatch.setenv("WHISPER_DOC_API_KEY", API_KEY)
    monkeypatch.setattr(api_server, "manager", None)
    monkeypatch.setattr(api_server, "create_engine", lambda: engine)
    monkeypatch.setattr(api_server, "warmup_oidc", lambda: None)
    monkeypatch.setattr(api_server, "APP_VERSION", "3.2.0")
    monkeypatch.setattr(api_server, "MIN_CLIENT_VERSION", "3.0.0")
    monkeypatch.setattr(api_server, "SEC_CLIENT_VERSION", "3.1.0")
    monkeypatch.setattr(websocket_handler, "MAX_CONNECTIONS", 10)
    monkeypatch.setattr(websocket_handler, "MAX_BUFFER_SIZE", 9_600_000)
    monkeypatch.setattr(websocket_handler, "SANITIZE_TRANSCRIPTS", True)
    monkeypatch.setattr(governance, "BAN_FAILURE_WINDOW_SECONDS", 60)
    monkeypatch.setattr(governance, "BAN_DURATION_SECONDS", 300)
    monkeypatch.setattr(governance, "FLOOD_ATTEMPT_THRESHOLD", 1000)
    monkeypatch.setattr("auth.oidc.OIDC_ISSUER_URL", "")
