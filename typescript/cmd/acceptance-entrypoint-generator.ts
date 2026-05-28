#!/usr/bin/env node
// Per the APS acceptance-generator spec:
//   acceptance-entrypoint-generator <json-ir> <generated-test-output>
// Two positional arguments, nothing else. Configuration via env vars:
//   APS_FEATURE_PATH   feature path to record in metadata (default: <json-ir>)
import { generate } from "../src/generator.js";

const USAGE =
  "usage: acceptance-entrypoint-generator <json-ir> <generated-test-output>";

function main(argv: string[]): number {
  const args = argv.slice(2);
  if (args[0] === "-h" || args[0] === "--help") {
    process.stderr.write(USAGE + "\n");
    return 0;
  }
  if (args.length !== 2) {
    process.stderr.write(USAGE + "\n");
    return 2;
  }
  const [irPath, outputDir] = args;
  const featurePath = process.env.APS_FEATURE_PATH || undefined;
  try {
    generate({ irPath, outputDir, featurePath });
    return 0;
  } catch (err) {
    process.stderr.write(
      `acceptance-entrypoint-generator: ${(err as Error).message}\n`,
    );
    return 1;
  }
}

process.exit(main(process.argv));
