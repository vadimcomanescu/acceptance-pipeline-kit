import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import {
  SCHEMA_VERSION,
  implementationHash,
  metadataFilename,
  writeMetadata,
} from "../src/metadata.js";

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "aps-kit-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("metadataFilename", () => {
  test("normalizes spec examples", () => {
    expect(metadataFilename("features/Hunt The Wumpus.feature")).toBe(
      "features-hunt-the-wumpus-feature.json",
    );
    expect(metadataFilename("features/orders/Cancel Order.feature")).toBe(
      "features-orders-cancel-order-feature.json",
    );
    expect(metadataFilename("Features/API v2/Happy Path.feature")).toBe(
      "features-api-v2-happy-path-feature.json",
    );
  });
});

describe("implementationHash", () => {
  test("is stable under reorder and sensitive to content", () => {
    const a = join(dir, "a.txt");
    const b = join(dir, "b.txt");
    writeFileSync(a, "alpha");
    writeFileSync(b, "beta");
    const h1 = implementationHash([a, b]);
    const h2 = implementationHash([b, a]);
    expect(h1).toBe(h2);
    expect(h1.startsWith("sha256:")).toBe(true);
    writeFileSync(b, "gamma");
    expect(implementationHash([a, b])).not.toBe(h1);
  });
});

describe("writeMetadata", () => {
  test("emits the spec shape", () => {
    const generated = join(dir, "gen.ts");
    writeFileSync(generated, "// generated");
    const metadataPath = join(dir, "metadata", "features-orders-feature.json");
    writeMetadata({
      metadataPath,
      featurePath: "features/orders.feature",
      irPath: "build/acceptance/orders.json",
      generatedFiles: [generated],
    });
    const payload = JSON.parse(readFileSync(metadataPath, "utf-8"));
    expect(payload.schema_version).toBe(SCHEMA_VERSION);
    expect(payload.hash_scope).toBe("generated_files");
    expect(payload.implementation_hash.startsWith("sha256:")).toBe(true);
    expect(payload.feature_path).toBe("features/orders.feature");
    expect(payload.generated_files).toEqual([generated]);
  });
});
