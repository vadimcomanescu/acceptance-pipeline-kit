import json
from pathlib import Path

import pytest

from aps_kit.ir import Feature, Scenario, Step, load_ir


def test_step_from_obj_defaults_parameters_to_empty() -> None:
    step = Step.from_obj({"keyword": "Given", "text": "ready"})
    assert step.parameters == ()


def test_step_from_obj_preserves_parameters() -> None:
    step = Step.from_obj(
        {"keyword": "When", "text": "I add <a>", "parameters": ["a"]}
    )
    assert step.parameters == ("a",)


def test_scenario_from_obj_defaults_examples_to_empty() -> None:
    scenario = Scenario.from_obj(
        {
            "name": "no examples",
            "steps": [{"keyword": "Then", "text": "ok"}],
        }
    )
    assert scenario.examples == ()


def test_feature_from_obj_rejects_missing_name() -> None:
    with pytest.raises(ValueError, match="missing 'name'"):
        Feature.from_obj({"scenarios": []})


def test_feature_from_obj_defaults_background_and_scenarios() -> None:
    feature = Feature.from_obj({"name": "F"})
    assert feature.background == ()
    assert feature.scenarios == ()


def test_load_ir_round_trip(tmp_path: Path) -> None:
    payload = {
        "name": "Calc",
        "background": [{"keyword": "Given", "text": "ready"}],
        "scenarios": [
            {
                "name": "addition",
                "steps": [
                    {
                        "keyword": "Then",
                        "text": "the result is <sum>",
                        "parameters": ["sum"],
                    }
                ],
                "examples": [{"sum": "3"}],
            }
        ],
    }
    path = tmp_path / "ir.json"
    path.write_text(json.dumps(payload), encoding="utf-8")
    feature = load_ir(path)
    assert feature.name == "Calc"
    assert feature.background == (Step(keyword="Given", text="ready"),)
    assert feature.scenarios[0].examples == ({"sum": "3"},)
