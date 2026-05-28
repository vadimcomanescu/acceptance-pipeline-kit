# @aps-kit/typescript

TypeScript scaffolding for the [Acceptance Pipeline Specification][aps].

[aps]: https://github.com/unclebob/Acceptance-Pipeline-Specification

## What you get

- `runExecution(irPath, scenarioIndex, exampleIndex, registry?)` — the runtime
  called from generated vitest tests. Loads the IR, prepends background steps,
  dispatches each step to the registered handler with a fresh `world` object.
- `defaultRegistry` — a process-wide `Registry`. Project handlers register
  against it with `defaultRegistry.step("the result is <result>", (world, ex)
  => { ... })`.
- `acceptance-entrypoint-generator` (CLI) — APS-conformant: takes two
  positional args (`<json-ir> <generated-test-output>`). Emits a vitest test
  module and `metadata/<feature-metadata-name>.json`.
- `aps-adapter` (CLI) — persistent NDJSON worker that `gherkin-mutator`
  launches via `--runner-worker`.

## Install

```bash
cd typescript
npm install
npm run build
/path/to/acceptance-pipeline-kit/scripts/install-aps-tools.sh
```

## Try the demo

```bash
cd typescript/examples/calculator
npm install
../../scripts/acceptance.sh
```

Expected: five tests pass.

## Adopt in your own project

1. **Install the kit and APS binaries** (steps above; once per machine).

2. **Add the kit as a dev dependency.**

   ```bash
   npm install --save-dev /path/to/acceptance-pipeline-kit/typescript
   ```

3. **Write a feature file** under `features/`.

4. **Write handlers** that match each step text exactly.

   ```ts
   // handlers/orders-handlers.ts
   import { defaultRegistry } from "@aps-kit/typescript";
   import { strict as assert } from "node:assert";

   defaultRegistry.step("an empty cart", (world) => {
     world.cart = new Cart();
   });
   defaultRegistry.step("I add <quantity> of <sku>", (world, ex) => {
     (world.cart as Cart).add(ex.sku, parseInt(ex.quantity, 10));
   });
   defaultRegistry.step("the cart total is <total>", (world, ex) => {
     assert.equal((world.cart as Cart).total().toString(), ex.total);
   });
   ```

5. **Wire vitest to import the handlers** before the generated tests run.

   ```ts
   // vitest.config.ts
   import { defineConfig } from "vitest/config";

   export default defineConfig({
     test: {
       include: ["acceptance/generated/**/*.test.ts"],
       setupFiles: ["./handlers/orders-handlers.ts"],
     },
   });
   ```

6. **Run the pipeline.**

   ```bash
   /path/to/acceptance-pipeline-kit/typescript/scripts/acceptance.sh
   ```

7. **Optionally run mutation:**

   ```bash
   FEATURE=features/orders.feature \
     /path/to/acceptance-pipeline-kit/typescript/scripts/acceptance-mutation.sh
   ```

## Expected project layout

```
your-project/
  package.json
  vitest.config.ts           setupFiles lists your handlers
  features/*.feature
  handlers/*.ts              register defaultRegistry.step(...) handlers
  acceptance/generated/      created by the generator (gitignore this)
  build/acceptance/          created by gherkin-parser (gitignore this)
```

## Script options

Same env vars as the Python script: `FEATURES_DIR`, `IR_DIR`, `GENERATED_DIR`,
`FEATURE`, `WORK_DIR`, `LEVEL`. Extra arguments pass through to `vitest run`
or `gherkin-mutator`.

## Generator CLI shape

```
acceptance-entrypoint-generator <json-ir> <generated-test-output>
```

Env: `APS_FEATURE_PATH` overrides the feature path recorded in metadata.
Exit codes: `0` success, `1` IO/generation error, `2` usage error.

## Conformance notes

- The generator emits one `test()` call per (scenario, example) named
  `scenario_<sIdx>_<scenario>_example_<eIdx>` (1-based example index).
- Generated tests read the IR from `APS_IR_PATH` at run time.
- `metadata/<feature-metadata-name>.json` follows the lowercase-and-hyphen
  filename mapping and records `implementation_hash` over the generated test
  files only.
- The adapter classifies vitest exit code 0 as `test_success`, 1 as
  `test_failure`, every other exit code as `infrastructure_error`. Timeouts
  become `infrastructure_error`.
