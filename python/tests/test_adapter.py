"""Adapter tests. The serve loop reads NDJSON from stdin and writes responses
to stdout; we drive it with StringIO so the test stays hermetic and fast.
"""
import io
import json
import sys

import pytest

from aps_kit.adapter import _classify, _handle, _parse_timeout, serve


# ---- pure functions ------------------------------------------------------

def test_classify_exit_codes() -> None:
    assert _classify(0) == "test_success"
    assert _classify(1) == "test_failure"
    assert _classify(2) == "infrastructure_error"
    assert _classify(5) == "infrastructure_error"
    assert _classify(137) == "infrastructure_error"


def test_parse_timeout_units() -> None:
    assert _parse_timeout("30s") == pytest.approx(30.0)
    assert _parse_timeout("250ms") == pytest.approx(0.25)
    assert _parse_timeout("2m") == pytest.approx(120.0)
    assert _parse_timeout("15") == pytest.approx(15.0)


def test_parse_timeout_returns_none_for_unparseable() -> None:
    assert _parse_timeout(None) is None
    assert _parse_timeout("") is None
    assert _parse_timeout("forever") is None


# ---- _handle drives a real subprocess; use python -c so it's portable ----

def _job(extra: dict | None = None) -> dict:
    base = {
        "id": "m1",
        "feature_json": "/tmp/ir.json",
        "generated_dir": "g",
        "work_dir": "w",
        "timeout": "5s",
    }
    if extra:
        base.update(extra)
    return base


def test_handle_test_success_exit_0() -> None:
    resp = _handle(_job(), [sys.executable, "-c", "import sys; sys.exit(0)"], cwd=None)
    assert resp["outcome"] == "test_success"
    assert resp["id"] == "m1"
    assert resp["duration"] >= 0


def test_handle_test_failure_exit_1() -> None:
    resp = _handle(_job(), [sys.executable, "-c", "import sys; sys.exit(1)"], cwd=None)
    assert resp["outcome"] == "test_failure"


def test_handle_infrastructure_error_other_exit() -> None:
    resp = _handle(_job(), [sys.executable, "-c", "import sys; sys.exit(42)"], cwd=None)
    assert resp["outcome"] == "infrastructure_error"


def test_handle_injects_aps_env_vars() -> None:
    # The subprocess prints APS_IR_PATH so we can confirm it was injected.
    cmd = [
        sys.executable,
        "-c",
        "import os, sys; print(os.environ['APS_IR_PATH']); sys.exit(0)",
    ]
    resp = _handle(_job({"feature_json": "/path/to/mutated.json"}), cmd, cwd=None)
    assert resp["outcome"] == "test_success"
    assert "/path/to/mutated.json" in resp["output"]


def test_handle_timeout_classifies_as_infrastructure_error() -> None:
    resp = _handle(
        _job({"timeout": "100ms"}),
        [sys.executable, "-c", "import time; time.sleep(2)"],
        cwd=None,
    )
    assert resp["outcome"] == "infrastructure_error"
    assert "timeout" in resp["error"]


# ---- serve loop ----------------------------------------------------------

def _drive_serve(
    monkeypatch: pytest.MonkeyPatch,
    stdin_text: str,
    cmd: list[str],
) -> tuple[str, str]:
    stdin = io.StringIO(stdin_text)
    stdout = io.StringIO()
    stderr = io.StringIO()
    monkeypatch.setattr(sys, "stdin", stdin)
    monkeypatch.setattr(sys, "stdout", stdout)
    monkeypatch.setattr(sys, "stderr", stderr)
    serve(cmd)
    return stdout.getvalue(), stderr.getvalue()


def test_serve_writes_one_response_per_job(monkeypatch: pytest.MonkeyPatch) -> None:
    jobs = "\n".join(
        json.dumps({"id": jid, "feature_json": "/x", "timeout": "5s"}) for jid in ("a", "b", "c")
    )
    out, _ = _drive_serve(
        monkeypatch, jobs + "\n", [sys.executable, "-c", "import sys; sys.exit(0)"]
    )
    lines = [json.loads(line) for line in out.strip().splitlines()]
    assert [r["id"] for r in lines] == ["a", "b", "c"]
    assert all(r["outcome"] == "test_success" for r in lines)


def test_serve_skips_blank_lines(monkeypatch: pytest.MonkeyPatch) -> None:
    stream = '\n   \n{"id":"x","feature_json":"/x","timeout":"5s"}\n\n'
    out, _ = _drive_serve(
        monkeypatch, stream, [sys.executable, "-c", "import sys; sys.exit(0)"]
    )
    lines = out.strip().splitlines()
    assert len(lines) == 1


def test_serve_reports_bad_json_to_stderr(monkeypatch: pytest.MonkeyPatch) -> None:
    out, err = _drive_serve(
        monkeypatch,
        "{not valid}\n",
        [sys.executable, "-c", "import sys; sys.exit(0)"],
    )
    assert out == ""
    assert "bad job line" in err


def test_serve_only_writes_protocol_to_stdout(monkeypatch: pytest.MonkeyPatch) -> None:
    # pytest-style subprocess that prints noise on both stdout and stderr.
    cmd = [
        sys.executable,
        "-c",
        "import sys; print('noise'); print('err', file=sys.stderr); sys.exit(0)",
    ]
    out, _ = _drive_serve(
        monkeypatch,
        '{"id":"x","feature_json":"/x","timeout":"5s"}\n',
        cmd,
    )
    # Every line on stdout must parse as JSON; the subprocess noise must be in `output`.
    for line in out.strip().splitlines():
        parsed = json.loads(line)
        assert "noise" in parsed["output"]
