import pytest
from unittest.mock import MagicMock, AsyncMock, patch

from protocol.websocket_handler import ConnectionManager
from engine.base_engine import TranscriptionResult, SegmentResult


@pytest.mark.asyncio
async def test_incognito_redaction():
    """Test that transcription logs are redacted when incognito is True."""
    mock_engine = MagicMock()
    mock_engine.transcribe.return_value = TranscriptionResult(
        text="This is a secret message",
        segments=[SegmentResult(start=0.0, end=1.0, text="This is a secret message")],
        language="en",
        processing_time=0.1,
    )

    manager = ConnectionManager(mock_engine, "1.0.0")
    mock_ws = AsyncMock()

    manager.active_connections[mock_ws] = {
        "buffer": bytearray(b"fake_audio_data"),
        "last_activity": 0,
        "handshake_completed": True,
        "id": "1234",
        "incognito": True,
    }

    with patch("protocol.websocket_handler.log") as mock_log:
        await manager.transcribe_and_send(mock_ws)

        # PRIVACY log must contain [REDACTED], not the actual text
        log_calls = [str(args) for args, _ in mock_log.log.call_args_list]
        assert any("PRIVACY" in c and "REDACTED" in c for c in log_calls), (
            f"Expected [REDACTED] in log.log('PRIVACY', ...), got {log_calls}"
        )

        # log.success must NOT contain the sensitive text
        success_calls = [str(args) for args, _ in mock_log.success.call_args_list]
        assert not any("secret message" in c for c in success_calls), (
            f"Found sensitive text in log.success: {success_calls}"
        )


@pytest.mark.asyncio
async def test_standard_logging_visibility():
    """Test that transcription logs are visible when incognito is False."""
    mock_engine = MagicMock()
    mock_engine.transcribe.return_value = TranscriptionResult(
        text="This is a public message",
        segments=[SegmentResult(start=0.0, end=1.0, text="This is a public message")],
        language="en",
        processing_time=0.1,
    )

    manager = ConnectionManager(mock_engine, "1.0.0")
    mock_ws = AsyncMock()

    manager.active_connections[mock_ws] = {
        "buffer": bytearray(b"fake_audio_data"),
        "last_activity": 0,
        "handshake_completed": True,
        "id": "5678",
        "incognito": False,
    }

    with patch("protocol.websocket_handler.log") as mock_log:
        await manager.transcribe_and_send(mock_ws)

        success_calls = [str(args) for args, _ in mock_log.success.call_args_list]
        assert any("public message" in c for c in success_calls), (
            f"Expected text in log.success, got {success_calls}"
        )
