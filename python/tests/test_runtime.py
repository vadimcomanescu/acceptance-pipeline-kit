import json
from pathlib import Path

import pytest

from aps_kit.registry import Registry, UnsupportedStepError
from aps_kit.runtime import run_execution


def _write_ir(tmp_path: Path) -> Path:
    ir = {
        "name": "Calculator",
        "background": [{"keyword": "Given", "text": "a fresh calculator"}],
        "scenarios": [
            {
                "name": "addition",
                "steps": [
                    {"keyword": "When", "text": "I add <a> and <b>", "parameters": ["a", "b"]},
                    {"keyword": "Then", "text": "the result is <sum>", "parameters": ["sum"]},
                ],
                "examples": [{"a": "1", "b": "2", "sum": "3"}],
            }
        ],
    }
    p = tmp_path / "ir.json"
    p.write_text(json.dumps(ir), encoding="utf-8")
    return p


def test_runs_scenario_with_background(tmp_path: Path) -> None:
    reg = Registry()

    @reg.step("a fresh calculator")
    def _(world, _ex):
        world["total"] = 0

    @reg.step("I add <a> and <b>")
    def _(world, ex):
        world["total"] = int(ex["a"]) + int(ex["b"])

    @reg.step("the result is <sum>")
    def _(world, ex):
        assert world["total"] == int(ex["sum"])

    ir = _write_ir(tmp_path)
    run_execution(ir, 0, 0, registry=reg)


def test_unsupported_step_fails(tmp_path: Path) -> None:
    reg = Registry()
    ir = _write_ir(tmp_path)
    with pytest.raises(UnsupportedStepError):
        run_execution(ir, 0, 0, registry=reg)


def test_missing_parameter_fails(tmp_path: Path) -> None:
    reg = Registry()

    @reg.step("a fresh calculator")
    def _(world, _ex):
        world["total"] = 0

    @reg.step("I add <a> and <b>")
    def _(world, ex):
        world["total"] = int(ex["a"]) + int(ex["b"])

    @reg.step("the result is <sum>")
    def _(world, ex):
        assert world["total"] == int(ex["sum"])

    # Strip a required key.
    ir = json.loads(_write_ir(tmp_path).read_text())
    ir["scenarios"][0]["examples"][0].pop("sum")
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps(ir), encoding="utf-8")
    with pytest.raises(AssertionError):
        run_execution(bad, 0, 0, registry=reg)
