# WhisperDoc Backend

The self-hosted speech server: FastAPI in a read-only Docker container, with a pluggable engine layer (faster-whisper in-process, or parakeet.cpp in a sidecar container). To run it, see [Setup](../docs/setup.md); for how it is secured, see [Architecture and security](../docs/architecture.md).

## API

| Endpoint | What it does |
|---|---|
| `GET /health` | Server status and whether the model is loaded |
| `POST /transcribe` | Transcribes an uploaded audio file. Needs `Authorization: Bearer <key>` and a `Content-Length`; uploads are capped at 25 MB, checked from the headers before the body is read (401 / 411 / 413) |
| `GET /ws` | The streaming WebSocket: a JSON handshake with a token first, then PCM audio; transcripts come back as JSON |

## Layout

| Path | What it holds |
|---|---|
| `api_server.py` | The FastAPI app: routes, startup, the upload guard |
| `engine/` | The engine interface, Whisper and Parakeet engines, the model manager (load and unload on demand), silence-based chunking for long audio |
| `protocol/` | The WebSocket handshake state machine and session handling |
| `auth/` | OIDC (JWKS, RS256) and the static API key |
| `security/` | Bans, flood control, and transcript sanitizing |
| `tools/` | Parakeet model provisioning (digest-verified) and its log filter |
| `tests/` | pytest suite, including live API and WebSocket tests against a running container |

## Engines

| Engine | Where it runs | Notes |
|---|---|---|
| Whisper (`ASR_ENGINE=whisper`) | In the API process, on CTranslate2 | GPU (`float16`) or CPU (`int8`); any faster-whisper model via `MODEL_NAME` |
| Parakeet (`ASR_ENGINE=parakeet`) | The `parakeet` container (parakeet.cpp) | NVIDIA GPU only; English; long audio is split at quiet points with timestamp-aware overlap |

Measurements: [speech engine benchmarks](../docs/benchmarks/README.md#speech-engines) and the [Parakeet report](engine/PARAKEET_BENCHMARK.md).

## Development

See [Development](../docs/development.md#backend) for the local environment, tests and CI.
