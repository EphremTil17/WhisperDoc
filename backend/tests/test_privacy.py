import pytest
from unittest.mock import MagicMock, AsyncMock, patch
import asyncio

# Assuming we are running pytest from backend/ or the root with backend/ in path
from protocol.websocket_handler import ConnectionManager

@pytest.mark.asyncio
async def test_incognito_redaction():
    """Test that transcription logs are redacted when incognito is True."""
    # Setup
    mock_model_manager = MagicMock()
    # Mock the inner model
    mock_inner_model = MagicMock()
    mock_model_manager.get_model.return_value = (mock_inner_model, False)
    
    # Mock transcribe result
    segment = MagicMock()
    segment.text = "This is a secret message"
    info = MagicMock()
    info.language = "en"
    info.duration = 1.0
    mock_inner_model.transcribe.return_value = ([segment], info)
    
    manager = ConnectionManager(mock_model_manager, "1.0.0")
    mock_ws = AsyncMock()
    
    # Manually inject connection state with incognito=True
    manager.active_connections[mock_ws] = {
        "buffer": bytearray(b"fake_audio_data"),
        "last_activity": 0,
        "handshake_completed": True,
        "id": "1234",
        "incognito": True
    }
    
    # Patch the logger
    with patch("protocol.websocket_handler.log") as mock_log:
        await manager.transcribe_and_send(mock_ws)
        
        # Verify PRIVACY log contains [REDACTED]
        log_calls = [str(args) for args, _ in mock_log.log.call_args_list]
        found_redacted = any("PRIVACY" in c and "REDACTED" in c for c in log_calls)
        assert found_redacted, f"Expected [REDACTED] in log.log('PRIVACY', ...), got {log_calls}"
        
        # Verify SUCCESS log does NOT contain text
        success_calls = [str(args) for args, _ in mock_log.success.call_args_list]
        found_text = any("secret message" in c for c in success_calls)
        assert not found_text, f"Found sensitive text in log.success: {success_calls}"

@pytest.mark.asyncio
async def test_standard_logging_visibility():
    """Test that transcription logs are visible when incognito is False."""
    # Setup
    mock_model_manager = MagicMock()
    mock_inner_model = MagicMock()
    mock_model_manager.get_model.return_value = (mock_inner_model, False)
    
    segment = MagicMock()
    segment.text = "This is a public message"
    info = MagicMock()
    mock_inner_model.transcribe.return_value = ([segment], info)
    
    manager = ConnectionManager(mock_model_manager, "1.0.0")
    mock_ws = AsyncMock()
    
    # Manually inject connection state with incognito=False
    manager.active_connections[mock_ws] = {
        "buffer": bytearray(b"fake_audio_data"),
        "last_activity": 0,
        "handshake_completed": True,
        "id": "5678",
        "incognito": False
    }
    
    with patch("protocol.websocket_handler.log") as mock_log:
        await manager.transcribe_and_send(mock_ws)
        
        # Verify SUCCESS log DOES contain text
        success_calls = [str(args) for args, _ in mock_log.success.call_args_list]
        found_text = any("public message" in c for c in success_calls)
        assert found_text, f"Expected text in log.success, got {success_calls}"
