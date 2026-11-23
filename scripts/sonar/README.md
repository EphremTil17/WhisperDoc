# SonarQube scans

WhisperDoc is analysed by a local SonarQube (Community Build, Docker container
`sonarqube` in WSL, http://localhost:9000) with the sonar-flutter plugin. Each
app is a module (`backend`, `terminal_client`, `flutter_client`), so every
report resolves against its own folder.

## Run a scan

From Windows, on a committed state:

```powershell
.\scripts\sonar\scan.ps1
```

It brings the WSL checkout (`~/projects/WhisperDoc`) to the same commit,
measures what needs Windows (Flutter coverage, the Dart analyzer report, the
terminal client's coverage), then runs `scan.sh` in WSL, which adds the
backend's coverage and runs the scanner. The scan reports the release version
from `scripts/bump_version.py`, so "new code" is the change since the last
release.

`scan.sh` also runs on its own inside WSL once the Flutter reports exist; it
then measures the terminal client in WSL, where its Windows-only tests fail,
and says the numbers are partial.

## One-time setup

**WSL packages:** Docker, `uv`, Python 3, and `libportaudio2` (terminal client
audio tests).

**`sonar-project.properties`** at the root of the WSL checkout, git-ignored,
`chmod 600`. It is the single place for machine-local settings; the scripts and
the MCP read it, and the analysis itself is defined in `scan.sh`:

```properties
sonar.host.url=http://localhost:9000
# A user token (My Account > Security): it scans and can read results.
sonar.token=<SONARQUBE_USER_TOKEN>
```

**SonarQube MCP for Claude Code (optional):** `~/.local/bin/sonarqube-mcp` in
WSL starts the `mcp/sonarqube` container with the token from that file.
Register it once from the repo on Windows:

```powershell
claude mcp add --scope local sonarqube-wsl -- wsl.exe -e /home/<user>/.local/bin/sonarqube-mcp
```

```bash
#!/usr/bin/env bash
set -euo pipefail
props="${SONAR_PROPERTIES:-$HOME/projects/WhisperDoc/sonar-project.properties}"
SONARQUBE_TOKEN="$(sed -n 's/^sonar.token=//p' "$props" | tr -d '[:space:]')"
export SONARQUBE_TOKEN
exec docker run -i --rm --network host \
  -e SONARQUBE_TOKEN -e SONARQUBE_URL=http://localhost:9000 mcp/sonarqube
```

## Why it is built this way

- **Flutter runs on Windows, the scanner in WSL.** The scanner image has no
  Flutter, so sonar-flutter reads a `dart analyze --format=machine` report
  (`MANUAL` mode) instead of running the analyzer itself.
- **Report paths.** Flutter writes `lib\...` paths and coverage.py records the
  folder it ran in; `scan.sh` rewrites both to what the scanner container sees
  (`/usr/src/<module>`).
