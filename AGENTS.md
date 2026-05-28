# AGENTS.md

Guidance for AI coding agents working in this repo.

## What this repo is

A per-language scaffolding kit for the Acceptance Pipeline Specification
(APS, `github.com/unclebob/Acceptance-Pipeline-Specification`). The APS Go
binaries `gherkin-parser` and `gherkin-mutator` stay where they live; this kit
ships the project-specific layer (entrypoint generator, runtime, step-handler
base, runner adapter, convenience scripts) for Python, TypeScript, Go, and
Rust.

Read `specs/APS-README.md` first, then `specs/parser-spec.md`,
`specs/acceptance-generator.md`, `specs/mutator-spec.md`. Every component in
this repo answers to one of those documents.

## Layout

Each language subdir mirrors the same five concerns:

```
<lang>/
  <library>            IR loader, runtime, step-handler registry
  cmd/aps-generate     acceptance-entrypoint-generator CLI
  cmd/aps-adapter      runner adapter (persistent NDJSON worker)
  examples/calculator  end-to-end demo against ../features/calculator.feature
  scripts              acceptance.sh and acceptance-mutation.sh
```

`features/calculator.feature` at the root is the shared example. Every
language's example uses the same source feature so behavior matches across
implementations.

## Rules

- MUST treat the APS spec docs in `specs/` as authoritative. If something
  diverges, fix this kit, not the spec.
- MUST keep the four language implementations behaviorally aligned. A change
  to runtime semantics in one language SHOULD land in the others in the same
  commit when feasible, or open a follow-up.
- MUST NOT reimplement parsing or mutation in any language directory. Those
  jobs belong to the upstream Go binaries.
- The runner adapter MUST speak the NDJSON protocol from `specs/mutator-spec.md`.
  Diagnostics go to stderr; only protocol responses go to stdout.
- The entrypoint generator MUST be deterministic for a fixed IR and MUST
  write `metadata/<feature-metadata-name>.json` with `implementation_hash`
  covering only generated files.
- Convenience scripts MUST run end-to-end without requiring a checkout of the
  upstream APS repo at runtime — they call the installed `gherkin-parser` and
  `gherkin-mutator` binaries from PATH.
- When adding a new language: copy the existing layout, satisfy the same
  conformance checklists, add a row to the status table in the top-level
  README.

## Verification

For any change to a language directory, run that language's
`scripts/acceptance.sh` against the calculator example and confirm tests
pass. Mutation runs (`scripts/acceptance-mutation.sh`) require the APS
binaries on PATH; install with `scripts/install-aps-tools.sh`.
