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

**No Go toolchain required.** The two upstream binaries arrive as prebuilt,
checksum-verified downloads, and the kit installs from a release-hosted tarball
— no clone and no npm registry credential.

1. **Install the prebuilt APS binaries.** Run `./install.sh` from a clone of
   this repo (or pipe the repo's `install.sh` to `sh`). It detects your
   OS/arch, downloads `gherkin-parser` and `gherkin-mutator` from the GitHub
   Release, checksum-verifies them, and installs them into `$HOME/.local/bin`
   (override with `--bin-dir`, pin a release with `--version <tag>`).

   ```bash
   ./install.sh
   # pin a specific release:
   ./install.sh --version v0.1.0
   ```

   Make sure the install dir (`$HOME/.local/bin` by default) is on your `PATH`.

2. **Install the TypeScript kit from the release tarball — no clone, no npm
   token.** The `@aps-kit/typescript` tarball is attached to the GitHub Release
   (it rides the same Release as the binaries), so install it by URL:

   ```bash
   npm install https://github.com/vadimcomanescu/acceptance-pipeline-kit/releases/download/v0.1.0/aps-kit-typescript-0.1.0.tgz
   ```

   The release tag is `v` + the package version; the tarball filename is the
   package version **without** the `v` (npm pack names it
   `aps-kit-typescript-<version>.tgz`). For another release, substitute both
   (e.g. tag `v0.2.0` → `aps-kit-typescript-0.2.0.tgz`). The kit has no runtime
   dependencies. (`@aps-kit/typescript` is **not** published to the npm
   registry; the Release tarball is the install source.)

For local development against a checkout, use
`cd typescript && npm install && npm run build`.

(Contributors and the release maintainer can build the binaries from source
instead — see the [contributor appendix](#contributor--maintainer-build-the-aps-binaries-from-source).)

## Try the demo

```bash
cd typescript/examples/calculator
npm install
../../scripts/acceptance.sh
```

Expected: five tests pass.

## Adopt in your own project

1. **Install the kit and APS binaries** (steps above; once per machine).

2. **Add the kit as a dev dependency.** Use the same release-tarball
   `npm install` from the [Install](#install) section, adding `--save-dev`.
   For local development against a checkout you can instead point at the
   directory: `npm install --save-dev /path/to/acceptance-pipeline-kit/typescript`.

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

## Contributor / maintainer: build the APS binaries from source

The prebuilt `./install.sh` path above is the recommended way to get
`gherkin-parser`/`gherkin-mutator`. Contributors and the maintainer can instead
build them from upstream source:

```bash
/path/to/acceptance-pipeline-kit/scripts/install-aps-tools.sh  # requires a Go toolchain
```

This clones the upstream APS repo and builds both binaries into `$GOBIN`. Add
`$GOBIN` to your `PATH`. This is a fallback for development on the kit, not the
default install path for a TypeScript project.
