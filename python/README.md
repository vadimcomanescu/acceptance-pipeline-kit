# aps-kit (Python)

Python scaffolding for the Acceptance Pipeline Specification.

## What this package provides

- `aps_kit.runtime.run_execution(ir_path, scenario_index, example_index, registry=None)`
  — load IR, prepend background, run scenario steps through the registered
  handlers. Designed to be called from generated pytest functions.
- `aps_kit.registry.default_registry` — global `Registry`. Project handlers
  register against it with `@default_registry.step("the result is <result>")`.
- `aps-generate` CLI — reads JSON IR, writes a pytest module and
  `metadata/<feature-metadata-name>.json` per the APS generator spec.
- `aps-adapter` CLI — persistent NDJSON worker that gherkin-mutator launches
  via `--runner-worker`. Each job swaps `APS_IR_PATH` for the worker's
  generated tests so the same test code executes mutated IRs.

## Install

```
cd python
pip install -e .[test]
~/Code/acceptance-pipeline-kit/scripts/install-aps-tools.sh   # gherkin-parser, gherkin-mutator
```

## End-to-end demo

```
cd python/examples/calculator
../../scripts/acceptance.sh
```

What you'll see: `gherkin-parser` writes `build/acceptance/calculator.json`,
`aps-generate` writes `acceptance/generated/calculator_acceptance_test.py`,
and pytest runs five test functions (three addition rows + two subtraction
rows).

## Project layout this expects

```
project-root/
  features/*.feature         your Gherkin files
  handlers/                  any package that registers handlers on import
  conftest.py                imports the handlers module so pytest collects steps
  acceptance/generated/      created by aps-generate (gitignored)
  build/acceptance/          created by gherkin-parser (gitignored)
```

## Conformance notes

- The generator emits one function per (scenario, example), named
  `test_scenario_<sIdx>_<scenario>_example_<eIdx>` (1-based example index).
- Generated functions read the IR from `APS_IR_PATH` at run time; the default
  is the IR path that was current when `aps-generate` ran. The adapter
  overrides this env var per mutator job so the same generated module runs
  every mutated IR.
- `metadata/<feature-metadata-name>.json` follows the lowercase-and-hyphen
  filename mapping and records `implementation_hash` over the generated test
  files only.
- The adapter classifies pytest's exit code 0 as `test_success`, 1 as
  `test_failure`, every other exit code as `infrastructure_error`. Timeouts
  also become `infrastructure_error`.
