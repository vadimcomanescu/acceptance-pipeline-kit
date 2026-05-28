import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import { fromObject } from "../src/ir.js";
import { Registry, UnsupportedStepError } from "../src/registry.js";
import { executionsFor, runExecution } from "../src/runtime.js";

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "aps-kit-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

function writeIR(payload: unknown): string {
  const path = join(dir, "ir.json");
  writeFileSync(path, JSON.stringify(payload));
  return path;
}

function calculatorPayload() {
  return {
    name: "Calculator",
    background: [{ keyword: "Given", text: "a fresh calculator" }],
    scenarios: [
      {
        name: "addition",
        steps: [
          { keyword: "When", text: "I add <a> and <b>", parameters: ["a", "b"] },
          { keyword: "Then", text: "the result is <sum>", parameters: ["sum"] },
        ],
        examples: [{ a: "1", b: "2", sum: "3" }],
      },
    ],
  };
}

describe("runExecution", () => {
  test("runs background then scenario steps with fresh world", () => {
    const reg = new Registry();
    reg.step("a fresh calculator", (world) => {
      (world as Record<string, number>).total = 0;
    });
    reg.step("I add <a> and <b>", (world, ex) => {
      (world as Record<string, number>).total =
        parseInt(ex.a, 10) + parseInt(ex.b, 10);
    });
    reg.step("the result is <sum>", (world, ex) => {
      expect((world as Record<string, number>).total).toBe(parseInt(ex.sum, 10));
    });
    runExecution(writeIR(calculatorPayload()), 0, 0, reg);
  });

  test("unsupported step throws UnsupportedStepError", () => {
    const reg = new Registry();
    expect(() => runExecution(writeIR(calculatorPayload()), 0, 0, reg)).toThrow(
      UnsupportedStepError,
    );
  });

  test("missing example value throws missing-values error", () => {
    const reg = new Registry();
    reg.step("a fresh calculator", () => {});
    reg.step("I add <a> and <b>", () => {});
    reg.step("the result is <sum>", () => {});
    const payload = calculatorPayload();
    delete (payload.scenarios[0].examples[0] as Record<string, string>).sum;
    expect(() => runExecution(writeIR(payload), 0, 0, reg)).toThrow(
      /missing example values/,
    );
  });

  test("scenario index out of range throws", () => {
    const reg = new Registry();
    reg.step("a fresh calculator", () => {});
    expect(() => runExecution(writeIR(calculatorPayload()), 99, 0, reg)).toThrow(
      /out of range/,
    );
    expect(() => runExecution(writeIR(calculatorPayload()), -1, 0, reg)).toThrow(
      /out of range/,
    );
  });

  test("scenario without examples runs once with empty example", () => {
    const payload = {
      name: "F",
      scenarios: [
        {
          name: "s",
          steps: [{ keyword: "Then", text: "ok" }],
          examples: [],
        },
      ],
    };
    const reg = new Registry();
    let invocations = 0;
    let seenExample: Record<string, string> | null = null;
    reg.step("ok", (_w, ex) => {
      invocations += 1;
      seenExample = ex;
    });
    runExecution(writeIR(payload), 0, 0, reg);
    expect(invocations).toBe(1);
    expect(seenExample).toEqual({});
  });

  test("scenario without examples rejects non-zero example index", () => {
    const payload = {
      name: "F",
      scenarios: [{ name: "s", steps: [], examples: [] }],
    };
    const reg = new Registry();
    expect(() => runExecution(writeIR(payload), 0, 1, reg)).toThrow(
      /only exampleIndex=0 is valid/,
    );
  });

  test("scenario with examples rejects out-of-range example index", () => {
    // Regression: TS used to silently return an empty example object when the
    // example index was past the end, masking the bug behind a misleading
    // "missing example values" error. Now it fails fast.
    const reg = new Registry();
    reg.step("a fresh calculator", () => {});
    reg.step("I add <a> and <b>", () => {});
    reg.step("the result is <sum>", () => {});
    expect(() => runExecution(writeIR(calculatorPayload()), 0, 99, reg)).toThrow(
      /example index 99 out of range/,
    );
  });

  test("uses default registry when none provided", async () => {
    const { defaultRegistry } = await import("../src/registry.js");
    let called = false;
    defaultRegistry.step("ts-default-marker", () => {
      called = true;
    });
    const payload = {
      name: "F",
      scenarios: [
        {
          name: "s",
          steps: [{ keyword: "Given", text: "ts-default-marker" }],
          examples: [],
        },
      ],
    };
    runExecution(writeIR(payload), 0, 0);
    expect(called).toBe(true);
  });
});

describe("executionsFor", () => {
  test("yields one pair per execution; scenarios with no examples yield one", () => {
    const feature = fromObject({
      name: "F",
      scenarios: [
        {
          name: "with examples",
          steps: [],
          examples: [{ a: "1" }, { a: "2" }],
        },
        { name: "no examples", steps: [], examples: [] },
      ],
    });
    expect(executionsFor(feature)).toEqual([
      [0, 0],
      [0, 1],
      [1, 0],
    ]);
  });
});
