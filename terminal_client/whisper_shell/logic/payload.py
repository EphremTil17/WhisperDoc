from typing import Dict


class PayloadBuilder:
    """
    Standardizes WebSocket payloads to match backend expectations.
    """

    @staticmethod
    def build_hello(token: str, version: str, incognito: bool = False) -> Dict:
        """Constructs the mandatory application-level handshake payload.

        The terminal client authenticates with a static API key only.
        """
        return {
            "event": "hello",
            "client": "whisper.client.terminal",
            "version": version,
            "auth_type": "api_key",
            "token": token,
            "incognito": incognito,
        }

    @staticmethod
    def build_end_of_stream() -> Dict:
        return {"event": "end-of-stream"}
