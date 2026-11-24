# WhisperDoc - Speech-to-Text System v3.3.0

Press a hotkey, speak, and your words appear wherever your cursor is. WhisperDoc is private, fast dictation for the desktop. Run it on your own GPU server, or send it straight to Groq or OpenRouter with your own key.

<img width="3375" height="3363" alt="WhisperDoc Github Preview" src="https://github.com/user-attachments/assets/c2c3037a-171c-42dc-a3e6-e72b8ef94d09" />

## Demo Video:

https://github.com/user-attachments/assets/906170ee-6d2a-4bf5-a881-926f03e0862a

## Highlights

- **Your choice of engine.** Self-host Whisper or NVIDIA Parakeet in Docker (on a GPU or the CPU), or use Groq or any of OpenRouter's speech models. You pick with one selector in the app.
- **Fast.** On a desktop GPU, Parakeet turns a 9-second clip into text in about 75 ms. Groq has text back about 0.2–0.3 s after you let go of the hotkey. The connection opens while you talk, so the upload never waits on it.
- **Models picked on evidence.** The OpenRouter list is live, with each model's current latency and its word error rate. New models appear and retired ones are flagged, without an app update.
- **Output styles.** Clean, Pro, Casual, Tech (exact function names, file paths and commands for coding agents) or your own. A rewrite takes about 0.26 s on Groq. On OpenRouter you choose the rewrite model.
- **Private by design.** The server never logs what you said. Incognito keeps nothing, zero data retention on OpenRouter is on by default, keys stay in Windows Credential Manager, and history is encrypted.
- **A hardened server.** It runs in a read-only container, with OIDC sign-in with PKCE, a handshake before any audio is accepted, and automatic bans.
- **Yours to shape.** Every server setting lives in one `.env`, the engine layer is pluggable, and you can write your own styles. [Open benchmarks](docs/benchmarks/README.md) back every default.

## Quick start

**Just the app:** install the latest [Windows release](https://github.com/EphremTil17/WhisperDoc/releases/latest), open **Account**, choose **Groq** (free) or **OpenRouter**, and paste your key.

**Your own server** (Linux, Docker):

```bash
git clone https://github.com/EphremTil17/WhisperDoc.git
cd WhisperDoc
./setup.sh
```

It picks GPU or CPU, generates an API key, builds and starts the server, and waits until it is healthy. Other systems, manual steps and configuration are in the [Setup guide](docs/setup.md).

## Clients

### Flutter Client (Windows) v3.3.0

The main app: a quiet window with a global hotkey and auto-paste, three sources (your server, Groq, OpenRouter), output styles, local encrypted history, and microphone hot-plug. → [Flutter client guide](flutter_client/README.md)

### Python Terminal Client v3.3.0

A lightweight Windows client for your own server, for fallback and debugging. → [Terminal client guide](terminal_client/README.md)

## Documentation

| Guide | What's in it |
|---|---|
| [Setup](docs/setup.md) | Installing the app, running a server (script or manual), configuration, troubleshooting |
| [Architecture and security](docs/architecture.md) | How the pieces fit, identity, active defense, the container, privacy |
| [Benchmarks](docs/benchmarks/README.md) | Speech engines, OpenRouter speech and rewrite models, style prompts, and how to rerun them |
| [Development](docs/development.md) | Local development, tests, pre-commit hooks, CI/CD, releases, contributing |
| [Backend](backend/README.md) | API endpoints, code layout, engines |
| [Release notes](docs/release_notes/) and [changelog](docs/CHANGELOG.md) | What changed in each version |
| [Roadmap](docs/roadmap.md) | What's planned further out |

## Project Phases

| Phase | Description | Status |
|---|---|---|
| Phase 1 | Core Backend & REST API | ✅ Complete |
| Phase 2 | WebSocket Streaming | ✅ Complete |
| Phase 3 | Robust Dev Terminal Client | ✅ Complete |
| Phase 4 | Flutter Windows Client | ✅ Complete |
| Phase 5 | Dynamic Model Loading | ✅ Complete |
| Phase 6 | Architecture Refactoring | ✅ Complete |
| Phase 7 | Infrastructure Hardening | ✅ Complete |
| Phase 8 | Client and Backend Hardening | ✅ Complete |
| Phase 9 | OIDC Identity Hardening & Verification Suite (v2.13.0) | ✅ Complete |
| Phase 10 | Optimization and Weight Shedding (v2.14.0) | ✅ Complete |
| Phase 11 | Error Handling & Update Controls (v2.20.0) | ✅ Complete |
| Phase 12 | UI and Functional Improvements | 🚧 In Progress |
| Phase 13 | Multi-Engine ASR Abstraction (v2.23.0) | ✅ Complete |
| Phase 14 | Multi-Connection Path [Groq Cloud] (v2.24.0) | ✅ Complete |
| Phase 15 | Client-Edge Dictation Profiles (v3.0.0) | ✅ Complete |
| Phase 16 | Security Maintenance, Audits & Pen Testing (v3.1.0) | 🚧 In Progress |
| Phase 17 | OpenRouter Source, Model Choice & Open Benchmarks (v3.3.0) | ✅ Complete |

## License

[GNU General Public License v3.0](LICENSE). Groq, OpenRouter, OpenAI Whisper, NVIDIA Parakeet and other names are trademarks of their owners; WhisperDoc is not affiliated with them.
