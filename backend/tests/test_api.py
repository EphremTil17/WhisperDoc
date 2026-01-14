import pytest
import requests
import os
import sys

# Configuration
# Configuration
API_URL = "http://localhost:9989"
API_KEY = os.getenv("WHISPER_DOC_API_KEY", "test_secret_key")

def get_headers():
    return {"Authorization": f"Bearer {API_KEY}"}

def check_server():
    """Returns True if the server is alive, otherwise skips the test."""
    try:
        requests.get(f"{API_URL}/health", timeout=1)
        return True
    except:
        return False

def test_http_health():
    """Verify the /health endpoint returns 200 and healthy status."""
    if not check_server():
        pytest.skip(f"Server not found at {API_URL}")
        
    response = requests.get(f"{API_URL}/health", timeout=5)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"

def test_http_transcribe_dummy():
    """Verify /transcribe fails gracefully with no file or wrong type."""
    if not check_server():
        pytest.skip(f"Server not found at {API_URL}")
        
    # Test with no data - should return 422 Unprocessable Entity
    # We must provide auth to reach the validation logic
    response = requests.post(f"{API_URL}/transcribe", headers=get_headers(), timeout=5)
    assert response.status_code == 422 

def test_http_transcription_real():
    """Verify full transcription via HTTP if a test file exists."""
    if not check_server():
        pytest.skip(f"Server not found at {API_URL}")

    audio_file = "assets/jfk.flac"
    if not os.path.exists(audio_file):
        pytest.skip(f"Test file {audio_file} not found. Skipping real transcription test.")
        
    with open(audio_file, 'rb') as f:
        files = {'file': (os.path.basename(audio_file), f, 'audio/wav')}
        response = requests.post(f"{API_URL}/transcribe", files=files, headers=get_headers(), timeout=30)
            
    assert response.status_code == 200
    data = response.json()
    assert "text" in data
    assert len(data["text"]) > 0

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=API_URL, help="API URL")
    parser.add_argument("--file", help="Audio file to transcribe")
    args = parser.parse_args()
    API_URL = args.url
    
    print(f"=== Testing HTTP API at {API_URL} ===")
    if check_server():
        test_http_health()
        print("✅ Health Check Passed")
        if args.file and os.path.exists(args.file):
            print(f"Testing transcription with {args.file}...")
            with open(args.file, 'rb') as f:
                files = {'file': (os.path.basename(args.file), f, 'audio/wav')}
                response = requests.post(f"{API_URL}/transcribe", files=files, timeout=30)
                if response.status_code == 200:
                    print(f"✅ Transcription Success: {response.json()['text'][:100]}...")
                else:
                    print(f"❌ Transcription Failed: {response.text}")
    else:
        print(f"❌ Server not reachable at {API_URL}")
        sys.exit(1)