#!/usr/bin/env python3
"""Provision a digest-verified Parakeet GGUF model for parakeet.cpp.

Model downloads are deliberately kept out of application startup. Run this
tool during deployment, then mount the resulting directory read-only into the
native sidecar.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
import urllib.request
from pathlib import Path
from typing import Any, BinaryIO, cast

CHUNK_SIZE = 1024 * 1024
DEFAULT_MANIFEST = Path(__file__).parents[1] / "engine" / "parakeet_manifest.json"
DEFAULT_DESTINATION = Path(__file__).parents[2] / "model-cache" / "parakeet"


def _load_manifest(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as manifest_file:
        manifest = json.load(manifest_file)
    if manifest.get("schema_version") != 1:
        raise ValueError("Unsupported parakeet.cpp manifest schema.")
    return manifest


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as model_file:
        while chunk := model_file.read(CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest()


def _stream_to_file(source: BinaryIO, destination: BinaryIO) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    while chunk := source.read(CHUNK_SIZE):
        destination.write(chunk)
        digest.update(chunk)
        size += len(chunk)
    return size, digest.hexdigest()


def provision(
    *,
    manifest_path: Path = DEFAULT_MANIFEST,
    destination: Path = DEFAULT_DESTINATION,
    variant: str | None = None,
) -> Path:
    """Download and atomically install one verified model variant."""

    manifest = _load_manifest(manifest_path)
    selected = variant or manifest["selected_variant"]
    try:
        model = manifest["models"][selected]
    except KeyError as error:
        choices = ", ".join(sorted(manifest.get("models", {})))
        raise ValueError(
            f"Unknown model variant '{selected}'. Choose: {choices}."
        ) from error

    filename = str(model["filename"])
    if Path(filename).name != filename:
        raise ValueError("Manifest model filename must not contain a path.")

    expected_size = int(model["size_bytes"])
    expected_sha256 = str(model["sha256"]).lower()
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / filename

    if target.is_file() and target.stat().st_size == expected_size:
        if _sha256(target) == expected_sha256:
            print(f"Model already verified: {target}")
            return target

    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w+b",
            prefix=f".{filename}.",
            suffix=".part",
            dir=destination,
            delete=False,
        ) as temporary_file:
            temporary_path = Path(temporary_file.name)
            request = urllib.request.Request(
                str(model["url"]),
                headers={"User-Agent": "WhisperDoc-parakeet.cpp-provisioner/1"},
            )
            with urllib.request.urlopen(request, timeout=60) as response:
                actual_size, actual_sha256 = _stream_to_file(
                    response, cast(BinaryIO, temporary_file)
                )
            temporary_file.flush()
            os.fsync(temporary_file.fileno())

        if actual_size != expected_size:
            raise ValueError(
                f"Model size mismatch: expected {expected_size}, received {actual_size}."
            )
        if actual_sha256 != expected_sha256:
            raise ValueError(
                f"Model SHA-256 mismatch: expected {expected_sha256}, received {actual_sha256}."
            )

        os.replace(temporary_path, target)
        temporary_path = None
        print(f"Provisioned verified model: {target}")
        return target
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--destination", type=Path, default=DEFAULT_DESTINATION)
    parser.add_argument(
        "--variant", help="Model variant from the manifest (default: selected_variant)"
    )
    arguments = parser.parse_args()
    provision(
        manifest_path=arguments.manifest,
        destination=arguments.destination,
        variant=arguments.variant,
    )


if __name__ == "__main__":
    main()
