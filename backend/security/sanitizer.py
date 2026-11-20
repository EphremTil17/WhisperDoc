import re

from logging_config import log


class Sanitizer:
    """
    Principal-level output sanitizer for the WhisperDoc backend.

    Prevents Reflected Terminal Injection by neutralizing ANSI escape
    sequences and control characters that could be hallucinated by the model
    or embedded in malicious audio. Printable Unicode (accents, symbols,
    typographic punctuation) is preserved: it cannot drive a terminal, and
    stripping it corrupts dictated text.
    """

    # C0 controls (except \t \n \r), DEL, and C1 controls. ESC (\x1b) and the
    # 8-bit CSI introducer (\x9b) are covered, so any escape sequence the ANSI
    # pattern below misses is still rendered inert.
    CONTROL_CHAR_REGEX = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")

    # Comprehensive ANSI stripper covering CSI and OSC
    ANSI_ESCAPE_REGEX = re.compile(r"\x1b\[[0-9;]*[mGKH]|\x1b]0;[^\x07]*\x07")

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

            # 2. Remove remaining control characters
            cleaned = cls.CONTROL_CHAR_REGEX.sub("", cleaned)

            # 3. Final cleaning
            cleaned = cleaned.strip()

            if cleaned != text:
                log.debug(
                    "Sanitizer neutralized control sequences in transcription output."
                )

            return cleaned
        except Exception as e:
            log.error(f"Backend Sanitization failure: {e}")
            # Fail-secure: return empty if processing fails
            return ""
