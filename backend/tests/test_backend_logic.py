"""
WhisperDoc Backend Logic Tests (PyTest)
---------------------------------------
Tests the core business logic of the backend without requiring a GPU.
- Mocks WhisperModel and Torch to allow running in lightweight environments.
- Verifies: ModelManager (loading/unloading), ConnectionManager (handshake/errors).

Usage:
  - cd backend
  - pytest tests/test_backend_logic.py
"""
import pytest
import asyncio
import time
from unittest.mock import MagicMock, patch, AsyncMock
import sys
import os

# We rely on local patching in fixtures instead of global sys.modules hijacking.
from websocket_handler import ModelManager, ConnectionManager

@pytest.fixture
def mock_whisper():
    """Mock the WhisperModel class to avoid loading real weights."""
    with patch("websocket_handler.WhisperModel") as MockClass:
        mock_instance = MagicMock()
        MockClass.return_value = mock_instance
        yield MockClass

@pytest.mark.asyncio
async def test_model_manager_loading(mock_whisper):
    """Test that the model loads initially and sets correct state."""
    manager = ModelManager("test_model", "cpu", "int8")
    
    # Assert model was initialized
    mock_whisper.assert_called_once()
    assert manager.model is not None
    
    # Check get_model returns the instance and reload=False
    model, reloaded = manager.get_model()
    assert model == manager.model
    assert reloaded is False

@pytest.mark.asyncio
async def test_model_manager_unload_logic(mock_whisper):
    """Test that the model unloads after timeout using Time Travel."""
    manager = ModelManager("test_model", "cpu", "int8")
    
    # 1. Initial State: Loaded
    assert manager.model is not None
    
    # 2. Travel forward in time (31 minutes)
    future_time = time.time() + 1861 
    
    with patch("time.time", return_value=future_time):
        # Trigger the monitor check manually (simulating the loop)
        # The logic is: if (now - last_used > timeout) -> unload
        if manager.model and (time.time() - manager.last_used > 1800):
            manager.unload_model()
            
    # 3. Assert Unloaded
    assert manager.model is None
    
    # 4. Request Model Again -> Should Reload
    model, reloaded = manager.get_model()
    assert model is not None
    assert reloaded is True
    # Verify WhisperModel was called twice (initial + reload)
    assert mock_whisper.call_count == 2

@pytest.mark.asyncio
async def test_connection_manager_handshake():
    """Test that ConnectionManager sends the correct Hello packet."""
    # Setup
    mock_model_manager = MagicMock()
    mock_model_manager.model = "MockModel" # Simulate loaded model
    
    manager = ConnectionManager(mock_model_manager, app_version="1.0.0")
    mock_ws = AsyncMock()
    
    # Action: Client Connects
    await manager.connect(mock_ws)
    
    # Assert: Accept was called
    mock_ws.accept.assert_awaited_once()
    
    # Assert: Hello JSON was sent
    # We inspect the call args to verify content
    call_args = mock_ws.send_json.call_args[0][0]
    assert call_args["event"] == "hello"
    assert call_args["status"] == "ready"
    assert "version" in call_args

@pytest.mark.asyncio
async def test_connection_manager_structured_error():
    """Test that no-audio scenarios return structured errors."""
    mock_model_manager = MagicMock()
    manager = ConnectionManager(mock_model_manager, app_version="1.0.0")
    mock_ws = AsyncMock()
    
    # Mock a connection that has NO buffer data
    manager.active_connections[mock_ws] = {"buffer": bytearray()}
    
    # Action: Trigger transcription
    await manager.transcribe_and_send(mock_ws)
    
    # Assert output is structured error
    call_args = mock_ws.send_json.call_args[0][0]
    assert call_args["event"] == "error"
    assert call_args["code"] == "NO_AUDIO"
