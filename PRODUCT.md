# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

<!-- The client is a native Flutter Windows desktop app (fixed 420×600 frameless window).
     Impeccable's platform values are web/ios/android/adaptive; "web" is the closest
     design-language fit (desktop, pointer + keyboard). Design for Windows desktop. -->

## Users

The broad public: non-technical people who download the Windows installer and want to talk instead of type. They are not expected to know what Groq, OIDC, a WebSocket backend, or a Whisper model is. Technical users (self-hosters, people bringing their own Groq API key) exist but are not the design target.

## Product Purpose

WhisperDoc turns speech into text anywhere on the desktop. A global hotkey (default shown in-app, e.g. Ctrl+Q) starts and stops recording from any app; the transcript is copied to the clipboard and, if enabled, pasted into whatever app has focus. Optional output styles rewrite the transcript (Raw verbatim, Clean, Pro, Casual, Tech, plus user-made custom styles). Success: the user presses the hotkey, speaks, and finds correct text where their cursor was, without ever needing to look at the WhisperDoc window.

## Positioning

Two transcription routes behind one window: Groq Cloud with the user's own API key, or a self-hosted, hardened WhisperDoc backend (faster-whisper / NVIDIA Parakeet) reached over an authenticated, encrypted connection. Privacy controls (incognito mode, local-only history) are first-class.

## Operating Context

- The window is mostly hidden or in the background. People dictate via the hotkey from other apps (email, chat, documents) and rarely watch the window while speaking.
- The window is opened to: check that WhisperDoc is ready, fix a problem (no mic, no API key, sign-in failed, update required), switch output style, review or recopy a recent transcript, open history, toggle incognito, or change settings.
- Therefore the home screen is primarily a status-and-repair surface, secondarily a review surface.

## Capabilities and Constraints

- Fixed 420×600 frameless window on Windows; custom title bar with minimize/close. Size is binding.
- Modes: Groq Cloud (needs API key) or self-hosted backend (needs server URI plus API key or OIDC sign-in). Connection states include ready, connecting, deep sleep, auth failed, banned (cooldown), update required.
- Recording states: idle, recording (with live audio level), transcribing, polishing (LLM output styles), result. Silence warning if no audio is detected; microphone missing/unplugged detection with default-device fallback.
- Output styles: Raw (no LLM), Clean, Pro, Casual, Tech, plus custom styles; LLM styles require a Groq key.
- Automation toggles: auto-copy, auto-paste, show visualizer.
- Other surfaces: history (recent transcripts), debug logs, settings, profile hub/account, incognito confirmation, auth error dialog, ban countdown overlay.
- Text renders in Flutter (Skia/Impeller), not native Win32 text.

## Brand Commitments

- Name: WhisperDoc.
- Crimson (#DC143C) on near-black is the established identity and must stay.
- Lexend is the UI typeface and must stay. JetBrains Mono is already used for logs and history.

## Evidence on Hand

- Current home screen screenshot (v3.0.0) shared in conversation.
- No user research, testimonials, or usage metrics exist; do not invent them.

## Product Principles

1. Invisible by default: the best session never needs the window. The window exists to confirm readiness and to repair problems fast.
2. Plain language: never surface infrastructure jargon (WebSocket, TLS, OIDC, deep sleep) to the broad public without a plain-language lead.
3. Every blocked state names the fix: if recording is unavailable, say why and offer the one action that resolves it.
4. Privacy is visible: incognito and history behavior should be unmistakable at a glance.
5. Calm when working, loud only when something needs the user.

## Accessibility & Inclusion

No formal standard confirmed. Broad-public audience implies readable contrast and keyboard-reachable controls as a baseline.
