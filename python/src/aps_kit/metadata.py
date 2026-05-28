"""Generator metadata helpers. Mirrors specs/acceptance-generator.md."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

SCHEMA_VERSION = 1
NON_ALNUM = re.compile(r"[^a-z0-9]+")


def metadata_filename(feature_path: str) -> str:
    """Convert ``features/Hunt The Wumpus.feature`` -> ``features-hunt-the-wumpus-feature.json``."""
    lowered = feature_path.lower()
    hyphenated = NON_ALNUM.sub("-", lowered).strip("-")
    return f"{hyphenated}.json"


def implementation_hash(generated_files: list[Path]) -> str:
    """SHA-256 of generated files only, sorted by their POSIX-style path."""
    h = hashlib.sha256()
    for path in sorted(generated_files, key=lambda p: p.as_posix()):
        h.update(path.as_posix().encode("utf-8"))
        h.update(b"\0")
        h.update(path.read_bytes())
        h.update(b"\0")
    return f"sha256:{h.hexdigest()}"


def write_metadata(
    metadata_dir: Path,
    *,
    feature_path: str,
    ir_path: str,
    generated_files: list[Path],
) -> Path:
    metadata_dir.mkdir(parents=True, exist_ok=True)
    name = metadata_filename(feature_path)
    out = metadata_dir / name
    payload = {
        "schema_version": SCHEMA_VERSION,
        "feature_path": feature_path,
        "ir_path": ir_path,
        "implementation_hash": implementation_hash(generated_files),
        "hash_scope": "generated_files",
        "generated_files": [p.as_posix() for p in generated_files],
    }
    out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return out
