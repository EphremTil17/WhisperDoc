import os
import time
from typing import Tuple
from logging_config import log

# --- Configuration ---
IDLE_TIMEOUT_SECONDS = int(os.getenv("IDLE_TIMEOUT_SECONDS", "300"))
HANDSHAKE_TIMEOUT_SECONDS = int(os.getenv("HANDSHAKE_TIMEOUT_SECONDS", "15"))

BAN_FAILURE_THRESHOLD = int(os.getenv("BAN_FAILURE_THRESHOLD", "5"))
BAN_FAILURE_WINDOW_SECONDS = int(os.getenv("BAN_FAILURE_WINDOW_SECONDS", "60"))
BAN_DURATION_SECONDS = int(os.getenv("BAN_DURATION_SECONDS", "300"))

FLOOD_ATTEMPT_THRESHOLD = int(os.getenv("FLOOD_ATTEMPT_THRESHOLD", "50"))
FLOOD_ATTEMPT_WINDOW_SECONDS = int(os.getenv("FLOOD_ATTEMPT_WINDOW_SECONDS", "60"))
FLOOD_BAN_SECONDS = int(os.getenv("FLOOD_BAN_SECONDS", "60"))

MAX_CONNECTIONS = int(os.getenv("MAX_CONNECTIONS", "10"))

class SecurityGovernance:
    """Handles IP tracking, bans, and rate limiting."""
    def __init__(self):
        self.failure_tracker = {} # ip -> [timestamps of violations]
        self.attempt_tracker = {} # ip -> [timestamps of all connections]
        self.ban_tracker = {}     # ip -> timestamp_until

    def is_ip_banned(self, ip: str) -> Tuple[bool, int]:
        """Returns (is_banned, remaining_seconds)."""
        ban_until = self.ban_tracker.get(ip)
        if ban_until:
            now = time.time()
            if now < ban_until:
                return True, int(ban_until - now)
            else:
                del self.ban_tracker[ip]
                if ip in self.attempt_tracker: del self.attempt_tracker[ip]
                if ip in self.failure_tracker: del self.failure_tracker[ip]
        return False, 0

    def record_connection_attempt(self, ip: str):
        now = time.time()
        attempts = self.attempt_tracker.get(ip, [])
        attempts = [t for t in attempts if now - t < FLOOD_ATTEMPT_WINDOW_SECONDS]
        attempts.append(now)
        self.attempt_tracker[ip] = attempts
        
        if len(attempts) > FLOOD_ATTEMPT_THRESHOLD:
            log.error(f"IP {ip} flagged for Connection Spamming. Banning for {FLOOD_BAN_SECONDS}s.")
            self.ban_tracker[ip] = now + FLOOD_BAN_SECONDS

    def record_protocol_violation(self, ip: str):
        now = time.time()
        failures = self.failure_tracker.get(ip, [])
        failures = [t for t in failures if now - t < BAN_FAILURE_WINDOW_SECONDS]
        failures.append(now)
        self.failure_tracker[ip] = failures
        
        if len(failures) >= BAN_FAILURE_THRESHOLD:
            log.error(f"IP {ip} exceeded failure threshold ({BAN_FAILURE_THRESHOLD} in {BAN_FAILURE_WINDOW_SECONDS}s). Banning for {BAN_DURATION_SECONDS}s.")
            self.ban_tracker[ip] = now + BAN_DURATION_SECONDS

    def clear_old_trackers(self):
        now = time.time()
        self.failure_tracker = {ip: ts for ip, ts in self.failure_tracker.items() if now - ts[-1] < 3600}
        self.attempt_tracker = {ip: ts for ip, ts in self.attempt_tracker.items() if now - ts[-1] < 3600}
