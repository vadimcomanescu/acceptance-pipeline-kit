"""Runner adapter: persistent NDJSON worker for gherkin-mutator.

Each input line is a JSON job request; each output line is a JSON job response.
Diagnostics go to stderr only.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


def _classify(returncode: int) -> str:
    if returncode == 0:
        return "test_success"
    if returncode == 1 or returncode == 2 or returncode == 3 or returncode == 4 or returncode == 5:
        # pytest exit codes: 1 (tests failed), 2 (interrupted), 3 (internal), 4 (usage), 5 (no tests).
        # Treat 1 as test_failure and the rest as infrastructure_error.
        return "test_failure" if returncode == 1 else "infrastructure_error"
    return "infrastructure_error"


def _parse_timeout(s: str | None) -> float | None:
    if not s:
        return None
    s = s.strip()
    if s.endswith("ms"):
        return float(s[:-2]) / 1000.0
    if s.endswith("s"):
        return float(s[:-1])
    if s.endswith("m"):
        return float(s[:-1]) * 60.0
    try:
        return float(s)
    except ValueError:
        return None


def _handle(job: dict[str, Any], test_command: list[str], cwd: Path | None) -> dict[str, Any]:
    env = os.environ.copy()
    env["APS_IR_PATH"] = job["feature_json"]
    env["APS_GENERATED_DIR"] = job.get("generated_dir", "")
    env["APS_WORK_DIR"] = job.get("work_dir", "")
    timeout = _parse_timeout(job.get("timeout"))
    started = time.monotonic_ns()
    try:
        proc = subprocess.run(
            test_command,
            env=env,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        elapsed = time.monotonic_ns() - started
        return {
            "id": job["id"],
            "outcome": "infrastructure_error",
            "output": exc.stdout or "",
            "error": f"timeout after {timeout}s",
            "duration": elapsed,
        }
    elapsed = time.monotonic_ns() - started
    return {
        "id": job["id"],
        "outcome": _classify(proc.returncode),
        "output": proc.stdout,
        "error": proc.stderr,
        "duration": elapsed,
    }


def serve(test_command: list[str], cwd: Path | None = None) -> int:
    """Loop reading NDJSON jobs from stdin, writing NDJSON responses to stdout."""
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            job = json.loads(raw)
        except json.JSONDecodeError as exc:
            print(f"aps-adapter: bad job line: {exc}", file=sys.stderr)
            continue
        try:
            resp = _handle(job, test_command, cwd)
        except Exception as exc:  # noqa: BLE001
            resp = {
                "id": job.get("id", ""),
                "outcome": "infrastructure_error",
                "output": "",
                "error": f"adapter exception: {exc}",
                "duration": 0,
            }
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()
    return 0
