"""acceptance-entrypoint-generator CLI.

Per the APS acceptance-generator spec, the command is invoked as:

    acceptance-entrypoint-generator <json-ir> <generated-test-output>

Two positional arguments, nothing else. Language-specific configuration is
read from environment variables:

    APS_FEATURE_PATH   feature path to record in metadata (default: <json-ir>)
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from .generator import generate


_USAGE = (
    "usage: acceptance-entrypoint-generator <json-ir> <generated-test-output>"
)


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0] in {"-h", "--help"}:
        sys.stderr.write(_USAGE + "\n")
        return 0
    if len(args) != 2:
        sys.stderr.write(_USAGE + "\n")
        return 2
    ir_path, output_dir = args
    feature_path = os.environ.get("APS_FEATURE_PATH") or None
    try:
        generate(Path(ir_path), Path(output_dir), feature_path=feature_path)
    except FileNotFoundError as exc:
        sys.stderr.write(f"acceptance-entrypoint-generator: {exc}\n")
        return 1
    except (ValueError, OSError) as exc:
        sys.stderr.write(f"acceptance-entrypoint-generator: {exc}\n")
        return 1
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
