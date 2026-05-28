"""aps-adapter CLI: persistent runner-worker for gherkin-mutator.

Usage:
    aps-adapter <test-cmd> [test-args...]

Everything after ``aps-adapter`` is the project's test command. The adapter
sets ``APS_IR_PATH`` in the environment for each job and forwards stdout/stderr
into the response. This positional form is what works with
``gherkin-mutator --runner-worker``, which splits its value on whitespace.
"""
from __future__ import annotations

import sys

from .adapter import serve


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] in {"-h", "--help"}:
        sys.stderr.write("usage: aps-adapter <test-cmd> [test-args...]\n")
        return 0 if args else 2
    return serve(args, cwd=None)


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
