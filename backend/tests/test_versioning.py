# Reload api_server to reset global variables between tests
import importlib
import os
from unittest import mock

import api_server
import pytest


def test_version_from_env_var():
    """Verify that WHISPER_DOC_VERSION env var takes precedence."""
    with mock.patch.dict(os.environ, {"WHISPER_DOC_VERSION": "9.9.9"}):
        # Force reload because APP_VERSION is a top-level constant
        importlib.reload(api_server)
        assert api_server.APP_VERSION == "9.9.9"


def test_version_logic_helper():
    """Verify the internal version comparison helper in ConnectionManager."""
    from unittest.mock import patch

    from protocol.websocket_handler import ConnectionManager

    with patch(
        "protocol.websocket_handler.asyncio.create_task",
        side_effect=lambda c: c.close(),
    ):
        manager = ConnectionManager(mock.Mock(), "1.0.0", "2.17.0", "2.18.0")

    assert manager.app_version == "1.0.0"
    assert manager.min_client_version == "2.17.0"
    assert manager.sec_client_version == "2.18.0"


@pytest.mark.asyncio
async def test_rejection_of_outdated_client():
    """Verify that clients with version below MIN are rejected during handshake."""
    from protocol.websocket_handler import ConnectionManager

    mock_model = mock.Mock()
    manager = ConnectionManager(
        mock_model, app_version="2.19.0", min_client_version="2.17.0"
    )

    mock_ws = mock.AsyncMock()
    mock_ws.client.host = "127.0.0.1"

    # Simulate receiving 'hello' from an old client
    msg = '{"event": "hello", "version": "2.14.0", "token": "key", "auth_type": "api_key"}'

    # We need to add the websocket to active_connections first to simulate a real connection
    manager.active_connections[mock_ws] = {
        "handshake_completed": False,
        "id": "1234",
        "buffer": bytearray(),
    }

    await manager.handle_message(mock_ws, msg)

    # Verify error sent and connection closed with 1008
    mock_ws.send_json.assert_called()
    args, _ = mock_ws.send_json.call_args
    assert args[0]["code"] == 1008
    assert "Update required" in args[0]["message"]
    mock_ws.close.assert_called_with(code=1008)
