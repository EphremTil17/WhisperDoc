# Architecture and security

## How the pieces fit

```
 Windows app / terminal client ──── wss:// (handshake, then PCM audio) ────▶ WhisperDoc backend
        │                                                                    (FastAPI, read-only container)
        │                                                                           │
        │                                                                    ┌──────┴───────┐
        │                                                               faster-whisper   parakeet.cpp
        │                                                               (in-process)     (sidecar container)
        │
        ├── HTTPS, your own key ──▶ Groq        (Whisper; Qwen for styles)
        └── HTTPS, your own key ──▶ OpenRouter  (any speech model; any chat model for styles)
```

- **Backend**: a Dockerized FastAPI server with a pluggable engine layer. With Whisper the API process holds the model; with Parakeet it is model-free and calls the native parakeet.cpp server in its own container, so a native memory fault can't take down the API ([why](PARAKEET_NEMO_TO_CPP_MIGRATION.md)). Exactly one model is loaded either way.
- **Clients** talk to the backend over a WebSocket, or straight to Groq or OpenRouter with the user's own key; the cloud paths never touch the backend.
- **Output styles** (Clean, Pro, Casual, Tech, custom) rewrite the transcript on the client with the cloud source's chat model. If a rewrite fails, the raw transcript is pasted and the reason is shown.

## Security

### Identity and transport

- **OIDC with PKCE**, run in the system browser, never an in-app web view. It works with any provider that publishes OIDC discovery and signs tokens with RS256; the reference setup uses Authentik. Tokens are verified as RS256 only, rejecting algorithm-confusion (HS256) and `none` attacks; an unknown signing key triggers one rate-limited JWKS refetch, so key rotation needs no restart.
- **A static API key** for clients without sign-in, compared in constant time.
- **The handshake cage**: a strict WebSocket state machine. Nothing is processed and no audio is accepted until a valid handshake is acknowledged; a client that streams audio first is dropped and banned. Clients buffer audio locally and send it only after the acknowledgement.
- **Sign-in scope**: the Flutter client sends its sign-in only to the built-in server or one the user explicitly trusted, and forgets trust on sign-out. Plain `ws://` is refused except to local or private (RFC 1918) addresses.

### Active defense

- **Bans and flood control**: repeated failures or connection floods get a `1008 (Policy Violation)` close and a timed IP ban. Every error carries a structured `error_code` (`AUTH_FAILED`, `VERSION_OUTDATED`, `IP_BANNED`, …) that clients route on, never message text.
- **Trusted proxy hops only**: `X-Forwarded-For` is honoured only from Docker bridge networks, so clients can't spoof their address to dodge or redirect a ban.
- **Upload guard**: `POST /transcribe` authenticates and size-checks on headers alone (401 / 411 / 413) before reading any body; ffmpeg runs under a wall-clock timeout and a duration cap.
- **Version gate**: clients older than `MIN_CLIENT_VERSION` are refused with `VERSION_OUTDATED`; older than `SEC_CLIENT_VERSION`, they are advised to update.

### The container

- **Read-only root filesystem**, `/tmp` as the only writable path, `no-new-privileges`, all capabilities dropped for Parakeet, and the port bound to `127.0.0.1`.
- **Lean image**: no PyTorch (faster-whisper runs on CTranslate2), static ffmpeg, pruned layers; the Whisper image is about 4.3 GB.
- **VRAM on demand**: the model unloads after a period of inactivity, and `malloc_trim` returns the memory to the system.

### Privacy

- **Transcript text is never logged** by the server, only its length.
- **Incognito**: nothing is written to disk on the server or kept in the client's history for that dictation.
- **On the client**: keys and tokens live in Windows Credential Manager; history is a local SQLite database with every entry AES-256-GCM encrypted, keyed per installation, keeping the newest 100.
- **OpenRouter**: zero data retention is on by default, enforced on every request (speech and styles), so only hosts that keep nothing are used. Turning it off asks first.
- **Sanitizing**: every component strips ANSI sequences and control characters from transcripts while keeping accents, typographic punctuation and non-Latin scripts. The Flutter client pastes only a transcript it asked for, as plain text.

### Desktop integration

- **Single instance**: a Win32 named mutex keeps one copy running, so hotkeys and the microphone are never contested.
- **Hot-plug**: Core Audio notifications re-check microphones the moment one is plugged in or removed, falling back to the system default.
