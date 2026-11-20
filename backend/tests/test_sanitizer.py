"""Unit tests for the transcription output sanitizer."""

import pytest

from security.sanitizer import Sanitizer


@pytest.mark.parametrize(
    "text",
    [
        "José ordered a café au lait",
        "naïve résumé — “quoted” and ‘single’",
        "It costs €20 at 25°C, ½ off",
        "Ünïcödé Ελληνικά 日本語",
        "line one\nline two\ttabbed",
    ],
)
def test_printable_unicode_is_preserved(text):
    assert Sanitizer.sanitize(text) == text


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("\x1b[31mred\x1b[0m text", "red text"),
        ("\x1b]0;title\x07hello", "hello"),
        ("bell\x07 null\x00 del\x7f", "bell null del"),
        ("c1\x9b31m csi", "c131m csi"),
        ("esc\x1b(0 charset", "esc(0 charset"),
        ("  padded  ", "padded"),
    ],
)
def test_escape_sequences_and_controls_are_removed(text, expected):
    assert Sanitizer.sanitize(text) == expected


def test_empty_input_returns_empty_string():
    assert Sanitizer.sanitize("") == ""
