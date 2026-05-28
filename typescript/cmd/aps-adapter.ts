#!/usr/bin/env node
// Usage: aps-adapter <test-cmd> [test-args...]
// All argv past argv[2] is the project's test command. The adapter sets
// APS_IR_PATH for each mutator job. This positional form survives
// `gherkin-mutator --runner-worker`, which splits on whitespace.
import { serve } from "../src/adapter.js";

function usage(): never {
  process.stderr.write("usage: aps-adapter <test-cmd> [test-args...]\n");
  process.exit(2);
}

async function main(argv: string[]): Promise<number> {
  const args = argv.slice(2);
  if (args.length === 0 || args[0] === "-h" || args[0] === "--help") {
    if (args.length === 0) usage();
    process.stderr.write("usage: aps-adapter <test-cmd> [test-args...]\n");
    return 0;
  }
  const [command, ...cmdArgs] = args;
  await serve({ command, args: cmdArgs });
  return 0;
}

main(process.argv).then((code) => process.exit(code));
