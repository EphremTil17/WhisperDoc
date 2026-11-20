"""Regression tests for the HTTP upload guard, service lifecycle, and auth caches."""

import time
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient

import api_server
from auth import oidc
from protocol.websocket_handler import ConnectionManager
from security.governance import SecurityGovernance

AUDIO_FILE = {"file": ("clip.wav", b"RIFF0000WAVE", "audio/wav")}
AUTH = {"Authorization": "Bearer test-key"}


# ---------------------------------------------------------------------------
# HTTP upload guard: checks run on headers, before the multipart body is read
# ---------------------------------------------------------------------------


@pytest.fixture
def client():
    # No lifespan: the guard must work without an initialized engine.
    return TestClient(api_server.app)


def test_unauthenticated_upload_rejected_before_parsing(client):
    with patch("api_server.validate_token", return_value=False) as validate:
        response = client.post("/transcribe", files=AUDIO_FILE, headers=AUTH)
    assert response.status_code == 401
    validate.assert_called_once_with("test-key")


def test_missing_authorization_rejected(client):
    response = client.post("/transcribe", files=AUDIO_FILE)
    assert response.status_code == 401


def test_oversized_upload_rejected_by_content_length(client):
    with (
        patch("api_server.validate_token", return_value=True),
        patch("api_server.MAX_UPLOAD_BYTES", 10),
    ):
        response = client.post("/transcribe", files=AUDIO_FILE, headers=AUTH)
    assert response.status_code == 413


def test_upload_without_content_length_rejected(client):
    def chunked_body():
        yield b"data"

    with patch("api_server.validate_token", return_value=True):
        response = client.post("/transcribe", content=chunked_body(), headers=AUTH)
    assert response.status_code == 411


def test_valid_upload_passes_guard(client):
    """Past the guard the route runs (and reports the missing engine)."""
    with (
        patch("api_server.validate_token", return_value=True),
        patch("api_server.manager", None),
    ):
        response = client.post("/transcribe", files=AUDIO_FILE, headers=AUTH)
    assert response.status_code == 503


def test_log_endpoint_removed(client):
    response = client.post("/log", json={"logs": []}, headers=AUTH)
    assert response.status_code in (404, 405)


# ---------------------------------------------------------------------------
# ConnectionManager lifecycle
# ---------------------------------------------------------------------------


def test_manager_construction_starts_no_tasks():
    """No event loop needed to construct; tasks belong to start()."""
    manager = ConnectionManager(MagicMock(), "1.0.0")
    assert manager._cleanup_task is None


@pytest.mark.asyncio
async def test_manager_start_and_stop():
    manager = ConnectionManager(MagicMock(), "1.0.0")
    manager.start()
    task = manager._cleanup_task
    assert task is not None and not task.done()

    await manager.stop()

    assert task.cancelled()
    assert manager._cleanup_task is None


@pytest.mark.asyncio
async def test_concurrent_handshakes_share_one_warmup():
    engine = MagicMock()
    engine.is_loaded.return_value = False
    engine.warmup.side_effect = lambda: time.sleep(0.05)
    manager = ConnectionManager(engine, "1.0.0")
    hello = {"event": "hello", "token": "k", "version": "9.9.9"}

    with patch("protocol.websocket_handler.validate_token", return_value=True):
        for i in range(3):
            ws = AsyncMock()
            state = {"handshake_completed": False, "id": str(i)}
            await manager._handle_handshake(ws, hello, "hello", state, str(i))

    assert manager._warmup_task is not None
    await manager._warmup_task
    assert engine.warmup.call_count == 1
    await manager.stop()


# ---------------------------------------------------------------------------
# Security trackers and OIDC key refresh
# ---------------------------------------------------------------------------


def test_expired_bans_are_pruned():
    governance = SecurityGovernance()
    now = time.time()
    governance.ban_tracker = {"1.1.1.1": now - 1, "2.2.2.2": now + 300}

    governance.clear_old_trackers()

    assert governance.ban_tracker == {"2.2.2.2": now + 300}


def test_unknown_kid_refetches_jwks_once_per_cooldown():
    rotated = {"keys": [{"kid": "new"}]}
    with (
        patch.object(oidc, "_fetch_jwks", return_value=rotated) as fetch,
        patch.object(oidc, "_last_jwks_refetch", 0.0),
    ):
        assert oidc._refetch_jwks_for_unknown_kid() == rotated
        # A burst of forged kids must not each trigger a fetch.
        assert oidc._refetch_jwks_for_unknown_kid() is None
    assert fetch.call_count == 1
    assert oidc._find_signing_key(rotated, "new") == {"kid": "new"}
    assert oidc._find_signing_key(rotated, "missing") is None
