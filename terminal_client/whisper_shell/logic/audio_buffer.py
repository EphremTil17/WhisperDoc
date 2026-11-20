from collections import deque
from typing import Awaitable, Callable

from loguru import logger


class AudioBufferManager:
    """
    Holds one utterance's audio while the connection is not yet ready, so
    speech captured during connect/handshake is streamed rather than lost.
    """

    # Safety cap: 16kHz mono 16-bit = ~32KB/s; 20,000 chunks (at 1024 frames)
    # is ~10 minutes. Beyond it the oldest audio is dropped to bound memory.
    MAX_CHUNKS = 20000

    def __init__(self):
        self._buffer: deque[bytes] = deque(maxlen=self.MAX_CHUNKS)
        self._overflow_logged = False

    def add(self, chunk: bytes) -> None:
        if len(self._buffer) == self.MAX_CHUNKS and not self._overflow_logged:
            logger.warning(
                "Audio buffer limit reached. Dropping oldest audio to bound memory."
            )
            self._overflow_logged = True
        self._buffer.append(chunk)

    async def flush(self, send_callback: Callable[[bytes], Awaitable[None]]) -> None:
        """Streams all buffered chunks, oldest first, through send_callback."""
        if not self._buffer:
            return

        logger.info(f"Flushing {len(self._buffer)} buffered audio chunks...")
        while self._buffer:
            await send_callback(self._buffer.popleft())

    def clear(self) -> None:
        self._buffer.clear()
        self._overflow_logged = False

    def __len__(self) -> int:
        return len(self._buffer)

    @property
    def is_empty(self) -> bool:
        return not self._buffer
