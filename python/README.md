# aps-kit (Python)

Python scaffolding for the [Acceptance Pipeline Specification][aps].

[aps]: https://github.com/unclebob/Acceptance-Pipeline-Specification

## What you get

- `aps_kit.run_execution(ir_path, scenario_index, example_index, registry=None)`
  — the runtime called from generated pytest functions. Loads the IR, prepends
  background steps, dispatches each step to the registered handler with a
  fresh `world` dict.
- `aps_kit.default_registry` — process-wide `Registry`. Project handlers
  register against it with
  `@default_registry.step("the result is <result>")`.
- `acceptance-entrypoint-generator` (CLI) — APS-conformant: takes two
  positional args (`<json-ir> <generated-test-output>`). Emits one pytest
  function per (scenario, example) plus
  `metadata/<feature-metadata-name>.json`.
- `aps-adapter` (CLI) — persistent NDJSON worker that `gherkin-mutator`
  launches via `--runner-worker`. Each job swaps `APS_IR_PATH` for the test
  command so the same generated tests execute every mutated IR.

## Install

**No Go toolchain required.** The two upstream binaries arrive as prebuilt,
checksum-verified downloads; only the kit itself is installed with `pip`.

1. **Install the prebuilt APS binaries.** Run `./install.sh` from a clone of
   this repo (or pipe the repo's `install.sh` to `sh`). It detects your
   OS/arch, resolves the latest GitHub Release, downloads `gherkin-parser` and
   `gherkin-mutator`, checksum-verifies them, and installs them into
   `$HOME/.local/bin` (override with `--bin-dir`, pin a release with
   `--version <tag>`). Supported installer platforms are Linux amd64/arm64 and
   macOS amd64/arm64.

   ```bash
   ./install.sh
   # pin a specific release:
   ./install.sh --version v0.1.0
   ```

   Make sure the install dir (`$HOME/.local/bin` by default) is on your `PATH`.

2. **Install the Python kit straight from git — no clone, no PyPI:**

   ```bash
   pip install "git+https://github.com/vadimcomanescu/acceptance-pipeline-kit@<tag>#subdirectory=python"
   ```

   Replace `<tag>` with a pushed release tag (e.g. `v0.1.0`) to pin the kit.

For local development against a checkout, use `cd python && pip install -e .[test]`.

(Contributors and the release maintainer can build the binaries from source
instead — see the [contributor appendix](#contributor--maintainer-build-the-aps-binaries-from-source).)

## Try the demo

```bash
cd python/examples/calculator
../../scripts/acceptance.sh
```

Expected: five tests pass (three addition rows + two subtraction rows). The
script runs `gherkin-parser → acceptance-entrypoint-generator → pytest`.

## Adopt in your own project

1. **Install the kit and APS binaries** (steps above; you only do this once
   per machine).

2. **Write a feature file** under `features/`.

   ```gherkin
   # features/orders.feature
   Feature: Orders

     Background:
       Given an empty cart

     Scenario Outline: add item
       When I add <quantity> of <sku>
       Then the cart total is <total>

       Examples:
         | sku   | quantity | total |
         | WIDGET| 2        | 19.98 |
   ```

3. **Write handlers** that match each step text exactly.

   ```python
   # handlers/orders_handlers.py
   from aps_kit import default_registry as registry

   @registry.step("an empty cart")
   def _(world, _ex):
       world["cart"] = Cart()

   @registry.step("I add <quantity> of <sku>")
   def _(world, ex):
       world["cart"].add(ex["sku"], int(ex["quantity"]))

   @registry.step("the cart total is <total>")
   def _(world, ex):
       assert world["cart"].total() == Decimal(ex["total"])
   ```

4. **Wire pytest to import the handlers** before the generated tests run.

   ```python
   # conftest.py at project root
   from handlers import orders_handlers  # noqa: F401
   ```

   Importing the module is enough — the `@registry.step(...)` decorators
   populate `default_registry` at import time.

5. **Run the pipeline.**

   ```bash
   /path/to/acceptance-pipeline-kit/python/scripts/acceptance.sh
   ```

6. **Optionally run mutation** to prove your assertions actually check the
   example data.

   ```bash
   FEATURE=features/orders.feature \
     /path/to/acceptance-pipeline-kit/python/scripts/acceptance-mutation.sh
   ```

## Expected project layout

```
your-project/
  conftest.py               imports your handlers module
  features/*.feature        your Gherkin files (one Feature per file)
  handlers/*.py             register @default_registry.step(...) handlers
  acceptance/generated/     created by the generator (gitignore this)
  build/acceptance/         created by gherkin-parser (gitignore this)
```

## Script options

`acceptance.sh` reads these env vars:

| Var | Default | Meaning |
| --- | --- | --- |
| `FEATURES_DIR` | `features` | directory containing `.feature` files |
| `IR_DIR` | `build/acceptance` | where `gherkin-parser` writes JSON IR |
| `GENERATED_DIR` | `acceptance/generated` | where generated pytest files land |

`acceptance-mutation.sh` adds:

| Var | Default | Meaning |
| --- | --- | --- |
| `FEATURE` | `features/calculator.feature` | the single feature file to mutate |
| `WORK_DIR` | `build/acceptance-mutation` | mutator working directory |
| `LEVEL` | `hard` | differential level: `full`, `hard`, or `soft` |

Any extra arguments are passed straight through to `pytest` or
`gherkin-mutator`.

## Generator CLI shape

Per APS, the generator takes exactly two positional arguments:

```
acceptance-entrypoint-generator <json-ir> <generated-test-output>
```

Environment variables:

- `APS_FEATURE_PATH` — feature path recorded in metadata. Defaults to the IR
  path; set it to the relative `features/foo.feature` so the metadata
  filename matches the spec's lowercase-and-hyphen convention.

Exit codes: `0` success, `1` IO/generation error, `2` usage error.

## Conformance notes

- The generator emits one `def test_scenario_<sIdx>_<scenario>_example_<eIdx>`
  function per (scenario, example). One-based example index.
- Generated tests read the IR from `APS_IR_PATH` at run time; the default is
  the IR path that was current when the generator ran. The adapter overrides
  this env var per mutator job.
- `metadata/<feature-metadata-name>.json` follows the lowercase-and-hyphen
  filename mapping and records `implementation_hash` over the generated test
  file only.
- The adapter classifies pytest exit code 0 as `test_success`, 1 as
  `test_failure`, every other exit code as `infrastructure_error`. Timeouts
  also become `infrastructure_error`.

## Contributor / maintainer: build the APS binaries from source

The prebuilt `./install.sh` path above is the recommended way to get
`gherkin-parser`/`gherkin-mutator`. Contributors and the maintainer can instead
build them from upstream source:

```bash
/path/to/acceptance-pipeline-kit/scripts/install-aps-tools.sh  # requires a Go toolchain
```

This clones the upstream APS repo and builds both binaries into `$GOBIN`. Add
`$GOBIN` to your `PATH`. This is a fallback for development on the kit, not the
default install path for a Python project.
