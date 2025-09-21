#!/usr/bin/env python3
"""
Simple test client for WhisperDoc API
Tests health check and transcription endpoints
"""

import sys
import time
import requests
import argparse
from pathlib import Path

def test_health(base_url: str, verbose: bool = False) -> bool:
    """Test the health endpoint"""
    try:
        if verbose:
            print(f"Testing health endpoint: {base_url}/health")
        
        response = requests.get(f"{base_url}/health", timeout=10)
        
        if verbose:
            print(f"Response status: {response.status_code}")
            print(f"Response body: {response.json()}")
        
        if response.status_code == 200:
            data = response.json()
            if data.get("status") == "healthy":
                print("✅ Health check passed - API is ready")
                return True
            else:
                print(f"API is running but not healthy: {data.get('message', 'Unknown issue')}")
                return False
        else:
            print(f"❌ Health check failed with status {response.status_code}")
            return False
            
    except requests.exceptions.ConnectionError:
        print("❌ Connection failed - is the API server running?")
        print("   Try: docker compose up -d whisper-backend")
        return False
    except Exception as e:
        print(f"❌ Health check error: {e}")
        return False

def test_transcription(base_url: str, audio_file: str, verbose: bool = False) -> bool:
    """Test the transcription endpoint with an audio file"""
    audio_path = Path(audio_file)
    
    if not audio_path.exists():
        print(f"❌ Audio file not found: {audio_file}")
        return False
    
    if not audio_path.suffix.lower() in ['.wav', '.mp3', '.m4a', '.flac', '.ogg']:
        print(f"Warning: {audio_path.suffix} might not be supported")
    
    try:
        if verbose:
            print(f"Testing transcription endpoint: {base_url}/transcribe")
            print(f"Audio file: {audio_file} ({audio_path.stat().st_size} bytes)")
        
        with open(audio_path, 'rb') as f:
            files = {'file': (audio_path.name, f, 'audio/wav')}
            
            print(f"Uploading {audio_path.name}...")
            start_time = time.time()
            
            response = requests.post(
                f"{base_url}/transcribe", 
                files=files, 
                timeout=120  # Allow up to 2 minutes for transcription
            )
            
            upload_time = time.time() - start_time
        
        if verbose:
            print(f"Response status: {response.status_code}")
            print(f"Total time: {upload_time:.2f}s")
        
        if response.status_code == 200:
            data = response.json()
            
            print("✅ Transcription successful!")
            print(f"Text: {data['text']}")
            print(f"Language: {data['language']} (confidence: {data['language_probability']:.2f})")
            print(f"Duration: {data['duration']:.2f}s")
            print(f"Processing time: {data['processing_time']:.2f}s")
            
            if verbose and data.get('segments'):
                print("\nSegments:")
                for i, segment in enumerate(data['segments']):
                    print(f"  {i+1}. [{segment['start']:.2f}s - {segment['end']:.2f}s] {segment['text']}")
            
            return True
        else:
            print(f"❌ Transcription failed with status {response.status_code}")
            try:
                error_data = response.json()
                print(f"   Error: {error_data.get('detail', 'Unknown error')}")
            except:
                print(f"   Raw response: {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        print("❌ Request timed out - transcription took too long")
        return False
    except Exception as e:
        print(f"❌ Transcription error: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description="Test WhisperDoc API")
    parser.add_argument("--url", default="http://localhost:9989", 
                       help="API base URL (default: http://localhost:9989)")
    parser.add_argument("--file", "-f", 
                       help="Audio file to transcribe")
    parser.add_argument("--health-only", action="store_true",
                       help="Only test health endpoint")
    parser.add_argument("--verbose", "-v", action="store_true",
                       help="Verbose output")
    
    args = parser.parse_args()
    
    print("WhisperDoc API Test Client")
    print(f"API URL: {args.url}")
    print()
    
    # Always test health first
    health_ok = test_health(args.url, args.verbose)
    
    if not health_ok:
        print("\nMake sure the API server is running:")
        print("   docker compose up -d whisper-backend")
        print("   docker compose logs -f whisper-backend")
        sys.exit(1)
    
    if args.health_only:
        print("\nHealth check complete!")
        sys.exit(0)
    
    # Test transcription if file provided
    if args.file:
        print()
        transcription_ok = test_transcription(args.url, args.file, args.verbose)
        
        if transcription_ok:
            print("\nAll tests passed!")
            sys.exit(0)
        else:
            sys.exit(1)
    else:
        print("\nTo test transcription, provide an audio file:")
        print(f"   python {sys.argv[0]} --file sample.wav")
        print("\nHealth check complete!")

if __name__ == "__main__":
    main()
