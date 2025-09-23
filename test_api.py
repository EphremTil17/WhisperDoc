#!/usr/bin/env python3
"""
Simple test client for WhisperDoc API
Tests health check, transcription, and the remote logging system.
"""

import os
import sys
import time
import requests
import argparse
from pathlib import Path
import atexit
from queue import Queue, Empty
from threading import Thread, Event
from datetime import datetime

# Use loguru for structured, colorful logging
from loguru import logger

# --- Remote Logging Configuration ---

LOG_SERVER_URL = f"{os.getenv('API_HOST', 'http://localhost')}:{os.getenv('API_PORT', '9989')}/log"
LOG_SOURCE_ID = "TestClient"
LOG_BATCH_INTERVAL = 5  # seconds
LOG_BATCH_SIZE = 100

class RemoteLogSink:
    """
    A loguru sink that sends log records to a remote server in batches.
    It uses a background thread to avoid blocking the main application.
    """
    def __init__(self, url: str, source: str, interval: int, batch_size: int):
        self.url = url
        self.source = source
        self.interval = interval
        self.batch_size = batch_size
        self.queue = Queue()
        self._stop_event = Event()
        self._thread = Thread(target=self._run, daemon=True)
        self._thread.start()
        atexit.register(self.stop)

    def write(self, message):
        """This is the method called by loguru for each new log record."""
        record = message.record
        log_entry = {
            "source": self.source,
            "level": record["level"].name,
            "message": record["message"],
            "timestamp": record["time"].isoformat(),
        }
        self.queue.put(log_entry)

    def _run(self):
        """The main loop for the background worker thread."""
        while not self._stop_event.is_set():
            self._stop_event.wait(self.interval)
            self._send_batch()

    def _send_batch(self):
        """Collect logs from the queue and send them as a batch."""
        if self.queue.empty():
            return

        batch = []
        while not self.queue.empty() and len(batch) < self.batch_size:
            try:
                batch.append(self.queue.get_nowait())
            except Empty:
                break
        
        if batch:
            try:
                response = requests.post(self.url, json={"logs": batch}, timeout=5)
                response.raise_for_status()
            except requests.RequestException as e:
                # In a real app, you might want to handle this more gracefully
                # (e.g., retry, save to a local file)
                print(f"Error sending logs to remote server: {e}", file=sys.stderr)

    def stop(self):
        """Stop the background thread and send any remaining logs."""
        logger.info("Stopping remote logger, sending final batch...")
        self._stop_event.set()
        self._send_batch()  # Final send-off
        self._thread.join(timeout=2)

def configure_logging(verbose: bool):
    """Configure loguru with console and remote sinks."""
    logger.remove() # Remove default handler
    
    # Console logger
    log_level = "DEBUG" if verbose else "INFO"
    logger.add(
        sys.stdout, 
        level=log_level,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan> - <level>{message}</level>",
        colorize=True
    )

    # Remote logger sink
    remote_sink = RemoteLogSink(LOG_SERVER_URL, LOG_SOURCE_ID, LOG_BATCH_INTERVAL, LOG_BATCH_SIZE)
    logger.add(remote_sink.write, level="INFO", catch=True)
    
    logger.info("Logging configured. Remote logs will be sent to " + LOG_SERVER_URL)


def test_health(base_url: str) -> bool:
    """Test the health endpoint"""
    try:
        logger.info(f"Testing health endpoint: {base_url}/health")
        response = requests.get(f"{base_url}/health", timeout=10)
        
        logger.debug(f"Response status: {response.status_code}")
        logger.debug(f"Response body: {response.json()}")
        
        if response.status_code == 200 and response.json().get("status") == "healthy":
            logger.success("Health check passed - API is ready")
            return True
        else:
            logger.error(f"API is running but not healthy: {response.json().get('message', 'Unknown issue')}")
            return False
            
    except requests.exceptions.ConnectionError:
        logger.critical("Connection failed - is the API server running?")
        logger.warning("Try: docker compose up -d whisper-backend")
        return False
    except Exception as e:
        logger.error(f"Health check error: {e}")
        return False

def test_transcription(base_url: str, audio_file: str) -> bool:
    """Test the transcription endpoint with an audio file"""
    audio_path = Path(audio_file)
    
    if not audio_path.exists():
        logger.error(f"Audio file not found: {audio_file}")
        return False
    
    try:
        logger.info(f"Testing transcription on {audio_path.name} ({audio_path.stat().st_size} bytes)")
        
        with open(audio_path, 'rb') as f:
            files = {'file': (audio_path.name, f, 'audio/wav')}
            start_time = time.time()
            
            response = requests.post(f"{base_url}/transcribe", files=files, timeout=120)
            
            upload_time = time.time() - start_time
        
        logger.debug(f"Response status: {response.status_code}")
        logger.info(f"Request completed in {upload_time:.2f}s")
        
        if response.status_code == 200:
            data = response.json()
            logger.success("Transcription successful!")
            logger.info(f"Text: {data['text']}")
            logger.debug(f"Language: {data['language']} (confidence: {data['language_probability']:.2f})")
            return True
        else:
            logger.error(f"Transcription failed with status {response.status_code}")
            try:
                logger.warning(f"Error detail: {response.json().get('detail', 'Unknown error')}")
            except:
                logger.warning(f"Raw response: {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        logger.error("Request timed out - transcription took too long")
        return False
    except Exception as e:
        logger.opt(exception=True).error(f"An unexpected error occurred during transcription")
        return False

def main():
    parser = argparse.ArgumentParser(description="Test WhisperDoc API")
    parser.add_argument("--url", default=f"http://localhost:{os.getenv('API_PORT', '9989')}", 
                       help=f"API base URL (default: http://localhost:{os.getenv('API_PORT', '9989')})")
    parser.add_argument("--file", "-f", help="Audio file to transcribe")
    parser.add_argument("--health-only", action="store_true", help="Only test health endpoint")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable debug logging")
    
    args = parser.parse_args()
    
    configure_logging(args.verbose)
    
    logger.info("--- Starting WhisperDoc API Test Client ---")
    logger.debug(f"API URL set to {args.url}")
    
    health_ok = test_health(args.url)
    
    if not health_ok:
        logger.critical("Health check failed. Aborting tests.")
        sys.exit(1)
    
    if args.health_only:
        logger.success("Health check complete!")
        sys.exit(0)
    
    if args.file:
        transcription_ok = test_transcription(args.url, args.file)
        
        if transcription_ok:
            logger.success("--- All tests passed! ---")
            sys.exit(0)
        else:
            logger.error("--- Tests failed. ---")
            sys.exit(1)
    else:
        logger.info("Health check complete. To test transcription, provide an audio file with --file.")

if __name__ == "__main__":
    main()