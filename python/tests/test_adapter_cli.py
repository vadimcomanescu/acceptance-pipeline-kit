import io
import json
import sys

import pytest

from aps_kit.adapter_cli import main as adapter_main


def test_no_args_returns_2(capsys: pytest.CaptureFixture) -> None:
    assert adapter_main([]) == 2
    assert "usage:" in capsys.readouterr().err


def test_help_returns_0(capsys: pytest.CaptureFixture) -> None:
    assert adapter_main(["-h"]) == 0
    assert "usage:" in capsys.readouterr().err


def test_runs_with_positional_command(monkeypatch: pytest.MonkeyPatch) -> None:
    job = json.dumps({"id": "x", "feature_json": "/x", "timeout": "5s"}) + "\n"
    monkeypatch.setattr(sys, "stdin", io.StringIO(job))
    monkeypatch.setattr(sys, "stdout", io.StringIO())
    monkeypatch.setattr(sys, "stderr", io.StringIO())
    # Use python -c sys.exit(0) as the test command so this stays portable.
    assert adapter_main([sys.executable, "-c", "import sys; sys.exit(0)"]) == 0
    response = sys.stdout.getvalue().strip()
    parsed = json.loads(response)
    assert parsed["outcome"] == "test_success"
