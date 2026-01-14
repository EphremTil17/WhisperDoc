import asyncio
import json
import time
import sys
from urllib.parse import urlparse
from loguru import logger
import websockets
import requests
import ipaddress
import socket
from .config import cfg, SecureConfig

class TransportManager:
    def __init__(self):
        self.ws = None
        self.uri = cfg.WS_URI
        self.hostname = urlparse(self.uri).hostname or "localhost"
        self._prepare_uri()

    def _prepare_uri(self):
        """Parses URI and enforces Transport Security (TLS/WSS)."""
        parsed = urlparse(self.uri)
        hostname = parsed.hostname or "localhost"
        scheme = parsed.scheme
        
        # Enforce TLS for remote connections
        if hostname not in ["localhost", "127.0.0.1", "0.0.0.0"]:
            if scheme == "ws":
                logger.warning("Remote connection detected. Enforcing SSL/TLS (wss://).")
                scheme = "wss"
            elif scheme == "http":
                scheme = "https"
        
        self.final_uri = f"{scheme}://{parsed.netloc}{parsed.path}"
        if parsed.query: self.final_uri += f"?{parsed.query}"
        logger.info(f"Target Server: {self.final_uri}")

    def check_health(self):
        """Performs a Pre-flight Health Check."""
        # Convert WS/WSS -> HTTP/HTTPS
        parsed = urlparse(self.final_uri)
        scheme = "https" if parsed.scheme == "wss" else "http"
        health_url = f"{scheme}://{parsed.netloc}/health"
        
        logger.info(f"Checking Server Health: {health_url}...")
        try:
            resp = requests.get(health_url, timeout=5, verify=False) 
        except requests.exceptions.SSLError:
             # Fallback logic for private IPs
             is_private = False
             try:
                 ip = socket.gethostbyname(parsed.hostname)
                 if ipaddress.ip_address(ip).is_private: is_private = True
             except: pass
             
             if is_private:
                  logger.warning(f"HTTPS failed. Falling back to HTTP for private IP ({ip})...")
                  health_url = health_url.replace("https://", "http://")
                  try:
                      resp = requests.get(health_url, timeout=5)
                  except: return False
             else:
                  logger.error(f"SSL Error on Public IP. Aborting.")
                  return False
        except Exception as e:
            logger.error(f"Health Check Error: {e}")
            return False

        if resp.status_code == 200:
            logger.success("Server is online and healthy.")
            return True
        logger.error(f"Server returned status {resp.status_code}")
        return False

    async def connect(self):
        """Establishes authenticated WebSocket connection."""
        if self.ws: return
        
        api_key = SecureConfig.get_api_key(self.hostname) # Prompts if missing
        
        # Add auth token
        sep = "&" if "?" in self.final_uri else "?"
        connect_uri = f"{self.final_uri}{sep}token={api_key}"
        
        try:
            logger.info(f"Connecting to {self.hostname}...")
            self.ws = await websockets.connect(connect_uri)
        except Exception as e:
            # WSS -> WS Fallback for Private IPs
            is_private = False
            try:
                 ip = socket.gethostbyname(self.hostname)
                 if ipaddress.ip_address(ip).is_private: is_private = True
            except: pass

            if "WRONG_VERSION_NUMBER" in str(e) and is_private:
                logger.warning(f"WSS failed. Falling back to WS for private IP ({ip})...")
                fallback_uri = connect_uri.replace("wss://", "ws://")
                self.ws = await websockets.connect(fallback_uri)
            else:
                raise e

        # Server Handshake (TWO-WAY)
        hello = json.loads(await self.ws.recv())
        if hello.get("event") == "hello":
             logger.success(f"Connected to Backend (v{hello.get('version')}) [Status: {hello.get('status')}]")
             
             # **CRITICAL**: Send Client Hello response to complete handshake
             from .config import CLIENT_VERSION
             await self.ws.send(json.dumps({
                 "event": "hello",
                 "client": "whisper_shell",
                 "version": CLIENT_VERSION
             }))
        else:
             logger.warning("Protocol mismatch: No hello received.")

    async def send(self, data):
        if self.ws: await self.ws.send(data)

    async def recv(self):
        if self.ws: return await self.ws.recv()
        return None

    async def close(self):
        if self.ws:
            await self.ws.close()
            self.ws = None
