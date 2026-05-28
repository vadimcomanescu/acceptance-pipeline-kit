# @aps-kit/typescript

TypeScript scaffolding for the Acceptance Pipeline Specification.

## What this package provides

- `runExecution(irPath, scenarioIndex, exampleIndex, registry?)` — load IR,
  prepend background, dispatch every step through the registered handlers.
- `defaultRegistry` — a `Registry`. Project handlers register against it with
  `defaultRegistry.step("the result is <result>", (world, example) => { ... })`.
- `aps-generate` CLI — reads JSON IR, writes a vitest test module and
  `metadata/<feature-metadata-name>.json` per the APS generator spec.
- `aps-adapter` CLI — persistent NDJSON worker that gherkin-mutator launches
  via `--runner-worker`. Each job swaps `APS_IR_PATH` for the worker's test
  command so the same generated tests run every mutated IR.

## Install

```
cd typescript
npm install
npm run build
~/Code/acceptance-pipeline-kit/scripts/install-aps-tools.sh
```

## End-to-end demo

```
cd typescript/examples/calculator
npm install
../../scripts/acceptance.sh
```

## Conformance notes

- The generator emits one `test()` call per (scenario, example) named
  `scenario_<sIdx>_<scenario>_example_<eIdx>` (1-based example index).
- Generated tests read the IR from `APS_IR_PATH` at run time; the default is
  the IR path that was current when `aps-generate` ran.
- `metadata/<feature-metadata-name>.json` follows the lowercase-and-hyphen
  filename mapping and records `implementation_hash` over the generated test
  files only.
- The adapter classifies vitest exit code 0 as `test_success`, 1 as
  `test_failure`, every other exit code as `infrastructure_error`. Timeouts
  become `infrastructure_error`.
