#!/usr/bin/env python3
"""
WhisperDoc Client - Live Audio Dictation
Optimized for Windows Native Hotkeys and Low-Latency Streaming.
"""

import os
import sys
import asyncio
import json
import time
import threading
import subprocess
import ctypes
from pathlib import Path

import numpy as np
import sounddevice as sd
import pyperclip
from pynput import keyboard
from dotenv import load_dotenv, set_key
from loguru import logger

# --- Windows Native Setup ---
if os.name == 'nt':
    from ctypes import wintypes
    user32 = ctypes.windll.user32

ENV_PATH = Path(".env")

def kill_conflicting_instances():
    """Finds and kills other running instances of this script using PowerShell."""
    current_pid = os.getpid()
    script_name = "whisper_client.py"
    try:
        ps_cmd = (
            f"Get-CimInstance Win32_Process | "
            f"Where-Object {{ ($_.Name -eq 'python.exe' -or $_.Name -eq 'pythonw.exe') "
            f"-and $_.CommandLine -like '*{script_name}*' "
            f"-and $_.ProcessId -ne {current_pid} }} | "
            f"Select-Object -ExpandProperty ProcessId"
        )
        output = subprocess.check_output(["powershell", "-Command", ps_cmd], creationflags=0x08000000)
        pids = [int(p) for p in output.decode().split() if p.strip().isdigit()]
        for pid in pids:
            logger.info(f"Terminating conflicting instance (PID: {pid})...")
            subprocess.run(f"taskkill /F /PID {pid}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if pids: time.sleep(1)
    except Exception as e:
        logger.debug(f"Instance cleanup skipped: {e}")

def setup_interactive():
    """Minimal interactive setup for first-run configuration."""
    logger.info("--- WhisperDoc Client Setup ---")
    
    current_uri = os.getenv("WHISPER_WS_URI", "ws://localhost:9989/ws")
    uri = input(f"Enter Server WebSocket URI [{current_uri}]: ").strip() or current_uri
    
    print("\nSelect Audio API:")
    print(" [1] WASAPI (Best) | [2] DirectSound | [3] MME | [0] All")
    api_choice = input("Choice [1]: ").strip() or "1"
    api_map = {"1": "Windows WASAPI", "2": "Windows DirectSound", "3": "MME", "4": "Windows WDM-KS"}
    target_api = api_map.get(api_choice)

    devices = sd.query_devices()
    host_apis = sd.query_hostapis()
    default_input = sd.query_hostapis()[0].get('default_input')
    
    print(f"\nAvailable Input Devices ({target_api or 'All'}):")
    for i, dev in enumerate(devices):
        if dev['max_input_channels'] > 0:
            api_name = host_apis[dev['hostapi']]['name']
            if target_api and api_name != target_api: continue
            marker = " (DEFAULT)" if i == default_input else ""
            print(f" [{i}] {dev['name']} | {api_name}{marker}")
    
    device_id = input(f"\nSelect Device ID [{default_input}]: ").strip() or str(default_input)
    
    if not ENV_PATH.exists(): ENV_PATH.touch()
    set_key(str(ENV_PATH), "WHISPER_WS_URI", uri)
    set_key(str(ENV_PATH), "AUDIO_DEVICE_ID", device_id)
    set_key(str(ENV_PATH), "RECORD_HOTKEY", "ctrl+alt+w")
    set_key(str(ENV_PATH), "SAMPLE_RATE", "16000")
    set_key(str(ENV_PATH), "CHANNELS", "1")
    set_key(str(ENV_PATH), "LOG_LEVEL", "INFO")
    
    logger.success("Setup complete. Default hotkey: ctrl+alt+w")
    logger.info("To change hotkey, edit RECORD_HOTKEY in .env")

if not ENV_PATH.exists() or "--setup" in sys.argv:
    setup_interactive()

load_dotenv()

# --- Config ---
WS_URI = os.getenv("WHISPER_WS_URI")
RECORD_HOTKEY = os.getenv("RECORD_HOTKEY", "ctrl+alt+w").lower()
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
DEVICE_ID = int(os.getenv("AUDIO_DEVICE_ID", 0))

logger.remove()
logger.add(sys.stdout, level=LOG_LEVEL, format="<white>{time:HH:mm:ss}</white> | <level>{level: <8}</level> | <level>{message}</level>")

class DictationClient:
    def __init__(self):
        self.is_recording = False
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.audio_queue = asyncio.Queue()
        self.kb = keyboard.Controller()
        self.device_rate = 16000

    def toggle(self):
        self.is_recording = not self.is_recording
        logger.info("🔴 Recording..." if self.is_recording else "⚪ Stopped. Processing...")

    def audio_callback(self, indata, frames, time, status):
        if status: logger.warning(status)
        if self.is_recording:
            if self.device_rate != 16000:
                duration = len(indata) / self.device_rate
                new_len = int(duration * 16000)
                audio = np.interp(np.linspace(0, duration, new_len), np.linspace(0, duration, len(indata)), indata.flatten())
            else:
                audio = indata.flatten()
            self.loop.call_soon_threadsafe(self.audio_queue.put_nowait, (audio * 32767).astype(np.int16).tobytes())

    def paste(self, text):
        if not text or not text.strip(): return
        logger.success(f"Result: {text}")
        pyperclip.copy(text)
        with self.kb.pressed(keyboard.Key.ctrl):
            self.kb.press('v')
            self.kb.release('v')

    async def run_ws(self):
        import websockets
        ws = None
        last_activity = time.time()
        IDLE_TIMEOUT = 300  # 5 minutes

        while True:
            try:
                # Wait for recording to start if we don't have a connection
                if not ws:
                    if not self.is_recording:
                        await asyncio.sleep(0.1)
                        continue
                    
                    # Wake up & Handshake
                    logger.info(f"Connecting to {WS_URI}...")
                    ws = await websockets.connect(WS_URI)
                    
                    # 1. Wait for Server Hello
                    hello_msg = json.loads(await ws.recv())
                    if hello_msg.get("event") == "hello":
                        server_ver = hello_msg.get("version")
                        status = hello_msg.get("status")
                        logger.success(f"Connected to {hello_msg.get('server')} (v{server_ver}) [Status: {status}]")
                        
                        # 2. Send Client Hello
                        await ws.send(json.dumps({
                            "event": "hello",
                            "client": "terminal_client",
                            "version": "1.1.0"
                        }))
                    else:
                        logger.warning("Protocol mismatch: No hello received.")
                    
                    last_activity = time.time()

                # If we are recording, drain the queue and send
                if self.is_recording:
                    while self.is_recording or not self.audio_queue.empty():
                        try:
                            # Get audio chunk with small timeout so we can check is_recording
                            chunk = await asyncio.wait_for(self.audio_queue.get(), 0.05)
                            await ws.send(chunk)
                            last_activity = time.time()
                        except asyncio.TimeoutError:
                            if not self.is_recording: break
                            continue
                    
                    # Done recording session - send signal
                    # Use EXACT spacing expected by backend: '{"event": "end-of-stream"}'
                    await ws.send('{"event": "end-of-stream"}')
                    
                    # Wait for response
                    while True:
                        resp_raw = await ws.recv()
                        resp = json.loads(resp_raw)
                        
                        # Handle Status Updates (e.g. Model Loading)
                        if resp.get("event") == "status":
                            logger.info(f"Server Status: {resp.get('message')}")
                            continue # Wait for next message (transcription)
                            
                        # Handle Transcription
                        if "text" in resp: 
                            self.paste(resp["text"])
                            break
                        
                        # Handle Errors
                        elif resp.get("event") == "error":
                            logger.error(f"Server Error [{resp.get('code')}]: {resp.get('message')}")
                            break
                        elif "error" in resp: # Legacy
                            logger.error(resp["error"])
                            break
                            
                    last_activity = time.time()

                # Idle check
                if ws and time.time() - last_activity > IDLE_TIMEOUT:
                    logger.info("Session idle for 5m. Closing connection.")
                    await ws.close()
                    ws = None
                
                await asyncio.sleep(0.1)

            except Exception as e:
                logger.error(f"WebSocket Error: {e}. Session reset.")
                if ws:
                    try: await ws.close()
                    except: pass
                ws = None
                # Clear queue on error
                while not self.audio_queue.empty(): self.audio_queue.get_nowait()
                await asyncio.sleep(1)

    def _parse_hk(self, s):
        mods, vk = 0, 0
        mod_map = {"ctrl": 0x0002, "alt": 0x0001, "shift": 0x0004, "win": 0x0008}
        vk_map = {f"f{i}": 0x6F+i for i in range(1, 13)}
        vk_map.update({"ins": 0x2D, "del": 0x2E, "space": 0x20})
        for p in s.split("+"):
            p = p.strip()
            if p in mod_map: mods |= mod_map[p]
            elif p in vk_map: vk = vk_map[p]
            elif len(p) == 1: vk = ord(p.upper())
        return mods, vk

    def start(self):
        if os.name == 'nt':
            m, v = self._parse_hk(RECORD_HOTKEY)
            def loop():
                for i in range(2):
                    if user32.RegisterHotKey(None, 1, m, v): break
                    if i == 0: kill_conflicting_instances()
                    else: return logger.error("Hotkey busy.")
                msg = wintypes.MSG()
                while user32.GetMessageW(ctypes.byref(msg), None, 0, 0):
                    if msg.message == 0x0312: self.toggle()
                user32.UnregisterHotKey(None, 1)
            threading.Thread(target=loop, daemon=True).start()
        else:
            hk = {f"<{RECORD_HOTKEY.replace('+', '><')}>" : self.toggle}
            keyboard.GlobalHotKeys(hk).start()

        try:
            info = sd.query_devices(DEVICE_ID, 'input')
            self.device_rate = int(info.get('default_samplerate', 16000))
            with sd.InputStream(samplerate=self.device_rate, channels=1, callback=self.audio_callback, device=DEVICE_ID):
                logger.success(f"Mic Ready: {info['name']} ({self.device_rate}Hz)")
                self.loop.run_until_complete(self.run_ws())
        except Exception as e: logger.critical(e)

if __name__ == "__main__":
    try: DictationClient().start()
    except KeyboardInterrupt: pass
