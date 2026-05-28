#!/usr/bin/env node
import { generate } from "../src/generator.js";

function usage(): never {
  process.stderr.write(
    "usage: aps-generate <json-ir> <output-dir> [--feature-path <path>]\n",
  );
  process.exit(2);
}

function main(argv: string[]): number {
  const args = argv.slice(2);
  let featurePath: string | undefined;
  const positional: string[] = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--feature-path") {
      featurePath = args[++i];
    } else {
      positional.push(args[i]);
    }
  }
  if (positional.length !== 2) usage();
  try {
    generate({ irPath: positional[0], outputDir: positional[1], featurePath });
    return 0;
  } catch (err) {
    process.stderr.write(`aps-generate: ${(err as Error).message}\n`);
    return 1;
  }
}

process.exit(main(process.argv));
