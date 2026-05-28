"""Tests for the CLI entry points. Each is invoked by argv; we capture stderr
via the pytest capsys fixture and assert exit codes match the spec."""
import json
from pathlib import Path

import pytest

from aps_kit.generator_cli import main as generate_main


def _write_ir(tmp_path: Path) -> Path:
    payload = {
        "name": "F",
        "scenarios": [
            {"name": "s", "steps": [{"keyword": "Then", "text": "ok"}], "examples": []}
        ],
    }
    p = tmp_path / "ir.json"
    p.write_text(json.dumps(payload), encoding="utf-8")
    return p


def test_generator_cli_success(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    ir = _write_ir(tmp_path)
    out = tmp_path / "out"
    monkeypatch.setenv("APS_FEATURE_PATH", "features/foo.feature")
    assert generate_main([str(ir), str(out)]) == 0
    assert (out / "metadata" / "features-foo-feature.json").exists()


def test_generator_cli_usage_error_returns_2(capsys: pytest.CaptureFixture) -> None:
    assert generate_main([]) == 2
    assert "usage:" in capsys.readouterr().err


def test_generator_cli_too_many_args_returns_2(capsys: pytest.CaptureFixture) -> None:
    assert generate_main(["a", "b", "c"]) == 2
    assert "usage:" in capsys.readouterr().err


def test_generator_cli_help_returns_0(capsys: pytest.CaptureFixture) -> None:
    assert generate_main(["--help"]) == 0
    assert "usage:" in capsys.readouterr().err


def test_generator_cli_missing_ir_returns_1(tmp_path: Path, capsys: pytest.CaptureFixture) -> None:
    out = tmp_path / "out"
    assert generate_main([str(tmp_path / "missing.json"), str(out)]) == 1
    assert "acceptance-entrypoint-generator" in capsys.readouterr().err


def test_generator_cli_invalid_ir_returns_1(tmp_path: Path, capsys: pytest.CaptureFixture) -> None:
    bad = tmp_path / "bad.json"
    bad.write_text("not json", encoding="utf-8")
    out = tmp_path / "out"
    assert generate_main([str(bad), str(out)]) == 1


def test_generator_cli_ir_missing_name_returns_1(
    tmp_path: Path, capsys: pytest.CaptureFixture
) -> None:
    bad = tmp_path / "noname.json"
    bad.write_text(json.dumps({"scenarios": []}), encoding="utf-8")
    out = tmp_path / "out"
    assert generate_main([str(bad), str(out)]) == 1
    assert "missing 'name'" in capsys.readouterr().err
