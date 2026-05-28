import json
from pathlib import Path

from aps_kit.generator import generate


def test_emits_one_test_per_execution(tmp_path: Path) -> None:
    ir = {
        "name": "Calculator",
        "background": [{"keyword": "Given", "text": "a fresh calculator"}],
        "scenarios": [
            {
                "name": "addition",
                "steps": [{"keyword": "Then", "text": "ok"}],
                "examples": [{"a": "1"}, {"a": "2"}],
            },
            {
                "name": "no examples",
                "steps": [{"keyword": "Then", "text": "ok"}],
                "examples": [],
            },
        ],
    }
    ir_path = tmp_path / "ir.json"
    ir_path.write_text(json.dumps(ir), encoding="utf-8")
    out = tmp_path / "out"
    generated = generate(ir_path, out, feature_path="features/calc.feature")
    assert len(generated) == 1
    body = generated[0].read_text()
    # Two addition rows + one no-examples scenario = three tests.
    assert body.count("def test_scenario_") == 3
    meta = json.loads((out / "metadata" / "features-calc-feature.json").read_text())
    assert meta["schema_version"] == 1
    assert meta["hash_scope"] == "generated_files"
    assert meta["implementation_hash"].startswith("sha256:")
