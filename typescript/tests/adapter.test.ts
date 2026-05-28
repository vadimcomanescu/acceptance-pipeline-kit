// In-process adapter tests. Drive serveIO with PassThrough streams so
// coverage counts every branch of the NDJSON loop and the classification code.
import { PassThrough, Readable } from "node:stream";
import { describe, expect, test } from "vitest";

import { classifyExit, parseTimeoutMs, serveIO } from "../src/adapter.js";

function streamFromString(s: string): Readable {
  const r = new Readable();
  r.push(s);
  r.push(null);
  return r;
}

async function drive(
  command: string,
  args: string[],
  input: string,
): Promise<{ out: string; err: string }> {
  const output = new PassThrough();
  const diagnostics = new PassThrough();
  const outChunks: Buffer[] = [];
  const errChunks: Buffer[] = [];
  output.on("data", (c: Buffer) => outChunks.push(c));
  diagnostics.on("data", (c: Buffer) => errChunks.push(c));
  await serveIO({ command, args }, streamFromString(input), output, diagnostics);
  return {
    out: Buffer.concat(outChunks).toString("utf-8"),
    err: Buffer.concat(errChunks).toString("utf-8"),
  };
}

describe("classifyExit", () => {
  test("0 is test_success, 1 is test_failure, else infrastructure_error", () => {
    expect(classifyExit(0)).toBe("test_success");
    expect(classifyExit(1)).toBe("test_failure");
    expect(classifyExit(42)).toBe("infrastructure_error");
    expect(classifyExit(null)).toBe("infrastructure_error");
  });
});

describe("parseTimeoutMs", () => {
  test("supports ms / s / m / bare seconds", () => {
    expect(parseTimeoutMs("250ms")).toBe(250);
    expect(parseTimeoutMs("30s")).toBe(30_000);
    expect(parseTimeoutMs("2m")).toBe(120_000);
    expect(parseTimeoutMs("15")).toBe(15_000);
  });

  test("returns undefined for empty or unparseable input", () => {
    expect(parseTimeoutMs(undefined)).toBeUndefined();
    expect(parseTimeoutMs("")).toBeUndefined();
    expect(parseTimeoutMs("forever")).toBeUndefined();
  });

  test("returns undefined when the suffix matches but the prefix is not numeric", () => {
    // Regression: this used to leak `NaN` into spawnSync's timeout option.
    expect(parseTimeoutMs("abcms")).toBeUndefined();
    expect(parseTimeoutMs("abcs")).toBeUndefined();
    expect(parseTimeoutMs("abcm")).toBeUndefined();
  });
});

describe("serveIO", () => {
  test("classifies test_success on exit 0", async () => {
    const { out } = await drive(
      "/bin/true",
      [],
      JSON.stringify({ id: "ok", feature_json: "/x" }) + "\n",
    );
    const resp = JSON.parse(out.trim());
    expect(resp.outcome).toBe("test_success");
    expect(resp.id).toBe("ok");
    expect(resp.duration).toBeGreaterThanOrEqual(0);
  });

  test("classifies test_failure on exit 1", async () => {
    const { out } = await drive(
      "/bin/false",
      [],
      JSON.stringify({ id: "f", feature_json: "/x" }) + "\n",
    );
    expect(JSON.parse(out.trim()).outcome).toBe("test_failure");
  });

  test("classifies timeout as infrastructure_error", async () => {
    const { out } = await drive(
      "/bin/sleep",
      ["2"],
      JSON.stringify({ id: "t", feature_json: "/x", timeout: "100ms" }) + "\n",
    );
    expect(JSON.parse(out.trim()).outcome).toBe("infrastructure_error");
  });

  test("classifies spawn failure as infrastructure_error", async () => {
    const { out } = await drive(
      "/this/does/not/exist",
      [],
      JSON.stringify({ id: "s", feature_json: "/x" }) + "\n",
    );
    expect(JSON.parse(out.trim()).outcome).toBe("infrastructure_error");
  });

  test("skips blank lines and reports bad JSON on stderr", async () => {
    const { out, err } = await drive(
      "/bin/true",
      [],
      `\n   \n{not valid}\n${JSON.stringify({ id: "x", feature_json: "/x" })}\n`,
    );
    const lines = out.trim().split("\n").filter(Boolean);
    expect(lines.length).toBe(1);
    expect(err).toContain("bad job line");
  });

  test("injects APS_IR_PATH so generated tests can find the mutated IR", async () => {
    const { out } = await drive(
      "/bin/sh",
      ["-c", 'printf "%s" "$APS_IR_PATH"'],
      JSON.stringify({ id: "e", feature_json: "/path/to/mutated.json" }) + "\n",
    );
    const resp = JSON.parse(out.trim());
    expect(resp.outcome).toBe("test_success");
    expect(resp.output).toBe("/path/to/mutated.json");
  });

  test("handles multiple jobs in one session", async () => {
    const input = ["a", "b", "c"]
      .map((id) => JSON.stringify({ id, feature_json: "/x" }))
      .join("\n") + "\n";
    const { out } = await drive("/bin/true", [], input);
    const ids = out
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line).id);
    expect(ids).toEqual(["a", "b", "c"]);
  });
});
