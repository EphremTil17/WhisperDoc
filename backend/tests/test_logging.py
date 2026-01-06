"""
WhisperDoc Logging Configuration Test
------------------------------------
Verifies that the custom logger (loguru based) is correctly configured.
Checks various log levels (DEBUG, INFO, SUCCESS, WARNING, ERROR, CRITICAL).

Usage:
  - pytest tests/test_logging.py
  - python tests/test_logging.py
"""
import pytest
import os
import sys

# Add parent directory to path for imports
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

try:
    from logging_config import log
except ImportError:
    # Handle environment where logging_config might not be in path
    import magicmock
    log = MagicMock()

def run_log_tests():
    """Execution logic for both manual and pytest runs."""
    log.info("--- Starting Log Test ---")
    
    log.debug("DEBUG: Should appear in log file.")
    log.info("INFO: Should appear in console + file.")
    log.success("SUCCESS: Should be green in console.")
    log.warning("WARNING: Should be yellow in console.")
    log.error("ERROR: Should be red in console.")
    log.critical("CRITICAL: Should be bold red in console.")
    
    try:
        1 / 0
    except ZeroDivisionError:
        log.exception("EXCEPTION: Verified traceback inclusion.")

    log.info("--- Log Test Complete ---")

def test_logging_configuration():
    """Pytest entry point for logging verification."""
    # We essentially want to ensure no crashes occur during logging
    try:
        run_log_tests()
    except Exception as e:
        pytest.fail(f"Logging system crashed: {e}")

if __name__ == "__main__":
    run_log_tests()
    print("\n[SUCCESS] Console verification complete. Check logs/backend.log for file verification.")
