import { describe, expect, test } from "vitest";
import { Registry, UnsupportedStepError } from "../src/registry.js";

describe("Registry", () => {
  test("step registers and resolves handlers", () => {
    const reg = new Registry();
    let called = false;
    reg.step("ready", () => {
      called = true;
    });
    expect(reg.has("ready")).toBe(true);
    reg.resolve("ready")({}, {});
    expect(called).toBe(true);
  });

  test("resolve throws UnsupportedStepError on unknown text", () => {
    const reg = new Registry();
    expect(() => reg.resolve("never")).toThrow(UnsupportedStepError);
    try {
      reg.resolve("never");
    } catch (err) {
      expect((err as UnsupportedStepError).text).toBe("never");
    }
  });

  test("step rejects duplicate text", () => {
    const reg = new Registry();
    reg.step("x", () => {});
    expect(() => reg.step("x", () => {})).toThrow(/duplicate step handler/);
  });

  test("has returns false for unknown text", () => {
    const reg = new Registry();
    expect(reg.has("never")).toBe(false);
  });
});
