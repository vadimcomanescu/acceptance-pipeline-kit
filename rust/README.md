# aps-kit (Rust)

Rust scaffolding for the [Acceptance Pipeline Specification][aps].

[aps]: https://github.com/unclebob/Acceptance-Pipeline-Specification

## What you get

- `aps_kit::run_execution(ir_path, scenario_index, example_index, registry)` —
  the runtime called from generated `tests/*_acceptance.rs` integration tests.
  Loads the IR, prepends background steps, dispatches each step to the
  registered handler with a fresh `World` (a `serde_json::Value::Object`).
- `aps_kit::default_registry()` — process-wide registry. Project crates expose
  a `pub fn register()` that registers handlers; the generated tests call it
  once through `std::sync::Once`.
- `acceptance-entrypoint-generator` (binary) — APS-conformant: takes two
  positional args (`<json-ir> <generated-test-output>`). Emits a
  `tests/<feature>_acceptance.rs` integration test and
  `metadata/<feature-metadata-name>.json`.
- `aps-adapter` (binary) — persistent NDJSON worker that `gherkin-mutator`
  launches via `--runner-worker`.

## Install

```bash
cd rust
cargo install --path aps-kit
/path/to/acceptance-pipeline-kit/scripts/install-aps-tools.sh
# ensure ~/.cargo/bin is on PATH
```

## Try the demo

```bash
cd rust/examples/calculator
HANDLERS_CRATE=calculator ../../scripts/acceptance.sh
```

Expected: five tests pass.

## Adopt in your own project

1. **Install the kit and APS binaries** (steps above; once per machine).

2. **Add aps-kit as a dependency** in your project's `Cargo.toml`.

   ```toml
   [dependencies]
   aps-kit = { path = "/path/to/acceptance-pipeline-kit/rust/aps-kit" }
   ```

3. **Write a feature file** under `features/`.

4. **Expose `pub fn register()` from your crate** so generated tests can call
   it.

   ```rust
   // src/lib.rs
   use std::sync::Once;
   use aps_kit::registry::{default_registry, Example, StepError, World};

   static REGISTERED: Once = Once::new();

   pub fn register() {
       REGISTERED.call_once(|| {
           let reg = default_registry();
           reg.step("an empty cart", |world, _ex| {
               world.as_object_mut().unwrap().insert("total".into(), 0.into());
               Ok(())
           });
           reg.step("I add <quantity> of <sku>", |world, ex: &Example| {
               let qty: i64 = ex["quantity"].parse().map_err(|e| StepError::Failure(format!("{e}")))?;
               // ...
               Ok(())
           });
           reg.step("the cart total is <total>", |world, ex: &Example| {
               // assertion logic
               Ok(())
           });
       });
   }
   ```

5. **Run the pipeline,** telling the generator which crate exposes
   `register()`:

   ```bash
   HANDLERS_CRATE=your_crate_name \
     /path/to/acceptance-pipeline-kit/rust/scripts/acceptance.sh
   ```

   Cargo crate names with `-` become `_` here (e.g. `my-app` →
   `HANDLERS_CRATE=my_app`); the script handles that translation.

6. **Optionally run mutation:**

   ```bash
   FEATURE=features/orders.feature \
   HANDLERS_CRATE=your_crate_name \
     /path/to/acceptance-pipeline-kit/rust/scripts/acceptance-mutation.sh
   ```

## Expected project layout

```
your-project/
  Cargo.toml
  src/lib.rs                  pub fn register() registers with aps_kit::default_registry()
  features/*.feature
  tests/
    *_acceptance.rs           generated (gitignore these)
    metadata/                 generated (gitignore this)
  build/acceptance/           created by gherkin-parser (gitignore this)
```

## Script options

Same env vars as the other languages: `FEATURES_DIR`, `IR_DIR`,
`GENERATED_DIR` (default `tests` here, since cargo's integration test
location), `FEATURE`, `WORK_DIR`, `LEVEL`, plus `HANDLERS_CRATE`. Extra
arguments pass through to `cargo test` or `gherkin-mutator`.

## Generator CLI shape

```
acceptance-entrypoint-generator <json-ir> <generated-test-output>
```

Env vars:

- `APS_FEATURE_PATH` overrides the feature path recorded in metadata.
- `APS_HANDLERS_CRATE` names the crate whose `register()` function the
  generated test imports (default: `handlers`).

Exit codes: `0` success, `1` IO/generation error, `2` usage error.

## Conformance notes

- The generator emits one `#[test] fn scenario_<sIdx>_<name>_example_<eIdx>`
  per (scenario, example).
- Generated tests read the IR via `APS_IR_PATH`; the fallback is the IR path
  current when the generator ran (relative paths work because `cargo test`
  runs integration test binaries with cwd = crate root).
- `metadata/<feature-metadata-name>.json` follows the lowercase-and-hyphen
  filename mapping and records `implementation_hash` over generated `.rs`
  files only.
- The adapter classifies `cargo test` exit code 0 as `test_success`, 1 as
  `test_failure`, any other non-zero or non-exit error as
  `infrastructure_error`. Timeouts become `infrastructure_error`.
