import pytest

from aps_kit.registry import Registry, UnsupportedStepError


def test_step_registers_handler() -> None:
    reg = Registry()

    @reg.step("the answer is 42")
    def handler(_world, _ex):  # noqa: ANN001
        pass

    assert "the answer is 42" in reg
    assert reg.resolve("the answer is 42") is handler


def test_step_rejects_duplicate_text() -> None:
    reg = Registry()
    reg.step("ready")(lambda _w, _ex: None)
    with pytest.raises(ValueError, match="duplicate step handler"):
        reg.step("ready")(lambda _w, _ex: None)


def test_resolve_raises_unsupported_for_unknown_text() -> None:
    reg = Registry()
    with pytest.raises(UnsupportedStepError) as info:
        reg.resolve("never seen this")
    assert "never seen this" in str(info.value)


def test_contains_reports_membership() -> None:
    reg = Registry()
    assert "x" not in reg
    reg.step("x")(lambda _w, _ex: None)
    assert "x" in reg
