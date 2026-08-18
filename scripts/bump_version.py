#!/usr/bin/env python3
"""WhisperDoc Automated Version Bumper.

Safely bumps semantic versions across all WhisperDoc sub-components
(Backend, Flutter Client, Python Terminal Client, and active documentation)
while strictly preserving historical release notes and changelogs.

Usage:
    python scripts/bump_version.py patch       # e.g., 2.24.8 -> 2.24.9
    python scripts/bump_version.py minor       # e.g., 2.24.8 -> 2.25.0
    python scripts/bump_version.py major       # e.g., 2.24.8 -> 3.0.0
    python scripts/bump_version.py 2.25.0      # Explicit version target
    python scripts/bump_version.py --current   # Prints active version
    python scripts/bump_version.py patch --dry-run
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from io import TextIOWrapper
from pathlib import Path
from typing import NamedTuple

# Semantic version regex (SemVer 2.0.0)
SEMVER_REGEX = re.compile(
    r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<prerelease>[0-9A-Za-z.-]+))?"
    r"(?:\+(?P<buildmetadata>[0-9A-Za-z.-]+))?$"
)


class SemVer(NamedTuple):
    major: int
    minor: int
    patch: int
    prerelease: str | None = None
    buildmetadata: str | None = None

    @classmethod
    def parse(cls, version_str: str) -> SemVer:
        match = SEMVER_REGEX.match(version_str.strip())
        if not match:
            raise ValueError(
                f"Invalid SemVer string '{version_str}'. Must follow MAJOR.MINOR.PATCH format."
            )
        groups = match.groupdict()
        return cls(
            major=int(groups["major"]),
            minor=int(groups["minor"]),
            patch=int(groups["patch"]),
            prerelease=groups.get("prerelease"),
            buildmetadata=groups.get("buildmetadata"),
        )

    def bump(self, bump_type: str) -> SemVer:
        bump = bump_type.lower()
        if bump == "patch":
            return SemVer(self.major, self.minor, self.patch + 1)
        if bump == "minor":
            return SemVer(self.major, self.minor + 1, 0)
        if bump == "major":
            return SemVer(self.major + 1, 0, 0)
        raise ValueError(
            f"Unknown bump type: '{bump_type}'. Choose 'patch', 'minor', or 'major'."
        )

    def __str__(self) -> str:
        base = f"{self.major}.{self.minor}.{self.patch}"
        if self.prerelease:
            base += f"-{self.prerelease}"
        if self.buildmetadata:
            base += f"+{self.buildmetadata}"
        return base


class TargetRule(NamedTuple):
    path: str
    pattern: str
    replacement_template: str
    description: str


# Single source of truth targets across the repository
TARGET_MANIFEST: list[TargetRule] = [
    # --- Backend ---
    TargetRule(
        path="backend/pyproject.toml",
        pattern=r'(?m)^(version\s*=\s*")[^"]+(")',
        replacement_template=r"\g<1>{version}\g<2>",
        description="Backend pyproject.toml package version",
    ),
    TargetRule(
        path="backend/.env.template",
        pattern=r"(?m)^(WHISPER_DOC_VERSION=)[^\r\n]*",
        replacement_template=r"\g<1>{version}",
        description="Backend .env.template single source of truth version",
    ),
    # --- Flutter Client ---
    TargetRule(
        path="flutter_client/pubspec.yaml",
        pattern=r"(?m)^(version:\s*)[^\+\r\n]+(\+\d+)",
        replacement_template=r"\g<1>{version}\g<2>",
        description="Flutter pubspec.yaml version (preserves +N build number)",
    ),
    TargetRule(
        path="flutter_client/windows/installer/whisperdoc_setup.iss",
        pattern=r"(?m)^(; Version:\s*)[^\r\n]*",
        replacement_template=r"\g<1>{version}",
        description="Inno Setup script comment header",
    ),
    TargetRule(
        path="flutter_client/windows/installer/whisperdoc_setup.iss",
        pattern=r'(?m)^(#define MyAppVersion\s*")[^"]+(")',
        replacement_template=r"\g<1>{version}\g<2>",
        description="Inno Setup script MyAppVersion definition",
    ),
    TargetRule(
        path="flutter_client/test/services/utility/settings_service_test.dart",
        pattern=r"(?m)(version:\s*')[^']+(\',)",
        replacement_template=r"\g<1>{version}\g<2>",
        description="Flutter SettingsService unit test mock PackageInfo version",
    ),
    TargetRule(
        path="flutter_client/README.md",
        pattern=r"(?m)^(# WhisperDoc Flutter Client v)[^\r\n]*",
        replacement_template=r"\g<1>{version}",
        description="Flutter Client README title version",
    ),
    # --- Terminal Client ---
    TargetRule(
        path="terminal_client/pyproject.toml",
        pattern=r'(?m)^(version\s*=\s*")[^"]+(")',
        replacement_template=r"\g<1>{version}\g<2>",
        description="Terminal client pyproject.toml package version",
    ),
    TargetRule(
        path="terminal_client/.env.template",
        pattern=r"(?m)^(CLIENT_VERSION=)[^\r\n]*",
        replacement_template=r"\g<1>{version}",
        description="Terminal client .env.template version",
    ),
    TargetRule(
        path="terminal_client/whisper_shell/services/config_service.py",
        pattern=r'(?m)^(DEFAULT_VERSION\s*=\s*")[^"]+(")',
        replacement_template=r"\g<1>{version}\g<2>",
        description="Terminal client config service fallback version",
    ),
    TargetRule(
        path="terminal_client/README.md",
        pattern=r"(?m)^(# WhisperDoc Terminal Client \(v)[^\)]+(\))",
        replacement_template=r"\g<1>{version}\g<2>",
        description="Terminal Client README title version",
    ),
    # --- Root Documentation ---
    TargetRule(
        path="README.md",
        pattern=r"(?m)^(# WhisperDoc - Speech-to-Text System v)[^\r\n]*",
        replacement_template=r"\g<1>{version}",
        description="Root README main title version",
    ),
    TargetRule(
        path="README.md",
        pattern=r"(?m)^(### Flutter Client \(Windows\) v)[^\r\n]*",
        replacement_template=r"\g<1>{version}",
        description="Root README Flutter Client section header",
    ),
    TargetRule(
        path="README.md",
        pattern=r"(?m)^(### Python Terminal Client v)[^\r\n]*",
        replacement_template=r"\g<1>{version}",
        description="Root README Terminal Client section header",
    ),
]


def find_repo_root() -> Path:
    """Resolve workspace root relative to this script."""
    return Path(__file__).resolve().parent.parent


def _read_text_preserving_newlines(path: Path) -> str:
    with path.open("r", encoding="utf-8", newline="") as stream:
        return stream.read()


def _write_text_preserving_newlines(path: Path, content: str) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        stream.write(content)


def get_current_version(repo_root: Path) -> str:
    """Read the current single source of truth version from backend/pyproject.toml."""
    pyproject = repo_root / "backend" / "pyproject.toml"
    if not pyproject.exists():
        raise FileNotFoundError(
            f"Missing {pyproject}. Cannot determine current version."
        )
    content = _read_text_preserving_newlines(pyproject)
    match = re.search(r'(?m)^version\s*=\s*"([^"]+)"', content)
    if not match:
        raise ValueError('Could not find `version = "..."` in backend/pyproject.toml')
    return match.group(1)


def perform_preflight_check(repo_root: Path) -> list[tuple[TargetRule, Path, str]]:
    """Verify that all target files exist and contain their expected regex patterns."""
    valid_targets: list[tuple[TargetRule, Path, str]] = []
    for rule in TARGET_MANIFEST:
        file_path = repo_root / rule.path
        if not file_path.exists():
            raise FileNotFoundError(
                f"Target file not found: {rule.path} ({rule.description})"
            )
        content = _read_text_preserving_newlines(file_path)
        if not re.search(rule.pattern, content):
            raise ValueError(
                f"Pattern mismatch in {rule.path} for: {rule.description}\n"
                f"Pattern: {rule.pattern}"
            )
        valid_targets.append((rule, file_path, content))
    return valid_targets


def bump_manifest(
    repo_root: Path,
    next_version: str,
    dry_run: bool = False,
) -> None:
    """Atomically update all files in TARGET_MANIFEST."""
    validated = perform_preflight_check(repo_root)

    print(
        f"\n🚀 {'[DRY RUN] ' if dry_run else ''}Bumping repository to v{next_version}:\n"
    )
    updated_contents: dict[Path, str] = {}
    for rule, file_path, original_content in validated:
        current_content = updated_contents.get(file_path, original_content)
        replacement = rule.replacement_template.format(version=next_version)
        new_content = re.sub(rule.pattern, replacement, current_content)

        if new_content == current_content:
            print(f"  ⚪ {rule.path}: Already up to date ({rule.description})")
            continue

        updated_contents[file_path] = new_content
        print(f"  🟢 {rule.path}: Updated ({rule.description})")

    if not dry_run:
        for file_path, content in updated_contents.items():
            _write_text_preserving_newlines(file_path, content)


def sync_lockfiles(repo_root: Path, dry_run: bool = False) -> None:
    """Run `uv lock` in Python packages to synchronize lockfiles."""
    if not shutil.which("uv"):
        if dry_run:
            print("\n⚠️  `uv` command not found on PATH. Lockfile sync unavailable.")
            return
        raise RuntimeError(
            "`uv` command not found on PATH. Install uv or pass --skip-lock explicitly."
        )

    python_dirs = ["backend", "terminal_client"]
    print(
        f"\n📦 {'[DRY RUN] ' if dry_run else ''}Synchronizing lockfiles with `uv lock`:"
    )

    failures: list[str] = []
    for pkg_dir in python_dirs:
        target_dir = repo_root / pkg_dir
        if not target_dir.exists():
            continue
        print(f"  ⚙️  Running `uv lock` in {pkg_dir}/...")
        if not dry_run:
            result = subprocess.run(
                ["uv", "lock"],
                cwd=target_dir,
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                print(f"    ❌ `uv lock` failed in {pkg_dir}:\n{result.stderr}")
                failures.append(pkg_dir)
            else:
                print(f"    ✅ {pkg_dir}/uv.lock synchronized.")

    if failures:
        raise RuntimeError(
            f"Lockfile synchronization failed for: {', '.join(failures)}."
        )


def main(argv: list[str] | None = None) -> int:
    # Preserve emoji output on the Windows console without mutating streams when
    # this module is imported by tests or other tooling.
    if sys.platform == "win32":
        if isinstance(sys.stdout, TextIOWrapper):
            sys.stdout.reconfigure(encoding="utf-8")
        if isinstance(sys.stderr, TextIOWrapper):
            sys.stderr.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(
        description="Automated SemVer bumper for WhisperDoc multi-component repository."
    )
    parser.add_argument(
        "target",
        nargs="?",
        help="Bump type ('patch', 'minor', 'major') or explicit target version (e.g. '2.25.0').",
    )
    parser.add_argument(
        "--current",
        action="store_true",
        help="Print the current repository version and exit.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate the version bump and show changes without modifying files on disk.",
    )
    parser.add_argument(
        "--skip-lock",
        action="store_true",
        help="Skip running `uv lock` synchronization after updating manifests.",
    )

    args = parser.parse_args(argv)
    repo_root = find_repo_root()

    try:
        current_version_str = get_current_version(repo_root)
    except Exception as e:
        print(f"❌ Error resolving current version: {e}", file=sys.stderr)
        return 1

    if args.current:
        print(f"WhisperDoc current version: {current_version_str}")
        return 0

    if not args.target:
        parser.print_help()
        print(f"\nCurrent version: {current_version_str}")
        return 1

    # Calculate next version
    target_arg = args.target.strip()
    try:
        if target_arg.lower() in {"patch", "minor", "major"}:
            current_semver = SemVer.parse(current_version_str)
            next_semver = current_semver.bump(target_arg)
            next_version_str = str(next_semver)
        else:
            # Explicit version provided; validate SemVer format
            explicit_semver = SemVer.parse(target_arg)
            next_version_str = str(explicit_semver)
    except ValueError as e:
        print(f"❌ Version calculation error: {e}", file=sys.stderr)
        return 1

    print(f"Bumping version: {current_version_str} -> {next_version_str}")

    try:
        bump_manifest(repo_root, next_version_str, dry_run=args.dry_run)
    except Exception as e:
        print(f"\n❌ Pre-flight or update error: {e}", file=sys.stderr)
        return 1

    if not args.skip_lock:
        try:
            sync_lockfiles(repo_root, dry_run=args.dry_run)
        except RuntimeError as e:
            print(f"\n❌ Lockfile synchronization error: {e}", file=sys.stderr)
            return 1

    print(f"\n✨ Version bump to v{next_version_str} completed successfully!\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
