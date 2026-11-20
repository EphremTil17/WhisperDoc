"""
Tests for the PayloadBuilder.
"""

from whisper_shell.logic.payload import PayloadBuilder


class TestBuildHello:
    def test_structure(self):
        payload = PayloadBuilder.build_hello(token="key123", version="9.9.9")
        assert payload["event"] == "hello"
        assert payload["client"] == "whisper.client.terminal"
        assert payload["token"] == "key123"
        assert payload["auth_type"] == "api_key"
        assert payload["version"] == "9.9.9"
        assert payload["incognito"] is False

    def test_incognito_flag(self):
        payload = PayloadBuilder.build_hello(token="x", version="1.0.0", incognito=True)
        assert payload["incognito"] is True


class TestBuildEndOfStream:
    def test_structure(self):
        payload = PayloadBuilder.build_end_of_stream()
        assert payload == {"event": "end-of-stream"}
