import re

from loguru import logger


class Sanitizer:
    """
    Output sanitizer for transcripts before they reach the clipboard/terminal.

    Mirrors the backend's Sanitizer: strips ANSI escape sequences and control
    characters that could drive a terminal, while preserving printable Unicode
    (accents, typographic punctuation, non-Latin scripts) so dictation is not
    corrupted.
    """

    # Comprehensive ANSI stripper covering CSI (colors/moves) and OSC (titles/etc).
    ANSI_ESCAPE_REGEX = re.compile(r"\x1b\[[0-9;]*[mGKH]|\x1b]0;[^\x07]*\x07")

    # C0 controls (except \t \n \r), DEL, and C1 controls. ESC (\x1b) and the
    # 8-bit CSI introducer (\x9b) are covered, so any escape sequence the ANSI
    # pattern misses is still rendered inert.
    CONTROL_CHAR_REGEX = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")

    @classmethod
    def sanitize(cls, text: str | None) -> str:
        if not text:
            return ""

        cleaned = cls.ANSI_ESCAPE_REGEX.sub("", text)
        cleaned = cls.CONTROL_CHAR_REGEX.sub("", cleaned).strip()

        if cleaned != text:
            logger.debug("Sanitizer neutralized control sequences in transcript.")

        return cleaned
