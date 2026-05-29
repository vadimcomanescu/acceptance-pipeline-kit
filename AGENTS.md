# AGENTS.md

Guidance for AI coding agents working in or with this repo.

## What this repo is

Per-language scaffolding for the [Acceptance Pipeline Specification][aps]
(APS). Uncle Bob's upstream repo ships two portable Go binaries
(`gherkin-parser`, `gherkin-mutator`) and a written spec for the per-project
components. This kit implements those per-project components for **Python,
TypeScript, Go, and Rust** so a project in any of those four languages can
adopt APS without rewriting the same glue.

The spec docs are vendored under [`specs/`](specs/) and are authoritative. If
this kit diverges from the spec, fix the kit.

[aps]: https://github.com/unclebob/Acceptance-Pipeline-Specification

## Reading order

1. [`specs/APS-README.md`](specs/APS-README.md) — overall pipeline shape and
   component map.
2. [`specs/parser-spec.md`](specs/parser-spec.md) — JSON IR shape this kit
   consumes.
3. [`specs/acceptance-generator.md`](specs/acceptance-generator.md) — generator
   command, runtime contract, step handler contract, metadata format,
   implementation hash rules. **This is the spec this kit primarily honors.**
4. [`specs/mutator-spec.md`](specs/mutator-spec.md) — mutator behavior and
   runner-adapter protocol. **The runner adapter in this kit honors the
   adapter contract from this doc.**

## Layout

Per-language subdir shape is identical:

```
<lang>/
  <library>                               IR loader, runtime, step-handler registry
  cmd/acceptance-entrypoint-generator/    APS-conformant generator CLI
  cmd/aps-adapter/                        runner adapter (persistent NDJSON worker)
  examples/calculator/                    end-to-end demo
  scripts/acceptance.sh                   normal acceptance pipeline
  scripts/acceptance-mutation.sh          acceptance-mutation pipeline
```

`features/calculator.feature` at the root is the shared example feature. Each
language's example uses the same source feature so behavior matches across
implementations.

## Helping a user adopt this kit

When a user asks for "add acceptance tests to my project using APS", do this:

1. Identify the project's language (Python, TS, Go, or Rust).
2. Install the prebuilt APS binaries with `./install.sh` (from a clone, or pipe
   the repo's `install.sh` to `sh`). It downloads and checksum-verifies
   `gherkin-parser` and `gherkin-mutator` into `$HOME/.local/bin` (override with
   `--bin-dir`, pin a release with `--version <tag>`). **No Go toolchain is
   required** for non-Go projects — the binaries are prebuilt downloads, never
   compiled on the user's machine. (The from-source `scripts/install-aps-tools.sh`
   is a contributor/maintainer fallback — see the appendix below.)
3. Install the kit for the user's language (see the per-language README).
4. Write `features/*.feature` per the APS subset (see
   [`specs/parser-spec.md`](specs/parser-spec.md)) — supported keywords are
   `Feature:`, `Background:`, `Scenario:`, `Scenario Outline:`, `Examples:`,
   plus `Given/When/Then/And` step keywords. No tags, no rules, no doc strings.
5. Implement step handlers in the user's language using the kit's `Registry`
   pattern. **Match step text exactly.**
6. Wire the handlers to be imported before the generated tests run:
   - **Python:** `conftest.py` imports the handlers module.
   - **TypeScript:** `vitest.config.ts` lists the handlers file in
     `setupFiles`.
   - **Go:** create one `<dir>_test.go` file inside `acceptance/generated/`
     that blank-imports the handlers package.
   - **Rust:** the project's crate exposes `pub fn register()`; the
     generator-emitted test file calls it via `std::sync::Once`.
7. Run `<lang>/scripts/acceptance.sh` from the project root.

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

## Verification

For any change to a language directory, run that language's
`scripts/acceptance.sh` against the calculator example and confirm tests
pass. Mutation runs (`scripts/acceptance-mutation.sh`) require the APS
binaries on PATH; install them with `./install.sh`.

A useful smoke test after touching the runtime or adapter: run
`LEVEL=full acceptance-mutation.sh` and confirm all candidate mutations are
killed. Surviving mutations against the calculator example almost always
indicate a bug in the kit, not in the example.

## Contributor / maintainer: build the APS binaries from source

Consumers should install the binaries via the prebuilt `./install.sh` path
above. Contributors working on the kit and the release maintainer can instead
build `gherkin-parser`/`gherkin-mutator` from upstream source with
`scripts/install-aps-tools.sh` (requires a Go toolchain; installs into
`$GOBIN`). This is a fallback, not the default adopt path.

Releases are cut entirely by CI on a pushed semver tag — the only manual step
is the maintainer running `git tag vX.Y.Z && git push --tags`, after which the
workflow cross-compiles and attaches the binaries (with checksums) and the
`@aps-kit/typescript` tarball to a GitHub Release using only `GITHUB_TOKEN`.
