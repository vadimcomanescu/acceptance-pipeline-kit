// Generator metadata helpers. Mirrors specs/acceptance-generator.md.
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

export const SCHEMA_VERSION = 1;

export function metadataFilename(featurePath: string): string {
  const lowered = featurePath.toLowerCase();
  const hyphenated = lowered.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return `${hyphenated}.json`;
}

export function implementationHash(generatedFiles: string[]): string {
  const sorted = [...generatedFiles].sort();
  const h = createHash("sha256");
  for (const file of sorted) {
    h.update(file);
    h.update(Buffer.from([0]));
    h.update(readFileSync(file));
    h.update(Buffer.from([0]));
  }
  return `sha256:${h.digest("hex")}`;
}

export interface MetadataInput {
  metadataPath: string;
  featurePath: string;
  irPath: string;
  generatedFiles: string[];
}

export function writeMetadata(input: MetadataInput): void {
  mkdirSync(dirname(input.metadataPath), { recursive: true });
  const payload = {
    schema_version: SCHEMA_VERSION,
    feature_path: input.featurePath,
    ir_path: input.irPath,
    implementation_hash: implementationHash(input.generatedFiles),
    hash_scope: "generated_files",
    generated_files: input.generatedFiles,
  };
  writeFileSync(input.metadataPath, JSON.stringify(payload, null, 2) + "\n", "utf-8");
}
