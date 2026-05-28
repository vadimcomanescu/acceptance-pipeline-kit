import { writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import { Registry, UnsupportedStepError } from "../src/registry.js";
import { runExecution } from "../src/runtime.js";

function writeIR(dir: string): string {
  const ir = {
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
  const path = join(dir, "ir.json");
  writeFileSync(path, JSON.stringify(ir));
  return path;
}

describe("runExecution", () => {
  let dir: string;

  beforeEach(() => {
    dir = tmpdir() + "/aps-kit-" + Math.random().toString(36).slice(2);
    require("node:fs").mkdirSync(dir, { recursive: true });
  });

  afterEach(() => {
    require("node:fs").rmSync(dir, { recursive: true, force: true });
  });

  test("runs background then scenario steps", () => {
    const reg = new Registry();
    reg.step("a fresh calculator", (world) => {
      world.total = 0;
    });
    reg.step("I add <a> and <b>", (world, ex) => {
      world.total = parseInt(ex.a, 10) + parseInt(ex.b, 10);
    });
    reg.step("the result is <sum>", (world, ex) => {
      expect(world.total).toBe(parseInt(ex.sum, 10));
    });
    runExecution(writeIR(dir), 0, 0, reg);
  });

  test("unsupported step throws", () => {
    const reg = new Registry();
    expect(() => runExecution(writeIR(dir), 0, 0, reg)).toThrow(
      UnsupportedStepError,
    );
  });
});
