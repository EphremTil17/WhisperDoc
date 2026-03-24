"""
Pytest configuration and shared stubs for host-side test execution.

Heavy dependencies (torch, faster_whisper, ctranslate2, nemo) are not
installed on the Windows host — they live only inside Docker. We stub them
at the sys.modules level here, before any application code is imported, so
that the full test suite can be collected and run without a GPU or Docker.

These stubs are harmless inside Docker too: sys.modules.setdefault() is a
no-op when the real module is already present.
"""

import os
import sys
from unittest.mock import MagicMock


# --- Load .env files for live integration tests (no-op if not present) ---
# Reads backend/.env and project-root .env so that WHISPER_DOC_API_KEY and
# other real credentials are available without manually exporting them.
# Uses setdefault semantics: shell env vars always take precedence.
def _load_dotenv(path: str) -> None:
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
    except FileNotFoundError:
        pass


_base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
_load_dotenv(os.path.join(_base, ".env"))  # backend/.env
_load_dotenv(os.path.join(_base, "..", ".env"))  # project root .env

# --- Test environment defaults (set before any app module is imported) ---
# TrustedHostMiddleware reads ALLOWED_HOSTS at app import time; TestClient
# uses 'testserver' as the Host header, so we add it to the allowed list.
os.environ.setdefault("ALLOWED_HOSTS", "testserver,localhost")

# --- torch / CUDA stubs ---
_torch = MagicMock()
_torch.cuda.is_available.return_value = False
sys.modules.setdefault("torch", _torch)
sys.modules.setdefault("torch.cuda", _torch.cuda)

# --- faster-whisper stubs ---
_fw = MagicMock()
sys.modules.setdefault("faster_whisper", _fw)

# --- ctranslate2 stub (used in api_server health check) ---
_ct2 = MagicMock()
_ct2.get_cuda_device_count.return_value = 0
sys.modules.setdefault("ctranslate2", _ct2)

# --- NeMo stubs ---
# _nemo_asr must be reachable BOTH via sys.modules["nemo.collections.asr"] AND
# via attribute access _nemo.collections.asr, because Python's import machinery
# can resolve the dotted import either way depending on the runtime path.
_nemo = MagicMock()
_nemo_asr = MagicMock()
_nemo.collections.asr = _nemo_asr  # wire attribute chain to the same stub object
sys.modules.setdefault("nemo", _nemo)
sys.modules.setdefault("nemo.collections", _nemo.collections)
sys.modules.setdefault("nemo.collections.asr", _nemo_asr)
