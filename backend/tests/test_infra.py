
import os
import tempfile
import pytest

def test_filesystem_root_is_readonly():
    """Verify that the root filesystem is read-only (Docker container only)."""
    if not os.path.exists("/.dockerenv"):
        pytest.skip("Read-only filesystem test only runs inside Docker container")

    with pytest.raises(OSError) as excinfo:
        with open("/app/test_persistence.txt", "w") as f:
            f.write("This should fail")

    assert "Read-only file system" in str(excinfo.value) or excinfo.value.errno == 30

def test_tmp_is_writable():
    """Verify that /tmp is writable (mapped to tmpfs)."""
    test_file = "/tmp/test_write.txt"
    try:
        with open(test_file, "w") as f:
            f.write("This should succeed")
        assert os.path.exists(test_file)
    finally:
        if os.path.exists(test_file):
            os.remove(test_file)

def test_tempfile_module_uses_tmp():
    """Verify Python's tempfile module defaults to the writable /tmp."""
    with tempfile.NamedTemporaryFile(delete=True) as tf:
        tf.write(b"data")
        tf.flush()
        # Check directory of the created temp file
        assert os.path.dirname(tf.name) == "/tmp"
        assert os.path.exists(tf.name)

def test_logging_no_file_access():
    """Verify the application does not attempt to write to logs directory."""
    # This is a bit passive, but we check if the logs dir is writable.
    # It should NOT be writable in the container.
    log_dir = "/app/logs"
    
    # If the dir exists (it might from COPY), we shouldn't be able to write new files
    if os.path.exists(log_dir):
        with pytest.raises(OSError):
            with open(os.path.join(log_dir, "test.log"), "w") as f:
                f.write("fail")
