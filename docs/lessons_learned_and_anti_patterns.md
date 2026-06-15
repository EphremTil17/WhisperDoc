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
