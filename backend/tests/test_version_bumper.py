"""Unit test suite for the scripts/bump_version.py automation tool."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

# Add repo root to sys.path to import scripts.bump_version directly
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

import scripts.bump_version as bump_version  # noqa: E402
from scripts.bump_version import (  # noqa: E402
    SEMVER_REGEX,
    TARGET_MANIFEST,
    SemVer,
    find_repo_root,
    get_current_version,
    perform_preflight_check,
)


def test_semver_parsing_valid():
    """Verify parsing valid SemVer strings."""
    v = SemVer.parse("2.24.8")
    assert v.major == 2
    assert v.minor == 24
    assert v.patch == 8
    assert v.prerelease is None
    assert str(v) == "2.24.8"

    v_pre = SemVer.parse("3.0.0-rc.1+build.123")
    assert v_pre.major == 3
    assert v_pre.prerelease == "rc.1"
    assert v_pre.buildmetadata == "build.123"
    assert str(v_pre) == "3.0.0-rc.1+build.123"


def test_semver_parsing_invalid():
    """Verify rejecting malformed SemVer strings."""
    with pytest.raises(ValueError, match="Invalid SemVer string"):
        SemVer.parse("v2.24")

    with pytest.raises(ValueError, match="Invalid SemVer string"):
        SemVer.parse("invalid.semver")


def test_semver_bumping():
    """Verify SemVer bump calculation logic."""
    base = SemVer.parse("2.24.8")

    assert str(base.bump("patch")) == "2.24.9"
    assert str(base.bump("minor")) == "2.25.0"
    assert str(base.bump("major")) == "3.0.0"

    with pytest.raises(ValueError, match="Unknown bump type"):
        base.bump("hotfix")


def test_get_current_version():
    """Verify resolving the active version from backend/pyproject.toml."""
    root = find_repo_root()
    ver = get_current_version(root)
    assert SEMVER_REGEX.match(ver) is not None


def test_perform_preflight_check_against_workspace():
    """Verify that all manifest targets exist and match their expected regex patterns."""
    root = find_repo_root()
    validated = perform_preflight_check(root)
    assert len(validated) == len(TARGET_MANIFEST)

    for rule, file_path, content in validated:
        assert file_path.exists()
        assert len(content) > 0


def test_bump_manifest_accumulates_rules_and_preserves_crlf(
    tmp_path, monkeypatch
):
    target = tmp_path / "version.txt"
    target.write_bytes(b"Product: 1.0.0\r\nClient: 1.0.0\r\n")
    rules = [
        bump_version.TargetRule(
            path="version.txt",
            pattern=r"(?m)^(Product: )[^\r\n]*",
            replacement_template=r"\g<1>{version}",
            description="product version",
        ),
        bump_version.TargetRule(
            path="version.txt",
            pattern=r"(?m)^(Client: )[^\r\n]*",
            replacement_template=r"\g<1>{version}",
            description="client version",
        ),
    ]
    monkeypatch.setattr(bump_version, "TARGET_MANIFEST", rules)

    bump_version.bump_manifest(tmp_path, "2.25.2")

    assert target.read_bytes() == b"Product: 2.25.2\r\nClient: 2.25.2\r\n"


def test_sync_lockfiles_reports_uv_failures(tmp_path, monkeypatch):
    (tmp_path / "backend").mkdir()
    monkeypatch.setattr(bump_version.shutil, "which", lambda _: "/usr/bin/uv")
    failed = bump_version.subprocess.CompletedProcess(
        args=["uv", "lock"],
        returncode=1,
        stdout="",
        stderr="resolution failed",
    )
    monkeypatch.setattr(bump_version.subprocess, "run", lambda *args, **kwargs: failed)

    with pytest.raises(RuntimeError, match="backend"):
        bump_version.sync_lockfiles(tmp_path)
