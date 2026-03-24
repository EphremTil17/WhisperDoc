import re

from logging_config import log


class Sanitizer:
    """
    Principal-level output sanitizer for the WhisperDoc backend.

    Prevents Reflected Terminal Injection by neutralizing control characters,
    ANSI escape sequences, and non-printable ASCII characters that could
    be hallucinated by the model or embedded in malicious audio.
    """

    # Whitelist: Basic printable ASCII (Space to ~) + safe whitespace
    # This prevents ANSI \x1b, Null \x00, and other control characters < \x20
    WHITELIST_REGEX = re.compile(r"[^\x20-\x7E\n\r\t]")

    # Comprehensive ANSI stripper covering CSI and OSC
    ANSI_ESCAPE_REGEX = re.compile(r"\x1b\[[0-9;]*[mGKH]|\x1b]0;.*?\x07")

    @classmethod
    def sanitize(cls, text: str) -> str:
        """
        Neutralizes all non-printable or suspicious characters from transcription results.
        """
        if not text:
            return ""

        try:
            # 1. Strip ANSI escape sequences explicitly
            cleaned = cls.ANSI_ESCAPE_REGEX.sub("", text)

            # 2. Apply strict whitelist (printable ASCII + safe whitespace)
            cleaned = cls.WHITELIST_REGEX.sub("", cleaned)

            # 3. Final cleaning
            cleaned = cleaned.strip()

            if cleaned != text:
                # We log this as info rather than warning to avoid log-spamming
                # if Whisper often produces tiny non-ASCII artifacts.
                log.debug(
                    "Sanitizer neutralized control sequences in transcription output."
                )

            return cleaned
        except Exception as e:
            log.error(f"Backend Sanitization failure: {e}")
            # Fail-secure: return empty if processing fails
            return ""
