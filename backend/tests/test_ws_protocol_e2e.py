"""End-to-end tests of the /ws transcription protocol.

The real FastAPI app runs with its lifespan (ConnectionManager, governance,
auth); only the ASR engine is a fake that reads the WAV it is handed and
returns scripted text. Tests talk to the server the way a client does: JSON
and binary frames in, JSON frames and close codes out.
"""

import os

import pytest
from fastapi import WebSocketDisconnect
from fastapi.testclient import TestClient

import api_server
from protocol import websocket_handler
from security import governance
from tests.fakes import (
    API_KEY,
    KID,
    FakeClock,
    FakeEngine,
    FakeIdP,
    clear_oidc_caches,
    configure_server,
    install_idp,
    make_token,
    new_rsa_key,
    public_jwk,
)

BAN_THRESHOLD = 3


@pytest.fixture
def engine():
    return FakeEngine()


@pytest.fixture
def client(monkeypatch, engine):
    """A running server whose configuration does not depend on the host's .env."""
    configure_server(monkeypatch, engine)
    monkeypatch.setattr(governance, "BAN_FAILURE_THRESHOLD", BAN_THRESHOLD)
    with TestClient(api_server.app) as test_client:
        yield test_client


def hello(version="3.2.0", token=API_KEY, **extra):
    return {
        "event": "hello",
        "client": "pytest",
        "version": version,
        "token": token,
        **extra,
    }


def connect_and_authenticate(ws, **overrides):
    server_hello = ws.receive_json()
    assert server_hello["event"] == "hello"
    ws.send_json(hello(**overrides))
    reply = ws.receive_json()
    assert reply == {
        "event": "authenticated",
        "status": "success",
        "cid": server_hello["cid"],
    }
    return server_hello


def expect_error(ws, error_code, code, close_code):
    frame = ws.receive_json()
    assert frame["event"] == "error"
    assert frame["error_code"] == error_code
    assert frame["code"] == code
    if close_code is None:
        return frame
    with pytest.raises(WebSocketDisconnect) as exc:
        ws.receive_json()
    assert exc.value.code == close_code
    return frame


def assert_still_open(ws):
    ws.send_json({"event": "ping"})
    assert ws.receive_json() == {"event": "pong"}


def pcm(n_samples, value=1):
    return int(value).to_bytes(2, "little", signed=True) * n_samples


# ---------------------------------------------------------------------------
# Handshake
# ---------------------------------------------------------------------------


def test_server_hello_advertises_versions_and_idle_model(client):
    with client.websocket_connect("/ws") as ws:
        frame = ws.receive_json()

    assert frame["event"] == "hello"
    assert frame["version"] == "3.2.0"
    assert frame["min_version"] == "3.0.0"
    assert frame["sec_version"] == "3.1.0"
    assert frame["status"] == "idle"
    assert len(frame["cid"]) == 4


def test_handshake_warms_a_cold_model_once(client, engine):
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        assert engine.warmed.wait(5), "a cold engine must be warmed after auth"

    with client.websocket_connect("/ws") as ws:
        server_hello = connect_and_authenticate(ws)
        assert server_hello["status"] == "ready"
        assert_still_open(ws)

    assert engine.warmups == 1


def test_failed_warmup_leaves_the_session_usable(client, engine, monkeypatch):
    def broken_warmup():
        engine.warmed.set()
        raise RuntimeError("out of VRAM")

    monkeypatch.setattr(engine, "warmup", broken_warmup)
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        assert engine.warmed.wait(5)
        ws.send_bytes(pcm(10))
        ws.send_json({"event": "end-of-stream"})
        assert ws.receive_json()["text"] == "20 bytes"


@pytest.mark.parametrize(
    "version",
    ["3.0.0", "3.0", "3.0.0-beta.1", "3.0.0+build.7", "3.1.0", "10.0.0"],
)
def test_supported_client_versions_are_admitted(client, version):
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws, version=version)


@pytest.mark.parametrize(
    "version", ["2.9.9", "2.99.99", "0.0.0", "v3.2.0", "garbage", ""]
)
def test_outdated_or_unparseable_client_versions_are_refused(client, version):
    with client.websocket_connect("/ws") as ws:
        ws.receive_json()
        ws.send_json(hello(version=version))
        frame = expect_error(ws, "VERSION_OUTDATED", 1008, 1008)

    assert frame["message"] == f"Update required: v3.0.0 (Client: {version})"


def test_hello_without_version_is_treated_as_outdated(client):
    with client.websocket_connect("/ws") as ws:
        ws.receive_json()
        ws.send_json({"event": "hello", "token": API_KEY})
        expect_error(ws, "VERSION_OUTDATED", 1008, 1008)


def test_long_client_version_cannot_break_the_close_frame(client):
    """The version is echoed in the JSON message only, never the close reason."""
    version = "1." + "9" * 300
    with client.websocket_connect("/ws") as ws:
        ws.receive_json()
        ws.send_json(hello(version=version))
        frame = expect_error(ws, "VERSION_OUTDATED", 1008, 1008)
    assert version in frame["message"]


def test_wrong_api_key_is_refused(client):
    with client.websocket_connect("/ws") as ws:
        ws.receive_json()
        ws.send_json(hello(token="not-the-key"))
        frame = expect_error(ws, "AUTH_FAILED", 403, 1008)
    assert frame["message"] == "API Key Authentication failed"


def test_duplicate_hello_closes_the_session(client):
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        ws.send_json(hello())
        expect_error(ws, "DUPLICATE_HANDSHAKE", 1008, 1008)


def test_unknown_event_after_handshake_closes_the_session(client):
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        ws.send_json({"event": "rm -rf"})
        frame = expect_error(ws, "INVALID_EVENT", 1008, 1008)
    assert frame["message"] == "Invalid event: rm -rf"


def test_malformed_json_closes_the_session(client):
    with client.websocket_connect("/ws") as ws:
        ws.receive_json()
        ws.send_text('{"event": "hello"')
        expect_error(ws, "MALFORMED_JSON", 1008, 1008)


@pytest.mark.parametrize("payload", ["[1, 2]", '"hello"', "null", "42"])
def test_json_that_is_not_an_object_is_an_internal_error(client, payload):
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        ws.send_text(payload)
        frame = expect_error(ws, "SERVER_ERROR", 1011, 1011)
    assert frame["message"] == "Internal server error"


# ---------------------------------------------------------------------------
# OIDC handshake against a faked identity provider
# ---------------------------------------------------------------------------


@pytest.fixture
def idp_key():
    return new_rsa_key()


@pytest.fixture
def idp(monkeypatch, client, idp_key):
    idp = FakeIdP(jwks={"keys": [public_jwk(idp_key, KID)]})
    install_idp(monkeypatch, idp, clock=FakeClock())
    yield idp
    clear_oidc_caches()


def test_oidc_token_authenticates_and_can_transcribe(client, idp, idp_key, engine):
    token = make_token(idp_key, sub="user-7", email="u7@example.test")
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws, token=token, auth_type="oidc")
        ws.send_bytes(pcm(160))
        ws.send_json({"event": "end-of-stream"})
        assert ws.receive_json()["text"] == "320 bytes"


def test_jwt_passed_as_api_key_is_accepted_through_the_oidc_door(client, idp, idp_key):
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws, token=make_token(idp_key))


@pytest.mark.parametrize(
    "claims",
    [{"aud": "someone-else"}, {"exp_in": -3600}, {"iss": "https://evil.example.test"}],
)
def test_invalid_oidc_token_is_refused(client, idp, idp_key, claims):
    with client.websocket_connect("/ws") as ws:
        ws.receive_json()
        ws.send_json(hello(token=make_token(idp_key, **claims), auth_type="oidc"))
        frame = expect_error(ws, "AUTH_FAILED", 403, 1008)
    assert frame["message"] == "OIDC Authentication failed"


def test_static_api_key_is_not_accepted_as_an_oidc_token(client, idp):
    with client.websocket_connect("/ws") as ws:
        ws.receive_json()
        ws.send_json(hello(auth_type="oidc"))
        expect_error(ws, "AUTH_FAILED", 403, 1008)


# ---------------------------------------------------------------------------
# Audio and transcription
# ---------------------------------------------------------------------------


def test_streamed_audio_is_transcribed_and_sanitized(client, engine):
    engine.script.append(["Hello \x1b[31mworld\x1b[0m", "\x07second\x00 line "])
    first, second = pcm(800, 7), pcm(400, -3)

    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        ws.send_bytes(first)
        ws.send_bytes(second)
        ws.send_json({"event": "end-of-stream"})
        frame = ws.receive_json()
        assert_still_open(ws)

    assert frame == {
        "event": "transcription",
        "text": "Hello world second line",
        "segments": [
            {"start": 0.0, "end": 1.0, "text": "Hello world"},
            {"start": 1.0, "end": 2.0, "text": "second line"},
        ],
        "processing_time": 0.25,
    }
    [heard] = engine.heard
    assert (heard.channels, heard.sample_width, heard.rate) == (1, 2, 16000)
    assert heard.pcm == first + second
    assert not os.path.exists(heard.path), "the temporary WAV must be deleted"


def test_each_utterance_is_transcribed_on_its_own(client, engine):
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        for n in (100, 30):
            ws.send_bytes(pcm(n))
            ws.send_json({"event": "end-of-stream"})
            assert ws.receive_json()["text"] == f"{2 * n} bytes"

    assert [len(h.pcm) for h in engine.heard] == [200, 60]


def test_end_of_stream_without_audio_reports_no_audio_and_keeps_session(client, engine):
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        ws.send_json({"event": "end-of-stream"})
        frame = expect_error(ws, "NO_AUDIO", 422, None)
        assert_still_open(ws)

    assert frame["message"] == "No audio data received"
    assert engine.heard == []


def test_engine_failure_is_reported_and_the_next_utterance_starts_clean(client, engine):
    engine.script.append(RuntimeError("CUDA exploded at /secret/path"))
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        ws.send_bytes(pcm(500))
        ws.send_json({"event": "end-of-stream"})
        frame = expect_error(ws, "TRANSCRIPTION_FAILED", 1011, None)

        ws.send_bytes(pcm(25))
        ws.send_json({"event": "end-of-stream"})
        assert ws.receive_json()["text"] == "50 bytes"

    assert frame["message"] == "Transcription failed"
    assert [len(h.pcm) for h in engine.heard] == [1000, 50]
    assert not os.path.exists(engine.heard[0].path)


def test_audio_beyond_the_buffer_limit_is_refused(client, monkeypatch, engine):
    monkeypatch.setattr(websocket_handler, "MAX_BUFFER_SIZE", 8)
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        ws.send_bytes(pcm(4))  # exactly at the limit: accepted
        ws.send_bytes(pcm(1))
        # Sentinel: had the chunk been buffered, this would yield a transcript
        # (and a failure) instead of a hang. The real server ignores it.
        ws.send_json({"event": "end-of-stream"})
        frame = expect_error(ws, "BUFFER_EXCEEDED", 1009, 1009)

    assert frame["message"] == "Buffer limit exceeded"
    assert engine.heard == []


def test_audio_up_to_the_buffer_limit_is_transcribed(client, monkeypatch, engine):
    monkeypatch.setattr(websocket_handler, "MAX_BUFFER_SIZE", 8)
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)
        ws.send_bytes(pcm(3))
        ws.send_bytes(pcm(1))  # buffer was below the limit, so this is kept
        ws.send_json({"event": "end-of-stream"})
        assert ws.receive_json()["text"] == "8 bytes"


# ---------------------------------------------------------------------------
# Admission control: connection cap and IP bans
# ---------------------------------------------------------------------------


def test_connections_beyond_the_cap_are_refused(client, monkeypatch):
    monkeypatch.setattr(websocket_handler, "MAX_CONNECTIONS", 1)
    with client.websocket_connect("/ws") as first:
        connect_and_authenticate(first)
        with client.websocket_connect("/ws") as second:
            frame = expect_error(second, "MAX_CONNECTIONS", 1008, 1008)
        assert_still_open(first)

    assert frame["message"] == "Max concurrent connections reached"


def _violate(ws, violation):
    ws.receive_json()
    if violation == "audio-before-hello":
        ws.send_bytes(b"\x00\x01")
    elif violation == "event-before-hello":
        ws.send_json({"event": "end-of-stream"})
    elif violation == "malformed-json":
        ws.send_text("{nope")
    elif violation == "bad-api-key":
        ws.send_json(hello(token="guess"))
    elif violation == "outdated-client":
        ws.send_json(hello(version="1.0.0"))
    elif violation == "bad-oidc-token":
        ws.send_json(hello(token="a.b.c", auth_type="oidc"))
    frame = ws.receive_json()
    assert frame["event"] == "error"
    with pytest.raises(WebSocketDisconnect):
        ws.receive_json()


def _assert_banned(client):
    with client.websocket_connect("/ws") as ws:
        frame = ws.receive_json()
        assert frame["event"] == "error"
        assert frame["error_code"] == "IP_BANNED"
        assert frame["code"] == 1008
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
    assert exc.value.code == 1008
    assert exc.value.reason == frame["message"]
    assert frame["message"].startswith("IP Banned. Cooldown: ")
    return int(frame["message"].removeprefix("IP Banned. Cooldown: ").rstrip("s"))


@pytest.mark.parametrize(
    "violation",
    [
        "audio-before-hello",
        "event-before-hello",
        "malformed-json",
        "bad-api-key",
        "outdated-client",
        "bad-oidc-token",
    ],
)
def test_repeated_protocol_violations_ban_the_ip(client, violation):
    for _ in range(BAN_THRESHOLD - 1):
        with client.websocket_connect("/ws") as ws:
            _violate(ws, violation)
    # Still below the threshold: the next client is admitted.
    with client.websocket_connect("/ws") as ws:
        _violate(ws, violation)

    remaining = _assert_banned(client)
    assert 295 <= remaining <= 300


def _misbehave_without_violation(ws, kind):
    connect_and_authenticate(ws)
    if kind == "duplicate-hello":
        ws.send_json(hello())
    elif kind == "invalid-event":
        ws.send_json({"event": "dance"})
    elif kind == "empty-utterance":
        ws.send_json({"event": "end-of-stream"})
        assert ws.receive_json()["error_code"] == "NO_AUDIO"
        return
    assert ws.receive_json()["event"] == "error"
    with pytest.raises(WebSocketDisconnect):
        ws.receive_json()


@pytest.mark.parametrize(
    "kind", ["duplicate-hello", "invalid-event", "empty-utterance"]
)
def test_authenticated_client_mistakes_do_not_ban(client, kind):
    for _ in range(BAN_THRESHOLD + 1):
        with client.websocket_connect("/ws") as ws:
            _misbehave_without_violation(ws, kind)

    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)


def test_ban_expires_after_its_duration(client, monkeypatch):
    clock = FakeClock()
    monkeypatch.setattr(governance, "time", clock)
    for _ in range(BAN_THRESHOLD):
        with client.websocket_connect("/ws") as ws:
            _violate(ws, "bad-api-key")

    clock.advance(299)
    assert _assert_banned(client) == 1

    clock.advance(1)
    with client.websocket_connect("/ws") as ws:
        connect_and_authenticate(ws)


def test_connection_flood_bans_the_ip(client, monkeypatch):
    monkeypatch.setattr(governance, "FLOOD_ATTEMPT_THRESHOLD", 3)
    for _ in range(4):
        with client.websocket_connect("/ws") as ws:
            assert ws.receive_json()["event"] == "hello"

    _assert_banned(client)


# ---------------------------------------------------------------------------
# Endpoint without an initialized backend
# ---------------------------------------------------------------------------


def test_socket_is_closed_with_1011_before_startup(monkeypatch):
    monkeypatch.setattr(api_server, "manager", None)
    with pytest.raises(WebSocketDisconnect) as exc:
        with TestClient(api_server.app).websocket_connect("/ws"):
            pass
    assert exc.value.code == 1011
