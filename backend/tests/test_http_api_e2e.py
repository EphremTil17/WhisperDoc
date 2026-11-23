"""End-to-end tests of the HTTP API: /health, /transcribe and the app lifespan.

The real app runs with its middleware and lifespan. The heavy edges are
faked: the ASR engine (reads the WAV it is handed) and the ffmpeg process
(copies or rewrites the file it is asked to convert).
"""

import subprocess
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

import api_server
from tests.fakes import API_KEY, FakeEngine, configure_server, pcm_wav

AUTH = {"Authorization": f"Bearer {API_KEY}"}


class FakeFfmpeg:
    """Stands in for the ffmpeg binary behind ``subprocess.run``."""

    def __init__(self):
        self.calls: list[tuple[list[str], dict]] = []
        self.returncode = 0
        self.hang = False
        self.output: bytes | None = None  # None: pass the input through

    def run(self, cmd, **kwargs):
        self.calls.append((cmd, kwargs))
        if self.hang:
            raise subprocess.TimeoutExpired(cmd, kwargs["timeout"])
        source, target = cmd[cmd.index("-i") + 1], cmd[-1]
        if self.returncode == 0:
            with open(source, "rb") as src:
                data = src.read() if self.output is None else self.output
            with open(target, "wb") as dst:
                dst.write(data)
        return subprocess.CompletedProcess(
            cmd, self.returncode, stdout=None, stderr=b"moov atom not found"
        )

    @property
    def paths(self) -> list[str]:
        cmd = self.calls[-1][0]
        return [cmd[cmd.index("-i") + 1], cmd[-1]]


@pytest.fixture
def engine():
    return FakeEngine()


@pytest.fixture
def ffmpeg(monkeypatch):
    fake = FakeFfmpeg()
    monkeypatch.setattr(
        api_server,
        "subprocess",
        SimpleNamespace(
            run=fake.run,
            TimeoutExpired=subprocess.TimeoutExpired,
            DEVNULL=subprocess.DEVNULL,
            PIPE=subprocess.PIPE,
        ),
    )
    return fake


@pytest.fixture
def client(monkeypatch, engine, ffmpeg):
    configure_server(monkeypatch, engine)
    monkeypatch.setattr(api_server, "MAX_AUDIO_SECONDS", 300)
    monkeypatch.setattr(api_server, "FFMPEG_TIMEOUT_SECONDS", 60)
    with TestClient(api_server.app) as test_client:
        yield test_client


def upload(name="memo.wav", body=None, content_type="audio/wav"):
    body = pcm_wav(b"\x01\x00" * 800) if body is None else body
    return {"file": (name, body, content_type)}


def assert_temp_files_removed(ffmpeg):
    import os

    for path in ffmpeg.paths:
        assert not os.path.exists(path), f"{path} was left behind"


# ---------------------------------------------------------------------------
# /health
# ---------------------------------------------------------------------------


def test_health_reports_uninitialized_before_startup(monkeypatch):
    monkeypatch.setattr(api_server, "manager", None)
    response = TestClient(api_server.app).get("/health")
    assert response.status_code == 503
    assert response.json() == {"status": "uninitialized"}


def test_health_reports_an_idle_model_as_online(client):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "online"
    assert body["model"] == "idle"
    assert isinstance(body["timestamp"], int)


def test_health_reports_a_loaded_model(client, engine):
    engine.loaded = True
    assert client.get("/health").json()["model"] == "loaded"


def test_unexpected_errors_are_masked(monkeypatch, engine, ffmpeg):
    configure_server(monkeypatch, engine)

    def explode():
        raise RuntimeError("db password=hunter2")

    with TestClient(api_server.app, raise_server_exceptions=False) as client:
        monkeypatch.setattr(engine, "is_loaded", explode)
        response = client.get("/health")

    assert response.status_code == 500
    body = response.json()
    assert body["error"] == "Internal Server Error"
    assert len(body["ref"]) == 8
    assert "hunter2" not in response.text


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


def test_startup_refuses_to_run_without_an_api_key(monkeypatch, engine):
    configure_server(monkeypatch, engine)
    created = []
    monkeypatch.setattr(api_server, "create_engine", lambda: created.append(1))
    monkeypatch.setenv("WHISPER_DOC_API_KEY", "  ")

    with pytest.raises(RuntimeError, match="WHISPER_DOC_API_KEY"):
        with TestClient(api_server.app):
            pass

    assert created == [], "no model may load before the key check passes"
    assert api_server.manager is None


def test_startup_fails_fast_when_the_engine_cannot_load(monkeypatch, engine):
    configure_server(monkeypatch, engine)

    def broken_engine():
        raise OSError("CUDA driver missing")

    monkeypatch.setattr(api_server, "create_engine", broken_engine)

    with pytest.raises(OSError, match="CUDA driver missing"):
        with TestClient(api_server.app):
            pass
    assert TestClient(api_server.app).get("/health").status_code == 503


def test_shutdown_unloads_the_engine(monkeypatch, engine):
    configure_server(monkeypatch, engine)
    with TestClient(api_server.app) as client:
        assert client.get("/health").status_code == 200
        assert engine.unloads == 0
    assert engine.unloads == 1


# ---------------------------------------------------------------------------
# /transcribe: authentication and size guard
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "header",
    [f"Bearer {API_KEY}", f"bearer {API_KEY}", f"BEARER {API_KEY}", API_KEY],
)
def test_accepted_authorization_header_forms(client, header):
    response = client.post(
        "/transcribe", files=upload(), headers={"Authorization": header}
    )
    assert response.status_code == 200


@pytest.mark.parametrize(
    "header",
    [None, "", "Bearer ", "Bearer wrong-key", f"Basic {API_KEY}", f"Bearer {API_KEY}x"],
)
def test_rejected_authorization_never_reaches_the_engine(
    client, engine, ffmpeg, header
):
    headers = {} if header is None else {"Authorization": header}
    response = client.post("/transcribe", files=upload(), headers=headers)

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid API Key"}
    assert ffmpeg.calls == [] and engine.heard == []


def test_upload_size_limit_is_inclusive(client, monkeypatch):
    request = client.build_request("POST", "/transcribe", files=upload(), headers=AUTH)
    length = int(request.headers["content-length"])

    monkeypatch.setattr(api_server, "MAX_UPLOAD_BYTES", length)
    assert client.send(request).status_code == 200

    monkeypatch.setattr(api_server, "MAX_UPLOAD_BYTES", length - 1)
    request = client.build_request("POST", "/transcribe", files=upload(), headers=AUTH)
    response = client.send(request)
    assert response.status_code == 413
    assert response.json() == {
        "detail": f"Upload too large. Maximum is {length - 1} bytes."
    }


async def _raw_post(headers):
    """Send a request with hand-written headers straight to the ASGI app."""
    messages = []

    async def receive():
        return {"type": "http.request", "body": b"", "more_body": False}

    async def send(message):
        messages.append(message)

    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "POST",
        "scheme": "http",
        "path": "/transcribe",
        "raw_path": b"/transcribe",
        "query_string": b"",
        "root_path": "",
        "headers": [(b"host", b"testserver"), *headers],
        "client": ("testclient", 50000),
        "server": ("testserver", 80),
    }
    await api_server.app(scope, receive, send)
    return next(m["status"] for m in messages if m["type"] == "http.response.start")


@pytest.mark.parametrize("length", [b"-1", b"12abc", b"1e3", b" 10", b""])
async def test_non_numeric_content_length_is_refused(monkeypatch, engine, length):
    configure_server(monkeypatch, engine)
    status = await _raw_post(
        [
            (b"authorization", AUTH["Authorization"].encode()),
            (b"content-length", length),
        ]
    )
    assert status == 413


async def test_missing_content_length_is_refused(monkeypatch, engine):
    configure_server(monkeypatch, engine)
    assert await _raw_post([(b"authorization", AUTH["Authorization"].encode())]) == 411


async def test_auth_is_checked_before_content_length(monkeypatch, engine):
    configure_server(monkeypatch, engine)
    assert await _raw_post([]) == 401


# ---------------------------------------------------------------------------
# /transcribe: conversion and transcription
# ---------------------------------------------------------------------------


def test_upload_is_converted_and_transcribed(client, engine, ffmpeg):
    engine.script.append(["Dear \x1b[1mDr. Smith\x1b[0m,", "\x1b]0;pwned\x07thanks."])
    pcm = b"\x10\x00\xf0\xff" * 400

    response = client.post("/transcribe", files=upload(body=pcm_wav(pcm)), headers=AUTH)

    assert response.status_code == 200
    body = response.json()
    assert body["text"] == "Dear Dr. Smith, thanks."
    assert body["segments"] == [
        {"start": 0.0, "end": 1.0, "text": "Dear Dr. Smith,"},
        {"start": 1.0, "end": 2.0, "text": "thanks."},
    ]
    assert body["language"] == "en"
    assert body["processing_time"] == 0.25
    assert isinstance(body["timestamp"], float)

    [heard] = engine.heard
    assert heard.pcm == pcm
    source, target = ffmpeg.paths
    assert heard.path == target
    assert source.endswith(".wav") and target == source + ".wav"
    assert_temp_files_removed(ffmpeg)


def test_ffmpeg_is_bounded_in_time_and_length(client, ffmpeg, monkeypatch):
    monkeypatch.setattr(api_server, "MAX_AUDIO_SECONDS", 42)
    monkeypatch.setattr(api_server, "FFMPEG_TIMEOUT_SECONDS", 7)

    assert client.post("/transcribe", files=upload(), headers=AUTH).status_code == 200

    [(cmd, kwargs)] = ffmpeg.calls
    assert cmd[0] == "ffmpeg"
    assert "-nostdin" in cmd
    assert cmd[cmd.index("-t") + 1] == "43"
    assert cmd[cmd.index("-ar") + 1] == "16000"
    assert cmd[cmd.index("-ac") + 1] == "1"
    assert cmd[cmd.index("-sample_fmt") + 1] == "s16"
    assert kwargs["timeout"] == 7


def test_non_audio_upload_is_refused_before_conversion(client, ffmpeg):
    response = client.post(
        "/transcribe", files=upload("notes.txt", b"hello", "text/plain"), headers=AUTH
    )
    assert response.status_code == 400
    assert (
        response.json()["detail"]
        == "Invalid file type. Expected audio file, got: text/plain"
    )
    assert ffmpeg.calls == []


@pytest.mark.parametrize(
    "name", ["memo.FLAC", "memo.mp3", "memo.m4a", "memo.ogg", "memo.wav"]
)
def test_audio_extension_is_enough_without_an_audio_mime_type(client, name):
    response = client.post(
        "/transcribe",
        files=upload(name, content_type="application/octet-stream"),
        headers=AUTH,
    )
    assert response.status_code == 200


def test_upload_without_extension_keeps_a_temp_suffix(client, ffmpeg):
    response = client.post(
        "/transcribe", files=upload("recording", content_type="audio/ogg"), headers=AUTH
    )
    assert response.status_code == 200
    assert ffmpeg.paths[0].endswith(".tmp")
    assert_temp_files_removed(ffmpeg)


def test_undecodable_audio_is_a_client_error(client, engine, ffmpeg):
    ffmpeg.returncode = 1
    response = client.post("/transcribe", files=upload(), headers=AUTH)

    assert response.status_code == 400
    assert response.json() == {"detail": "Unsupported audio format"}
    assert engine.heard == []
    assert_temp_files_removed(ffmpeg)


def test_decoder_that_hangs_is_cut_off(client, engine, ffmpeg):
    ffmpeg.hang = True
    response = client.post("/transcribe", files=upload(), headers=AUTH)

    assert response.status_code == 400
    assert response.json() == {"detail": "Audio could not be decoded in time"}
    assert engine.heard == []
    assert_temp_files_removed(ffmpeg)


def test_decoded_audio_length_limit_is_inclusive(client, engine, ffmpeg, monkeypatch):
    monkeypatch.setattr(api_server, "MAX_AUDIO_SECONDS", 1)
    # Limit: one second of PCM plus 1024 bytes of slack for the WAV header.
    limit = 16000 * 2 + 1024
    ffmpeg.output = pcm_wav(b"\x00" * (limit - 44))
    assert client.post("/transcribe", files=upload(), headers=AUTH).status_code == 200

    ffmpeg.output = pcm_wav(b"\x00" * (limit - 44 + 2))
    response = client.post("/transcribe", files=upload(), headers=AUTH)
    assert response.status_code == 413
    assert response.json() == {"detail": "Audio too long. Maximum is 1 seconds."}
    assert len(engine.heard) == 1
    assert_temp_files_removed(ffmpeg)


def test_engine_failure_is_masked_with_a_reference(client, engine, ffmpeg):
    engine.script.append(RuntimeError("model at /srv/secret/weights crashed"))
    response = client.post("/transcribe", files=upload(), headers=AUTH)

    assert response.status_code == 500
    detail = response.json()["detail"]
    assert detail.startswith("Transcription failed (ref ") and len(detail) == len(
        "Transcription failed (ref 12345678)"
    )
    assert "secret" not in response.text
    assert_temp_files_removed(ffmpeg)


def test_http_and_websocket_share_the_sanitization_switch(client, engine, monkeypatch):
    from protocol import websocket_handler

    monkeypatch.setattr(websocket_handler, "SANITIZE_TRANSCRIPTS", False)
    engine.script.append(["raw \x1b[31mred"])
    response = client.post("/transcribe", files=upload(), headers=AUTH)
    assert response.json()["text"] == "raw \x1b[31mred"
