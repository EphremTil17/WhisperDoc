"""Tests for digest-verified Parakeet model provisioning."""

from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
from unittest.mock import patch

import pytest

from tools.provision_parakeet import provision


def _manifest(path: Path, payload: bytes, *, variant: str = "f16") -> Path:
    manifest = {
        "schema_version": 1,
        "selected_variant": variant,
        "models": {
            "f16": {
                "filename": "model.gguf",
                "url": "https://models.invalid/model.gguf",
                "size_bytes": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            }
        },
    }
    path.write_text(json.dumps(manifest), encoding="utf-8")
    return path


def test_provision_downloads_verifies_and_atomically_installs(tmp_path):
    payload = b"verified-gguf-payload"
    manifest = _manifest(tmp_path / "manifest.json", payload)
    destination = tmp_path / "models"

    with patch(
        "tools.provision_parakeet.urllib.request.urlopen",
        return_value=io.BytesIO(payload),
    ) as urlopen:
        result = provision(manifest_path=manifest, destination=destination)

    assert result.read_bytes() == payload
    assert list(destination.glob("*.part")) == []
    urlopen.assert_called_once()


def test_provision_reuses_an_existing_verified_model(tmp_path):
    payload = b"verified-gguf-payload"
    manifest = _manifest(tmp_path / "manifest.json", payload)
    destination = tmp_path / "models"
    destination.mkdir()
    (destination / "model.gguf").write_bytes(payload)

    with patch("tools.provision_parakeet.urllib.request.urlopen") as urlopen:
        result = provision(manifest_path=manifest, destination=destination)

    assert result == destination / "model.gguf"
    urlopen.assert_not_called()


@pytest.mark.parametrize("corruption", [b"wrong-size", b"verified-gguf-payloX"])
def test_provision_rejects_corrupted_download_and_cleans_partial_file(
    tmp_path, corruption
):
    expected = b"verified-gguf-payload"
    manifest = _manifest(tmp_path / "manifest.json", expected)
    destination = tmp_path / "models"

    with (
        patch(
            "tools.provision_parakeet.urllib.request.urlopen",
            return_value=io.BytesIO(corruption),
        ),
        pytest.raises(ValueError, match="mismatch"),
    ):
        provision(manifest_path=manifest, destination=destination)

    assert not (destination / "model.gguf").exists()
    assert list(destination.glob("*.part")) == []


def test_provision_rejects_unknown_variant(tmp_path):
    manifest = _manifest(tmp_path / "manifest.json", b"model")

    with pytest.raises(ValueError, match="Unknown model variant"):
        provision(
            manifest_path=manifest,
            destination=tmp_path / "models",
            variant="q4_k",
        )
