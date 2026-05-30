# AGENTS.md

Guidance for AI coding agents working in or with this repo.

Per-language scaffolding (Python, TypeScript, Go, Rust) for the
[Acceptance Pipeline Specification][aps] (APS). The kit implements the
per-project layer — entrypoint generator, runtime, step-handler registry,
runner adapter, convenience scripts — around the two upstream Go binaries
(`gherkin-parser`, `gherkin-mutator`). The spec docs vendored under
[`specs/`](specs/) are authoritative; **if the kit diverges from the spec, fix
the kit, not the spec.**

This file carries only what an agent must not get wrong: the invariants below,
how to verify, and the error-prone wiring step. For everything descriptive, see
the README:

- Orientation, pipeline diagram, repository layout, adoption walkthrough —
  [README.md](README.md).
- Spec reading order — [README → Reading the spec](README.md#reading-the-spec).
- Build binaries from source / cut a release —
  [README → appendix](README.md#appendix-contributors-and-maintainers).

[aps]: https://github.com/unclebob/Acceptance-Pipeline-Specification

## Rules

- **MUST** treat the APS spec docs in `specs/` as authoritative. If something
  diverges, fix this kit, not the spec.
- **MUST NOT** reimplement parsing or mutation in any language directory.
  Those jobs belong to the upstream Go binaries.
- **MUST** keep the four language implementations behaviorally aligned. A
  change to runtime semantics in one language **SHOULD** land in the others in
  the same commit when feasible, or open a follow-up.
- The generator binary **MUST** be named `acceptance-entrypoint-generator` in
  all four languages.
- The generator **MUST** accept exactly two positional arguments: `<json-ir>
  <generated-test-output>`. Language-specific configuration goes through env
  vars: `APS_FEATURE_PATH`, `APS_PACKAGE` (Go), `APS_HANDLERS_CRATE` (Rust).
- The runner adapter **MUST** speak the NDJSON protocol from
  [`specs/mutator-spec.md`](specs/mutator-spec.md). Diagnostics go to stderr;
  only protocol responses go to stdout.
- The generator **MUST** be deterministic for a fixed IR and **MUST** write
  `metadata/<feature-metadata-name>.json` with `implementation_hash` covering
  only generated test files (not handlers, runtime, adapter, parser, mutator,
  or application sources).
- Convenience scripts **MUST** run end-to-end without requiring a checkout of
  the upstream APS repo at runtime — they call the installed `gherkin-parser`
  and `gherkin-mutator` binaries from `PATH`.
- When adding a new language: copy the existing layout, satisfy the same
  conformance checklists, add a row to the status table in the top-level
  README.

## Handler wiring (the error-prone step)

To help a user adopt the kit, follow the per-language README; the **Rules**
above are the invariants you must not break. The one step that is easy to get
wrong is wiring handlers to load **before** the generated tests run:

- **Python:** `conftest.py` imports the handlers module.
- **TypeScript:** `vitest.config.ts` lists the handlers file in `setupFiles`.
- **Go:** create one `<dir>_test.go` file inside `acceptance/generated/` that
  blank-imports the handlers package.
- **Rust:** the project's crate exposes `pub fn register()`; the
  generator-emitted test file calls it via `std::sync::Once`.

## Verification

For any change to a language directory, run that language's
`scripts/acceptance.sh` against the calculator example and confirm tests
pass. Mutation runs (`scripts/acceptance-mutation.sh`) require the APS
binaries on PATH; install them with `./install.sh`.

A useful smoke test after touching the runtime or adapter: run
`LEVEL=full acceptance-mutation.sh` and confirm all candidate mutations are
killed. Surviving mutations against the calculator example almost always
indicate a bug in the kit, not in the example.
