import pytest
import asyncio
import time
from unittest.mock import MagicMock, patch
from engine.model_manager import ModelManager
from protocol.websocket_handler import ConnectionManager

@pytest.mark.asyncio
async def test_concurrent_warmup_lock():
    """
    Verifies that simultaneous calls to load_model are serialized by the lock
    and do not cause multiple loads.
    """
    # Mock WhisperModel to simulate a slow load
    with patch("engine.model_manager.WhisperModel") as mock_whisper:
        # Simulate 1 second load time
        def slow_load(*args, **kwargs):
            time.sleep(0.5)
            return MagicMock()
        
        mock_whisper.side_effect = slow_load
        
        manager = ModelManager("tiny.en", "cpu", "int8")
        # Reset mock after initial load in __init__
        mock_whisper.reset_mock()
        manager.model = None # Force a reload
        
        # Trigger two concurrent loads via threads (since load_model is sync)
        # In the real app, these are triggered by asyncio.to_thread
        async def trigger_load():
            await asyncio.to_thread(manager.load_model)

        start_time = time.time()
        await asyncio.gather(trigger_load(), trigger_load())
        duration = time.time() - start_time
        
        # Duration should be at least 1s (0.5s + 0.5s) if locked, 
        # but mock_whisper.call_count should be exactly 1 because of the 'if self.model: return' inside the lock.
        assert mock_whisper.call_count == 1
        assert duration >= 0.5

@pytest.mark.asyncio
async def test_warmup_non_blocking_event_loop():
    """
    Verifies that the event loop remains responsive while a warmup is happening in the background.
    """
    with patch("engine.model_manager.WhisperModel") as mock_whisper:
        def slow_load(*args, **kwargs):
            time.sleep(1.0)
            return MagicMock()
        mock_whisper.side_effect = slow_load
        
        model_manager = ModelManager("tiny.en", "cpu", "int8")
        model_manager.model = None # Force reload
        
        conn_manager = ConnectionManager(model_manager, "v1.0.0")
        
        # Trigger warmup (this is an async task internally)
        start_time = time.time()
        asyncio.create_task(conn_manager._warmup_model())
        
        # Immediately do something else on the event loop
        # If _warmup_model blocked the loop, this sleep would take 1s + 0.1s
        await asyncio.sleep(0.1)
        heartbeat_time = time.time() - start_time
        
        # Heartbeat should have happened almost immediately, well before the 1s load
        assert heartbeat_time < 0.5
        print(f"Heartbeat took {heartbeat_time:.4f}s during 1s model load.")
