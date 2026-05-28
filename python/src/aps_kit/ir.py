"""JSON IR types and loader. Mirrors specs/parser-spec.md."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Step:
    keyword: str
    text: str
    parameters: tuple[str, ...] = ()

    @classmethod
    def from_obj(cls, obj: dict[str, Any]) -> "Step":
        return cls(
            keyword=obj["keyword"],
            text=obj["text"],
            parameters=tuple(obj.get("parameters") or ()),
        )


@dataclass(frozen=True)
class Scenario:
    name: str
    steps: tuple[Step, ...]
    examples: tuple[dict[str, str], ...]

    @classmethod
    def from_obj(cls, obj: dict[str, Any]) -> "Scenario":
        return cls(
            name=obj["name"],
            steps=tuple(Step.from_obj(s) for s in obj.get("steps", [])),
            examples=tuple(obj.get("examples") or ()),
        )


@dataclass(frozen=True)
class Feature:
    name: str
    background: tuple[Step, ...] = ()
    scenarios: tuple[Scenario, ...] = field(default_factory=tuple)

    @classmethod
    def from_obj(cls, obj: dict[str, Any]) -> "Feature":
        if "name" not in obj:
            raise ValueError("feature IR missing 'name'")
        return cls(
            name=obj["name"],
            background=tuple(Step.from_obj(s) for s in obj.get("background") or ()),
            scenarios=tuple(Scenario.from_obj(s) for s in obj.get("scenarios") or ()),
        )


def load_ir(path: str | Path) -> Feature:
    with open(path, encoding="utf-8") as fh:
        return Feature.from_obj(json.load(fh))
