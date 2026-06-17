# WhisperDoc Living Ledger: Lessons Learned and Anti-Patterns

## 🎙️ Audio Availability & Hardware Subsystem

### 1. Make Illegal States Unrepresentable
* **The Mistake**: Using a simple binary boolean `hasAudioInput` to track audio availability. This collapsed multiple distinct states ("no device," "selected device unplugged," "permission denied," and "not yet checked") into one bit, causing recovery failure, incorrect UI banners, and unhandled exceptions.
* **The Root Cause**: Attempting to model a complex state machine using binary flags.
* **The Corrective Rule**: Always model hardware states with a rich, typed domain representation (e.g., `AudioInputStatus` enum with states like `available`, `noDevice`, `permissionDenied`, etc.). 

### 2. Context-Blind Services
* **The Mistake**: Hardcoding Flutter bindings, lifecycle observers, or UI status overrides (`_audioService.updateHardwareInputStatus(false)`) inside low-level Services or Controllers.
* **The Root Cause**: Layering inversion where services assumed knowledge of application/UI lifecycle state.
* **The Corrective Rule**: Keep core services blind to Flutter context and widgets. UI lifecycle observers (e.g., `WidgetsBindingObserver`) belong strictly in the UI/Orchestration layer, which calls passive evaluation endpoints on the services.

### 3. Adaptive Degraded Monitors
* **The Mistake**: Demanding that the user manually trigger re-detection or restarting the app when audio permissions were granted or microdevices plugged back in.
* **The Root Cause**: Lack of automated recovery polling during degraded states.
* **The Corrective Rule**: Implement a low-overhead, self-managed adaptive polling timer (e.g., polling every 3 seconds) that runs *only* while the system is in a degraded/unavailable state, and automatically halts once status recovers to `available`.

---

## 💻 PowerShell Escape Rules in Git Commits

### 1. PowerShell Escape Sequences
* **The Mistake**: Using double quotes and backticks for inline code block format inside commit messages in PowerShell (e.g., ``- `backend/pyproject.toml` ``). PowerShell interpreted these backticks as escape chars (e.g., `` `b `` became backspace, `` `t `` became tab, `` `f `` became form feed), causing corrupted commit history formatting.
* **The Root Cause**: In PowerShell, the backtick `` ` `` is the escape character.
* **The Corrective Rule**: Always wrap multi-line commit messages containing code formatting in literal single quotes (`'`) when committing via PowerShell to prevent string expansion and escape sequence evaluation.

---

## 🔒 Security & Dependency Lifecycle Management

### 1. Cryptographic/JWT Library Hygiene
* **The Mistake**: Relying on unmaintained legacy wrappers like `python-jose` which drag in unpatched transitive dependencies (e.g. `ecdsa` carrying timing attack CVEs).
* **The Root Cause**: Failing to audit the transitive tree when choosing a library, leading to unresolvable security flags.
* **The Corrective Rule**: Prefer clean, standard-focused, and actively maintained libraries (e.g., `PyJWT`) that verify claims and signatures securely with minimal transitive footprint, bypassing legacy wrap-dependency baggage.

### 2. Transitive Dependency Remediation via Floor Constraints
* **The Mistake**: Blindly overriding parent package ceilings or bumping parent package definitions to remediate a deep transitive CVE, which forces package resolver fights or breaks tight compatibility bounds of heavy ML stacks like `nemo_toolkit`.
* **The Root Cause**: Attempting to force-upgrade parent versions instead of targeting the specific leaf vulnerability directly.
* **The Corrective Rule**: Always use `tool.uv.constraint-dependencies` to establish floor constraints (e.g., `cryptography>=48.0.1`) for transitive vulnerabilities. This guarantees a safe minimum floor version is locked while leaving the ceiling unbound, keeping third-party ML pipelines compatible.

