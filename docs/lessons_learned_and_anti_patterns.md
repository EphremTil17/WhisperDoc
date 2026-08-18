# WhisperDoc Lessons Learned & Architectural Anti-Patterns

This document serves as the project's living ledger of architectural corrections, operational lessons learned, and forbidden anti-patterns. In accordance with project engineering rules, this document must be consulted at the start of every engineering session to ensure past design failures and regressions are never reintroduced.

---

## 1. Process Isolation vs. In-Process Heavy C/CUDA Libraries

- **The Mistake / Issue**: Embedding NVIDIA NeMo (`nemo_toolkit[asr]`) and its extensive C++/CUDA dependency graph directly into the Python `FastAPI` / `uvicorn` asyncio event loop.
- **The Root Cause**: A severe, non-deterministic CPython memory corruption bug occurred where a native C/CUDA extension mutated CPython's interned `b" "` (ASCII space `0x20`) singleton to `0x00` in memory. This corrupted `h11` HTTP header parsing, caused socket upgrade failures, and pulled over 12 GB of bloated dependencies into the backend container.
- **The Core Corrective Rule**: Never host complex, native C++/CUDA inference engines in-process alongside web services. Isolate heavy ML workloads behind a standalone sidecar process (e.g., native C++ `parakeet.cpp` container) communicating over lightweight HTTP/IPC.

---

## 2. Zero-Shim & Anti-Monkey-Patching Policy

- **The Mistake / Issue**: Introducing monkey-patches (`_fixed_ws_upgrade` and `_SAFE_SPACE` byte patches) inside `backend/api_server.py` to paper over `h11` protocol failures caused by memory corruption.
- **The Root Cause**: Attempting to fix downstream symptoms of underlying memory corruption rather than resolving the architectural root cause.
- **The Core Corrective Rule**: Zero silent patches. Never introduce runtime shims, monkey-patches, or compatibility layers to mask deeper structural bugs. If a foundational dependency or design pattern fails, isolate or refactor the architecture at its root.

---

## 3. Cross-Environment Windows/WSL Synchronization

- **The Mistake / Issue**: Manually copying files or using ad-hoc file transfers between Windows workspace filesystems and WSL Linux environments.
- **The Root Cause**: File permission discrepancies (e.g., execution bit loss on shell scripts), line ending mutations (CRLF vs. LF), and orphaned mirror files leading to state desynchronization and dirty git working trees.
- **The Core Corrective Rule**: Never perform manual file copies between Windows and WSL. Exclusively use `wdsync send` / `wdsync receive` or formal Git operations (`git fetch` / `git reset --hard`) to maintain synchronized environments.

---

## 4. Multi-Platform Line Ending Drift in Automation Tooling

- **The Mistake / Issue**: Regex-based text replacements in `scripts/bump_version.py` failing on Windows files formatted with CRLF (`\r\n`), and Python file writers converting LF to CRLF unexpectedly.
- **The Root Cause**: Using string `$`, `\n`, or default `open(..., "w")` without preserving exact newline semantics, causing silent regex mismatch or git diff churn.
- **The Core Corrective Rule**: All repository-level automation scripts touching files must use `newline=""` when reading and writing text (`_read_text_preserving_newlines()` / `_write_text_preserving_newlines()`), and multiline regexes must match non-newline characters explicitly (e.g., `[^\r\n]*`) instead of relying on `$` or `.*`.

---

## 5. Three-Tier Narrative Commit Standard

- **The Mistake / Issue**: Authoring generic, single-line, or vague commit messages lacking context, motivation, or detailed impact.
- **The Root Cause**: Omitting structured documentation standards during rapid development.
- **The Core Corrective Rule**: Every git commit must adhere to the three-tier narrative commit format:
  1. **Executive Summary Header**: `<type>(<scope>): <summary>` using 2 to 4 complete sentences stating both what changed and why/result.
  2. **Technical Narrative**: 1 to 2 paragraphs of prose (each at least 3 complete sentences) detailing architectural rationale, trade-offs, and system impacts.
  3. **Categorized Component Breakdown**: Explicit file paths grouped under domain headers (`**Backend**`, `**Frontend**`, `**Tooling**`, `**Infrastructure**`, `**Docs**`, `**Tests**`).

---

## 6. Windows Desktop Release Compilation Flags

- **The Mistake / Issue**: Compiling Flutter Windows release binaries without debug symbol separation or runtime configuration definitions.
- **The Root Cause**: Standard `flutter build windows --release` produces monolithic executables with unmapped crash traces and missing OIDC enclave credentials.
- **The Core Corrective Rule**: Windows release builds must always specify obfuscation, split debug symbol output, and explicit environment injection:
  ```powershell
  flutter build windows --release --build-name=<version> --build-number=<num> --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env.json
  ```

---

## 7. Decoupled Architecture & Context-Blind Services

- **The Mistake / Issue**: Embedding UI lifecycle observers (`WidgetsBindingObserver`) or Flutter widget dependencies inside low-level services like `AudioService`.
- **The Root Cause**: Conflating UI state orchestration with hardware interface management, creating cyclic dependencies and making services difficult to unit-test.
- **The Core Corrective Rule**: Adhere strictly to the five horizontal layers (Infrastructure -> Services -> Logic -> Controllers -> UI). Services must remain 100% context-blind. UI lifecycle and presentation logic belong strictly in UI widgets and Controllers.
