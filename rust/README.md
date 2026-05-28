# aps-kit (Rust)

Rust scaffolding for the Acceptance Pipeline Specification.

## What this crate provides

- `aps_kit::run_execution(ir_path, scenario_index, example_index, registry)` —
  runtime called from generated integration tests in `tests/`.
- `aps_kit::default_registry()` — process-wide registry. Project crates expose a
  `pub fn register()` that registers handlers; the generated tests call it once
  through `std::sync::Once`.
- `aps-generate` (binary) — reads JSON IR, writes a `tests/<feature>_acceptance.rs`
  integration test plus `metadata/<feature-metadata-name>.json`.
- `aps-adapter` (binary) — persistent NDJSON worker spawned by gherkin-mutator.

## Install

```
cd rust
cargo build --release
cargo install --path aps-kit
~/Code/acceptance-pipeline-kit/scripts/install-aps-tools.sh
```

## End-to-end demo

```
cd rust/examples/calculator
HANDLERS_CRATE=calculator ../../scripts/acceptance.sh
```

## Project layout this expects

```
project-root/
  Cargo.toml
  src/lib.rs         pub fn register() registers steps with aps_kit::default_registry()
  features/*.feature
  tests/             aps-generate writes integration test files here
```

`--handlers-crate <name>` (default `handlers`) tells the generator which crate
to import inside the generated `tests/` file. The example uses
`HANDLERS_CRATE=calculator` because the example crate is named `calculator`.

## Conformance notes

- The generator emits one `#[test] fn scenario_<sIdx>_<name>_example_<eIdx>` per
  (scenario, example).
- Generated tests read IR via `APS_IR_PATH`; default falls back to the IR path
  current when `aps-generate` ran.
- `metadata/<feature-metadata-name>.json` follows the lowercase-and-hyphen
  filename mapping and records `implementation_hash` over generated `.rs` files
  only.
- The adapter classifies `cargo test` exit code 0 as `test_success`, 1 as
  `test_failure`, any other non-zero or non-exit error as
  `infrastructure_error`. Timeouts become `infrastructure_error`.
