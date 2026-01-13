
import os
import pytest
from unittest import mock
import api_server

# Reload api_server to reset global variables between tests
import importlib

def test_version_from_env_var():
    """Verify that WHISPER_DOC_VERSION env var takes precedence."""
    with mock.patch.dict(os.environ, {"WHISPER_DOC_VERSION": "9.9.9"}):
        # Force reload because APP_VERSION is a top-level constant
        importlib.reload(api_server)
        assert api_server.APP_VERSION == "9.9.9"


