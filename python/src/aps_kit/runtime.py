"""Acceptance runtime. Mirrors specs/acceptance-generator.md runtime contract."""
from __future__ import annotations

from pathlib import Path
from typing import Any, Iterator

from .ir import Feature, Scenario, Step, load_ir
from .registry import Registry, default_registry


def executions_for(feature: Feature) -> Iterator[tuple[int, int]]:
    """Yield (scenario_index, example_index) pairs the runtime must execute.

    A scenario with no examples produces exactly one execution (example_index 0
    with an empty example object). A scenario with N example rows produces N
    executions.
    """
    for s_idx, scenario in enumerate(feature.scenarios):
        if not scenario.examples:
            yield s_idx, 0
        else:
            for e_idx in range(len(scenario.examples)):
                yield s_idx, e_idx


def _example_for(scenario: Scenario, example_index: int) -> dict[str, str]:
    if not scenario.examples:
        if example_index != 0:
            raise IndexError(
                f"scenario {scenario.name!r} has no examples; only example_index=0 is valid"
            )
        return {}
    return dict(scenario.examples[example_index])


def _run_step(step: Step, world: dict[str, Any], example: dict[str, str], registry: Registry) -> None:
    # Resolve the handler first so an unsupported step gives the most useful
    # error before we check anything else; then validate required example
    # values; then invoke. Same order in all four language runtimes.
    handler = registry.resolve(step.text)
    missing = [p for p in step.parameters if p not in example]
    if missing:
        raise AssertionError(
            f"step {step.text!r} references missing example values: {missing}"
        )
    handler(world, example)


def run_execution(
    ir_path: str | Path,
    scenario_index: int,
    example_index: int,
    registry: Registry | None = None,
) -> None:
    """Run a single scenario/example execution from the IR file at ``ir_path``.

    The runtime loads the IR fresh on each call so a mutator can swap the file
    between runs without re-importing the test module.
    """
    feature = load_ir(ir_path)
    if scenario_index < 0 or scenario_index >= len(feature.scenarios):
        raise AssertionError(
            f"scenario index {scenario_index} out of range; feature has "
            f"{len(feature.scenarios)} scenarios"
        )
    scenario = feature.scenarios[scenario_index]
    example = _example_for(scenario, example_index)
    reg = registry or default_registry
    world: dict[str, Any] = {}
    for step in feature.background:
        _run_step(step, world, example, reg)
    for step in scenario.steps:
        _run_step(step, world, example, reg)
