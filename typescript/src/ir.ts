// JSON IR types and loader. Mirrors specs/parser-spec.md.
import { readFileSync } from "node:fs";

export interface Step {
  keyword: string;
  text: string;
  parameters: string[];
}

export interface Scenario {
  name: string;
  steps: Step[];
  examples: Record<string, string>[];
}

export interface Feature {
  name: string;
  background: Step[];
  scenarios: Scenario[];
}

function normalizeStep(raw: unknown): Step {
  const s = raw as { keyword?: string; text?: string; parameters?: string[] };
  if (typeof s.keyword !== "string" || typeof s.text !== "string") {
    throw new Error("step IR missing keyword or text");
  }
  return {
    keyword: s.keyword,
    text: s.text,
    parameters: Array.isArray(s.parameters) ? [...s.parameters] : [],
  };
}

function normalizeScenario(raw: unknown): Scenario {
  const s = raw as {
    name?: string;
    steps?: unknown[];
    examples?: Record<string, string>[];
  };
  if (typeof s.name !== "string") {
    throw new Error("scenario IR missing name");
  }
  return {
    name: s.name,
    steps: (s.steps ?? []).map(normalizeStep),
    examples: (s.examples ?? []).map((row) => ({ ...row })),
  };
}

export function fromObject(raw: unknown): Feature {
  const r = raw as {
    name?: string;
    background?: unknown[];
    scenarios?: unknown[];
  };
  if (typeof r.name !== "string") {
    throw new Error("feature IR missing 'name'");
  }
  return {
    name: r.name,
    background: (r.background ?? []).map(normalizeStep),
    scenarios: (r.scenarios ?? []).map(normalizeScenario),
  };
}

export function loadIR(path: string): Feature {
  return fromObject(JSON.parse(readFileSync(path, "utf-8")));
}
