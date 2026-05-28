// Step handler registry. Exact-text matching is the portable baseline.

export type World = Record<string, unknown>;
export type Example = Record<string, string>;
export type StepHandler = (world: World, example: Example) => void;

export class UnsupportedStepError extends Error {
  constructor(public readonly text: string) {
    super(`unsupported step: ${text}`);
    this.name = "UnsupportedStepError";
  }
}

export class Registry {
  private readonly steps = new Map<string, StepHandler>();

  step(text: string, handler: StepHandler): void {
    if (this.steps.has(text)) {
      throw new Error(`duplicate step handler: ${text}`);
    }
    this.steps.set(text, handler);
  }

  resolve(text: string): StepHandler {
    const fn = this.steps.get(text);
    if (!fn) throw new UnsupportedStepError(text);
    return fn;
  }

  has(text: string): boolean {
    return this.steps.has(text);
  }
}

export const defaultRegistry = new Registry();
