# acceptance-pipeline-kit

Per-language scaffolding for the [Acceptance Pipeline Specification][aps] (APS).

APS supplies two portable Go binaries — `gherkin-parser` and `gherkin-mutator` —
plus a written spec for the project-specific pieces. This kit ships those
project-specific pieces (entrypoint generator, runtime, step-handler base,
runner adapter, convenience scripts) for **Python**, **TypeScript**, **Go**, and
**Rust**, so any project in those languages can adopt APS without rewriting the
adapter layer.

Bring your own parser + mutator (installed from APS — see
[scripts/install-aps-tools.sh](scripts/install-aps-tools.sh)).

[aps]: https://github.com/unclebob/Acceptance-Pipeline-Specification

## What's in here

```
specs/                 vendored copy of the APS spec docs (read these first)
features/              shared sample Gherkin used by every language's example
scripts/               install-aps-tools.sh fetches the Go binaries from APS
python/                Python implementation + example calculator project
typescript/            TypeScript implementation + example calculator project
go/                    Go implementation + example calculator project
rust/                  Rust implementation + example calculator project
```

Per-language layout follows the same shape:

```
<lang>/
  <library code>        IR loader, runtime, step-handler registry
  cmd/aps-generate/     entrypoint generator CLI (acceptance-entrypoint-generator)
  cmd/aps-adapter/      runner adapter (persistent NDJSON worker for the mutator)
  examples/calculator/  end-to-end demo using features/calculator.feature
  scripts/              acceptance.sh and acceptance-mutation.sh
```

## The pipeline

Normal acceptance run:

```
features/foo.feature
    -> gherkin-parser            (Go binary from APS)
    -> build/acceptance/foo.json
    -> aps-generate              (this kit, per language)
    -> generated test entry points + metadata/<feature-name>.json
    -> project test runner       (pytest / vitest / go test / cargo test)
```

Acceptance-mutation run:

```
features/foo.feature
    -> gherkin-parser
    -> base JSON IR
    -> aps-generate              (once, reused across mutations)
    -> gherkin-mutator           (Go binary from APS)
        -> launches aps-adapter as a persistent worker
        -> sends mutated IR over stdin/stdout
        -> classifies killed / survived / error
    -> mutation report
```

See [specs/APS-README.md](specs/APS-README.md) and the spec docs alongside it
for the contract every component honors.

## Quick start

Install the APS Go binaries once:

```
scripts/install-aps-tools.sh
```

Then pick a language and follow its README. Each example calculator runs from a
single `acceptance.sh` script that exercises the full normal pipeline.

## Status

| Language   | Runtime | Generator | Adapter | Example   |
| ---------- | ------- | --------- | ------- | --------- |
| Python     | yes     | yes       | yes     | yes       |
| TypeScript | yes     | yes       | yes     | yes       |
| Go         | yes     | yes       | yes     | yes       |
| Rust       | yes     | yes       | yes     | yes       |

Everything is intentionally minimal — enough to satisfy the APS conformance
checklists and run the bundled calculator end-to-end. Project step handlers,
world types, and assertion idioms remain the project's responsibility.

## License

MIT — see [LICENSE](LICENSE).
