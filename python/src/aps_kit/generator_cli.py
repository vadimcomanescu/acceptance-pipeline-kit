"""acceptance-entrypoint-generator CLI."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .generator import generate


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="aps-generate",
        description="Generate pytest entry points from APS JSON IR.",
    )
    parser.add_argument("ir", help="Path to the JSON IR produced by gherkin-parser.")
    parser.add_argument(
        "output_dir",
        help="Directory where generated test files and metadata/ are written.",
    )
    parser.add_argument(
        "--feature-path",
        help=(
            "Original .feature path to record in metadata. Defaults to the IR path. "
            "Use this when the feature lives under a different name than the IR."
        ),
    )
    args = parser.parse_args(argv)
    try:
        generate(
            Path(args.ir),
            Path(args.output_dir),
            feature_path=args.feature_path,
        )
    except FileNotFoundError as exc:
        print(f"aps-generate: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"aps-generate: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
