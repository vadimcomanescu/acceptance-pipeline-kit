import json
from pathlib import Path

from aps_kit.metadata import (
    SCHEMA_VERSION,
    implementation_hash,
    metadata_filename,
    write_metadata,
)


def test_normalizes_features_subdir() -> None:
    assert (
        metadata_filename("features/Hunt The Wumpus.feature")
        == "features-hunt-the-wumpus-feature.json"
    )


def test_normalizes_nested() -> None:
    assert (
        metadata_filename("features/orders/Cancel Order.feature")
        == "features-orders-cancel-order-feature.json"
    )


def test_normalizes_mixed_case_and_punct() -> None:
    assert (
        metadata_filename("Features/API v2/Happy Path.feature")
        == "features-api-v2-happy-path-feature.json"
    )


def test_implementation_hash_is_deterministic_and_path_sensitive(tmp_path: Path) -> None:
    a = tmp_path / "a.txt"
    b = tmp_path / "b.txt"
    a.write_text("alpha", encoding="utf-8")
    b.write_text("beta", encoding="utf-8")
    h1 = implementation_hash([a, b])
    h2 = implementation_hash([b, a])  # sorted internally
    assert h1 == h2
    assert h1.startswith("sha256:")
    # Different content changes the hash.
    b.write_text("gamma", encoding="utf-8")
    assert implementation_hash([a, b]) != h1


def test_write_metadata_emits_expected_shape(tmp_path: Path) -> None:
    test_file = tmp_path / "generated_test.py"
    test_file.write_text("# generated\n", encoding="utf-8")
    metadata_dir = tmp_path / "metadata"
    out = write_metadata(
        metadata_dir,
        feature_path="features/orders.feature",
        ir_path="build/acceptance/orders.json",
        generated_files=[test_file],
    )
    assert out.name == "features-orders-feature.json"
    payload = json.loads(out.read_text(encoding="utf-8"))
    assert payload["schema_version"] == SCHEMA_VERSION
    assert payload["feature_path"] == "features/orders.feature"
    assert payload["ir_path"] == "build/acceptance/orders.json"
    assert payload["hash_scope"] == "generated_files"
    assert payload["implementation_hash"].startswith("sha256:")
    assert payload["generated_files"] == [test_file.as_posix()]
