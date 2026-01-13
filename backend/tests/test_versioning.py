
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

def test_version_from_file_fallback():
    """Verify that it falls back to VERSION file if env var is missing."""
    # Ensure env var is NOT set
    with mock.patch.dict(os.environ, {}, clear=True):
        # We need to ensure the VERSION file exists for this test to pass 
        # (It does in our environment, but good to be explicit/safe)
        if not os.path.exists("VERSION"):
            with open("VERSION", "w") as f:
                f.write("FILE_VERSION_1.0")
        
        importlib.reload(api_server)
        
        # Read the actual file content to match
        with open("VERSION", "r") as f:
            expected = f.read().strip()
            
        assert api_server.APP_VERSION == expected
