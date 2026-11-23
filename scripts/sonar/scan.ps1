<#
.SYNOPSIS
SonarQube analysis of WhisperDoc's current commit, in one command from Windows.

.DESCRIPTION
1. Brings the WSL checkout to the same commit (fast-forward only).
2. Measures what needs Windows: Flutter coverage and the Dart analyzer report
   (the Flutter SDK lives here) and the terminal client's coverage (it is a
   Windows app; several of its tests need Windows).
3. Runs scripts/sonar/scan.sh in WSL, which adds the backend's coverage and
   runs the scanner.

The token is read in WSL from the git-ignored sonar-project.properties; see
scripts/sonar/README.md.

.PARAMETER WslRepo
The WSL checkout to scan from.

.PARAMETER AllowDirty
Scan even if flutter_client or terminal_client have uncommitted changes. Their
coverage then describes the working tree, not the scanned commit.
#>
param(
    [string]$WslRepo = '~/projects/WhisperDoc',
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Invoke-Wsl([string]$command) {
    wsl.exe -e bash -lc $command
    if ($LASTEXITCODE -ne 0) { throw "WSL command failed ($LASTEXITCODE): $command" }
}

function ConvertTo-WslPath([string]$windowsPath) {
    (wsl.exe -e wslpath -a ($windowsPath -replace '\\', '/')).Trim()
}

# Measured on Windows from the working tree, so it must match the commit.
$dirty = git -C $root status --porcelain -- flutter_client terminal_client
if ($dirty -and -not $AllowDirty) {
    throw "flutter_client or terminal_client has uncommitted changes; commit them, or pass -AllowDirty."
}

$branch = git -C $root rev-parse --abbrev-ref HEAD
$commit = git -C $root rev-parse HEAD
$rootWsl = ConvertTo-WslPath $root
Write-Host "--- Scanning $branch at $($commit.Substring(0, 7)) ---"

# 1. The WSL checkout follows this one: fetch the commit and fast-forward its
#    branch. It refuses rather than drop WSL-only commits or changes.
Invoke-Wsl @"
set -euo pipefail
cd $WslRepo
[[ -z "`$(git status --porcelain)" ]] || { echo 'WSL checkout has uncommitted changes (wdsync or stash them first)' >&2; exit 1; }
git fetch -q '$rootWsl' '$branch'
# Moving the branch is safe when every commit it would leave behind exists in
# the Windows repo too, e.g. after commits were amended or folded there.
if git rev-parse -q --verify 'refs/heads/$branch' >/dev/null; then
  for sha in `$(git rev-list FETCH_HEAD..'$branch'); do
    git --git-dir='$rootWsl/.git' cat-file -e "`$sha^{commit}" 2>/dev/null ||
      { echo "WSL branch $branch has commit `$sha that Windows lacks" >&2; exit 1; }
  done
fi
git switch -q -C '$branch' FETCH_HEAD
echo "WSL checkout at `$(git rev-parse --short HEAD) on $branch"
"@

# 2. What needs Windows.
Push-Location (Join-Path $root 'flutter_client')
try {
    Write-Host 'Coverage: flutter_client'
    flutter test --coverage | Select-Object -Last 1
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Flutter tests failed; their coverage is still reported.' }
    # The analyzer writes diagnostics to stderr and exits non-zero when it
    # finds issues; both are fine here, the report is what matters.
    cmd /c 'dart analyze --format=machine > coverage\dart-analyzer.txt 2>&1'
} finally { Pop-Location }

Push-Location (Join-Path $root 'terminal_client')
try {
    Write-Host 'Coverage: terminal_client'
    uv run --no-sync pytest -q -p no:cacheprovider --cov=. --cov-report=xml:coverage.xml | Select-Object -Last 1
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Terminal client tests failed; their coverage is still reported.' }
} finally { Pop-Location }

# 3. Hand the reports to WSL and scan there.
Invoke-Wsl @"
set -euo pipefail
cd $WslRepo
mkdir -p flutter_client/coverage
cp '$rootWsl/flutter_client/coverage/lcov.info' '$rootWsl/flutter_client/coverage/dart-analyzer.txt' flutter_client/coverage/
TERMINAL_COVERAGE='$rootWsl/terminal_client/coverage.xml' bash scripts/sonar/scan.sh
"@
