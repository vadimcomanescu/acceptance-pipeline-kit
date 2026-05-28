// Acceptance runtime. Mirrors specs/acceptance-generator.md runtime contract.
import type { Feature, Scenario, Step } from "./ir.js";
import { loadIR } from "./ir.js";
import { defaultRegistry, Registry } from "./registry.js";

export function executionsFor(feature: Feature): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  feature.scenarios.forEach((scenario, sIdx) => {
    if (scenario.examples.length === 0) {
      out.push([sIdx, 0]);
    } else {
      scenario.examples.forEach((_, eIdx) => out.push([sIdx, eIdx]));
    }
  });
  return out;
}

function exampleFor(scenario: Scenario, exampleIndex: number): Record<string, string> {
  if (scenario.examples.length === 0) {
    if (exampleIndex !== 0) {
      throw new Error(
        `scenario ${scenario.name} has no examples; only exampleIndex=0 is valid`,
      );
    }
    return {};
  }
  return { ...scenario.examples[exampleIndex] };
}

function runStep(
  step: Step,
  world: Record<string, unknown>,
  example: Record<string, string>,
  registry: Registry,
): void {
  // Resolve the handler first so an unsupported step gives the most useful
  // error before we check anything else; then validate required example
  // values; then invoke. Same order in all four language runtimes.
  const handler = registry.resolve(step.text);
  const missing = step.parameters.filter((p) => !(p in example));
  if (missing.length > 0) {
    throw new Error(
      `step "${step.text}" references missing example values: ${missing.join(", ")}`,
    );
  }
  handler(world, example);
}

export function runExecution(
  irPath: string,
  scenarioIndex: number,
  exampleIndex: number,
  registry: Registry = defaultRegistry,
): void {
  const feature = loadIR(irPath);
  if (scenarioIndex < 0 || scenarioIndex >= feature.scenarios.length) {
    throw new Error(
      `scenario index ${scenarioIndex} out of range; feature has ${feature.scenarios.length} scenarios`,
    );
  }
  const scenario = feature.scenarios[scenarioIndex];
  const example = exampleFor(scenario, exampleIndex);
  const world: Record<string, unknown> = {};
  for (const step of feature.background) {
    runStep(step, world, example, registry);
  }
  for (const step of scenario.steps) {
    runStep(step, world, example, registry);
  }
}
