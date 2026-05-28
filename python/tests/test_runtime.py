import json
from pathlib import Path

import pytest

from aps_kit.ir import Feature, Scenario, Step
from aps_kit.registry import Registry, UnsupportedStepError
from aps_kit.runtime import executions_for, run_execution


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
    reg.step("a fresh calculator")(lambda world, _ex: world.update({"total": 0}))
    reg.step("I add <a> and <b>")(
        lambda world, ex: world.update({"total": int(ex["a"]) + int(ex["b"])})
    )
    reg.step("the result is <sum>")(
        lambda world, ex: (_ for _ in ()).throw(
            AssertionError(f"expected {ex['sum']} got {world['total']}")
        )
        if world["total"] != int(ex["sum"])
        else None
    )
    run_execution(_write_ir(tmp_path), 0, 0, registry=reg)


def test_unsupported_step_fails(tmp_path: Path) -> None:
    reg = Registry()
    with pytest.raises(UnsupportedStepError):
        run_execution(_write_ir(tmp_path), 0, 0, registry=reg)


def test_missing_parameter_fails(tmp_path: Path) -> None:
    reg = Registry()
    reg.step("a fresh calculator")(lambda world, _ex: None)
    reg.step("I add <a> and <b>")(lambda world, ex: None)
    reg.step("the result is <sum>")(lambda world, ex: None)

    ir = json.loads(_write_ir(tmp_path).read_text())
    ir["scenarios"][0]["examples"][0].pop("sum")
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps(ir), encoding="utf-8")
    with pytest.raises(AssertionError, match="missing example values"):
        run_execution(bad, 0, 0, registry=reg)


def test_scenario_index_out_of_range(tmp_path: Path) -> None:
    reg = Registry()
    reg.step("a fresh calculator")(lambda world, _ex: None)
    with pytest.raises(AssertionError, match="out of range"):
        run_execution(_write_ir(tmp_path), 99, 0, registry=reg)


def test_negative_scenario_index_rejected(tmp_path: Path) -> None:
    reg = Registry()
    reg.step("a fresh calculator")(lambda world, _ex: None)
    with pytest.raises(AssertionError, match="out of range"):
        run_execution(_write_ir(tmp_path), -1, 0, registry=reg)


def test_scenario_without_examples_runs_once() -> None:
    feature = Feature(
        name="F",
        background=(),
        scenarios=(
            Scenario(
                name="no examples",
                steps=(Step(keyword="Then", text="ok"),),
                examples=(),
            ),
        ),
    )
    assert list(executions_for(feature)) == [(0, 0)]


def test_example_index_out_of_range_for_scenario_without_examples(tmp_path: Path) -> None:
    ir = {
        "name": "F",
        "scenarios": [
            {"name": "s", "steps": [{"keyword": "Then", "text": "ok"}], "examples": []}
        ],
    }
    p = tmp_path / "ir.json"
    p.write_text(json.dumps(ir), encoding="utf-8")
    reg = Registry()
    reg.step("ok")(lambda _w, _ex: None)
    with pytest.raises(IndexError, match="only example_index=0 is valid"):
        run_execution(p, 0, 1, registry=reg)
