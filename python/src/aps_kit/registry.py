"""Step handler registry. Exact-text matching is the portable baseline."""
from __future__ import annotations

from typing import Any, Callable, Dict

# world is a mutable per-execution dict; example is the row of example values.
StepHandler = Callable[[Dict[str, Any], Dict[str, str]], None]


class UnsupportedStepError(LookupError):
    """Raised when a step's text has no registered handler."""


class Registry:
    def __init__(self) -> None:
        self._steps: Dict[str, StepHandler] = {}

    def step(self, text: str) -> Callable[[StepHandler], StepHandler]:
        def deco(fn: StepHandler) -> StepHandler:
            if text in self._steps:
                raise ValueError(f"duplicate step handler: {text!r}")
            self._steps[text] = fn
            return fn

        return deco

    def resolve(self, text: str) -> StepHandler:
        try:
            return self._steps[text]
        except KeyError as exc:
            raise UnsupportedStepError(text) from exc

    def __contains__(self, text: str) -> bool:
        return text in self._steps


default_registry = Registry()
