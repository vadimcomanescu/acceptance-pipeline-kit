import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import { fromObject, loadIR } from "../src/ir.js";

let dir: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "aps-kit-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("fromObject", () => {
  test("defaults background and scenarios to empty arrays", () => {
    const feature = fromObject({ name: "F" });
    expect(feature.background).toEqual([]);
    expect(feature.scenarios).toEqual([]);
  });

  test("preserves step parameters and example rows", () => {
    const feature = fromObject({
      name: "F",
      scenarios: [
        {
          name: "s",
          steps: [
            { keyword: "Then", text: "result is <r>", parameters: ["r"] },
          ],
          examples: [{ r: "ok" }],
        },
      ],
    });
    expect(feature.scenarios[0].steps[0].parameters).toEqual(["r"]);
    expect(feature.scenarios[0].examples).toEqual([{ r: "ok" }]);
  });

  test("rejects missing name", () => {
    expect(() => fromObject({ scenarios: [] })).toThrow(/missing 'name'/);
  });

  test("rejects malformed step", () => {
    expect(() =>
      fromObject({
        name: "F",
        scenarios: [{ name: "s", steps: [{ keyword: 1 } as unknown] }],
      }),
    ).toThrow(/keyword or text/);
  });

  test("rejects scenario without name", () => {
    expect(() =>
      fromObject({ name: "F", scenarios: [{ steps: [] }] }),
    ).toThrow(/scenario IR missing name/);
  });
});

describe("loadIR", () => {
  test("round-trips a calculator IR", () => {
    const ir = {
      name: "Calc",
      background: [{ keyword: "Given", text: "ready" }],
      scenarios: [
        {
          name: "addition",
          steps: [
            { keyword: "Then", text: "result is <sum>", parameters: ["sum"] },
          ],
          examples: [{ sum: "3" }],
        },
      ],
    };
    const path = join(dir, "ir.json");
    writeFileSync(path, JSON.stringify(ir));
    const feature = loadIR(path);
    expect(feature.name).toBe("Calc");
    expect(feature.background).toHaveLength(1);
    expect(feature.scenarios[0].examples[0].sum).toBe("3");
  });
});
