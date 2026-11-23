#!/usr/bin/env bash
# SonarQube analysis of WhisperDoc. Runs inside WSL (Linux) from a checkout of
# the commit to scan. Normally started by scripts/sonar/scan.ps1 on Windows,
# which first writes the Flutter inputs that need the Windows Flutter SDK:
#   flutter_client/coverage/lcov.info          (flutter test --coverage)
#   flutter_client/coverage/dart-analyzer.txt  (dart analyze --format=machine)
#
# Machine-local settings (server URL, token) live in the git-ignored
# sonar-project.properties at the repo root; scripts/sonar/README.md shows the
# template. Each top-level app is its own module, so every report resolves
# against its own folder and no path rewriting or Flutter shim is needed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROPS="$ROOT/sonar-project.properties"
REPORTS="$ROOT/.sonar-reports"
FLUTTER_COVERAGE="$ROOT/flutter_client/coverage"
SCANNER_IMAGE="sonarsource/sonar-scanner-cli:${SONAR_SCANNER_VERSION:-latest}"

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

prop() { sed -n "s/^$1=//p" "$PROPS" | tr -d '[:space:]'; }

[[ -f "$PROPS" ]] || fail "missing $PROPS: create it from scripts/sonar/README.md"
SONAR_URL="$(prop sonar.host.url)"
SONAR_TOKEN="$(prop sonar.token)"
[[ -n "$SONAR_URL" && "$SONAR_URL" != "<"* ]] || fail "set sonar.host.url in $PROPS"
[[ -n "$SONAR_TOKEN" && "$SONAR_TOKEN" != "<"* ]] || fail "set sonar.token in $PROPS"
[[ -f "$FLUTTER_COVERAGE/lcov.info" ]] || fail "no Flutter coverage: run scripts/sonar/scan.ps1 on Windows"
[[ -f "$FLUTTER_COVERAGE/dart-analyzer.txt" ]] || fail "no Dart analyzer report: run scripts/sonar/scan.ps1 on Windows"

# Each release is its own version, so with the "previous version" New Code
# rule, new code means the changes since the last release.
VERSION="$(python3 "$ROOT/scripts/bump_version.py" --current | awk '{print $NF}')"
[[ -n "$VERSION" ]] || fail "could not read the version from scripts/bump_version.py"
echo "--- SonarQube scan of WhisperDoc $VERSION ($(git -C "$ROOT" rev-parse --short HEAD)) ---"

mkdir -p "$REPORTS"

# 1. Python coverage, each suite in its own locked environment. A failing test
# still leaves valid coverage, so it warns instead of stopping the scan.
python_coverage() {
  local app="$1"
  echo "Coverage: $app"
  (
    cd "$ROOT/$app"
    uv sync --frozen --quiet
    uv run --no-sync pytest -q -p no:cacheprovider \
      --cov=. --cov-report="xml:$REPORTS/$app-coverage.xml" \
      | tail -n 1
  ) || echo "WARNING: $app tests failed; its coverage is still reported" >&2
  [[ -f "$REPORTS/$app-coverage.xml" ]] || fail "no coverage report for $app"
}
python_coverage backend

# The terminal client is a Windows app: several of its tests need Windows, so
# scan.ps1 measures it there and passes the report in. Run on its own, this
# script measures it here and says the numbers are partial.
if [[ -n "${TERMINAL_COVERAGE:-}" ]]; then
  cp "$TERMINAL_COVERAGE" "$REPORTS/terminal_client-coverage.xml"
else
  echo "NOTE: terminal_client measured in WSL; Windows-only tests fail here, so its coverage is partial" >&2
  python_coverage terminal_client
fi

# Coverage.py records where it ran (a WSL or Windows path); point each report
# at its module's folder inside the scanner container instead.
for app in backend terminal_client; do
  sed -i -E "s#<source>[^<]*</source>#<source>/usr/src/$app</source>#" \
    "$REPORTS/$app-coverage.xml"
done

# 2. Flutter writes Windows paths (lib\x.dart); the analyzer report may hold
# absolute ones. Both become paths relative to flutter_client, with slashes.
python3 - "$FLUTTER_COVERAGE" "$REPORTS" <<'PY'
import sys
from pathlib import Path, PurePosixPath

coverage, reports = map(Path, sys.argv[1:])


def relative(path: str) -> str:
    parts = PurePosixPath(path.strip().replace("\\", "/")).parts
    if "flutter_client" in parts:
        parts = parts[parts.index("flutter_client") + 1 :]
    return PurePosixPath(*parts).as_posix()


# In place: sonar-flutter reads coverage/lcov.info under its module, and the
# rewrite is idempotent, so a second scan of the same report changes nothing.
lcov = coverage / "lcov.info"
lines = lcov.read_text(encoding="utf-8").splitlines()
lcov.write_text(
    "".join(
        (f"SF:{relative(line[3:])}" if line.startswith("SF:") else line) + "\n"
        for line in lines
    ),
    encoding="utf-8",
    newline="\n",
)

# Machine format: SEVERITY|TYPE|CODE|FILE|LINE|COLUMN|LENGTH|MESSAGE
with open(coverage / "dart-analyzer.txt", encoding="utf-8-sig") as src, open(
    reports / "dart-analyzer.txt", "w", encoding="utf-8", newline="\n"
) as dst:
    for line in src:
        fields = line.rstrip("\r\n").split("|")
        if len(fields) >= 8:  # skips summaries such as "No issues found!"
            fields[3] = relative(fields[3])
            dst.write("|".join(fields) + "\n")
PY

# 3. Scan. Source paths below are relative to each module's folder; report
# paths are absolute inside the container, where the repo is /usr/src.
python_module() {
  local app="$1"
  echo "-D$app.sonar.sources=."
  echo "-D$app.sonar.tests=tests"
  echo "-D$app.sonar.exclusions=tests/**,**/__pycache__/**,.venv/**,.pytest_cache/**,conftest.py"
  # Absolute (inside the container): the Python sensor won't follow ../ out
  # of its module.
  echo "-D$app.sonar.python.coverage.reportPaths=/usr/src/.sonar-reports/$app-coverage.xml"
}

mapfile -t MODULE_ARGS < <(python_module backend; python_module terminal_client)
SCANNER_ARGS=(
  "-Dsonar.projectKey=WhisperDoc"
  "-Dsonar.projectName=WhisperDoc"
  "-Dsonar.projectVersion=$VERSION"
  "-Dsonar.host.url=$SONAR_URL"
  "-Dsonar.sourceEncoding=UTF-8"
  "-Dsonar.python.version=3.12"
  "-Dsonar.modules=backend,terminal_client,flutter_client"
  "${MODULE_ARGS[@]}"
  "-Dflutter_client.sonar.sources=lib"
  "-Dflutter_client.sonar.tests=test"
  "-Dflutter_client.sonar.exclusions=**/*.g.dart"
  "-Dflutter_client.sonar.coverage.exclusions=**/*.g.dart"
  # sonar-flutter reads coverage/lcov.info under its module; MANUAL mode reads
  # the analyzer report instead of running Flutter, which the image lacks.
  "-Dflutter_client.sonar.dart.analyzer.mode=MANUAL"
  "-Dflutter_client.sonar.dart.analyzer.report.mode=MACHINE"
  "-Dflutter_client.sonar.dart.analyzer.report.path=/usr/src/.sonar-reports/dart-analyzer.txt"
)

# The token goes in through the environment, never on a command line.
export SONAR_TOKEN
docker run --rm --network host -e SONAR_TOKEN -v "$ROOT:/usr/src" \
  "$SCANNER_IMAGE" "${SCANNER_ARGS[@]}"

echo -e "\nScan complete: $SONAR_URL/dashboard?id=WhisperDoc"
