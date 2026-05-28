# acceptance-pipeline-kit

Per-language scaffolding for the [Acceptance Pipeline Specification][aps] (APS),
ready to drop into a Python, TypeScript, Go, or Rust project.

APS supplies two portable Go binaries — `gherkin-parser` and `gherkin-mutator`
— plus a written spec for the components that must be written per project.
This kit ships those per-project components (entrypoint generator, runtime,
step-handler base, runner adapter, convenience scripts) for four languages so
you don't have to rewrite the same plumbing every time.

[aps]: https://github.com/unclebob/Acceptance-Pipeline-Specification

## How the pipeline works

```
Normal acceptance:
   features/foo.feature
      -> gherkin-parser
      -> build/acceptance/foo.json          (JSON IR)
      -> acceptance-entrypoint-generator
      -> acceptance/generated/foo_acceptance_test.<ext>
      -> acceptance/generated/metadata/features-foo-feature.json
      -> project test runner (pytest / vitest / go test / cargo test)

Acceptance mutation:
   features/foo.feature
      -> gherkin-parser              (mutator runs this internally per mutation)
      -> base + mutated JSON IRs
      -> acceptance-entrypoint-generator   (once, against base IR)
      -> gherkin-mutator
            launches aps-adapter as a persistent NDJSON worker
            sends one mutation per line on stdin
            adapter runs the same generated tests with APS_IR_PATH=mutated IR
            classifies killed / survived / error
      -> mutation report + updated mutation manifest in the feature file
```

The five per-project pieces in this kit are exactly what APS describes:

| Piece | What it is |
| --- | --- |
| Acceptance entrypoint generator | CLI that turns JSON IR into language-native test files plus a metadata sidecar. |
| Acceptance runtime | Library function the generated tests call (loads IR, prepends background, dispatches steps). |
| Step handler base | A `Registry` you register handlers against by exact step text. |
| Runner adapter | A persistent process the mutator pipes mutated IRs into via stdin/stdout. |
| Convenience scripts | `acceptance.sh` and `acceptance-mutation.sh` per language. |

## Quick start (in your own project)

These steps are language-agnostic; pick the section under "Per-language setup"
for the language-specific commands.

1. **Install the APS Go binaries once.**

   ```
   /path/to/acceptance-pipeline-kit/scripts/install-aps-tools.sh
   ```

   This clones the upstream APS repo and builds `gherkin-parser` and
   `gherkin-mutator` into `$GOBIN`. Add `$GOBIN` to your `PATH`.

2. **Install the kit for your language** (see per-language setup below).

3. **Write a feature file** under `features/`:

   ```gherkin
   Feature: Calculator
     Background:
       Given a fresh calculator
     Scenario Outline: addition
       When I add <a> and <b>
       Then the result is <sum>
       Examples:
         | a | b | sum |
         | 1 | 2 | 3   |
   ```

4. **Write step handlers** that match each step text exactly. One per language
   uses your project's idiomatic registration mechanism — see the per-language
   README.

5. **Run the normal acceptance pipeline.**

   ```
   /path/to/acceptance-pipeline-kit/<lang>/scripts/acceptance.sh
   ```

   You'll see `gherkin-parser` produce JSON, the generator write a test file,
   and your test runner execute it.

6. **Optionally run acceptance mutation** to prove your tests actually catch
   bad example data.

   ```
   /path/to/acceptance-pipeline-kit/<lang>/scripts/acceptance-mutation.sh
   ```

   This drives `gherkin-mutator` against your generated tests through
   `aps-adapter`. A clean run writes a `mutation-stamp` and
   `acceptance-mutation-manifest-{begin,end}` block back into the feature
   file; both are spec-defined artifacts and should be committed.

## Per-language setup

Each language ships a fully working calculator example under
`<lang>/examples/calculator/`. Run that first to confirm the pipeline works on
your machine; then port the pattern into your real project.

### Python

```
pip install ./python
cd your-project
mkdir -p features handlers
# write features/*.feature and handlers/*.py
# in conftest.py: import your handlers module so it registers on import
~/.../acceptance-pipeline-kit/python/scripts/acceptance.sh
```

Full guide: [python/README.md](python/README.md).

### TypeScript

```
cd typescript && npm install && npm run build
cd your-project
npm install @aps-kit/typescript --save-dev   # or file: path until published
# write features/*.feature and handlers/*.ts
# in vitest.config.ts, list your handlers file in setupFiles
~/.../acceptance-pipeline-kit/typescript/scripts/acceptance.sh
```

Full guide: [typescript/README.md](typescript/README.md).

### Go

```
cd go && go install ./cmd/acceptance-entrypoint-generator ./cmd/aps-adapter
cd your-project
# write features/*.feature
# write handlers/*.go that register handlers from func init()
# write acceptance/generated/handlers_init_test.go (one-line blank import)
~/.../acceptance-pipeline-kit/go/scripts/acceptance.sh
```

Full guide: [go/README.md](go/README.md).

### Rust

```
cd rust && cargo install --path aps-kit
cd your-project
# write features/*.feature
# write src/lib.rs with pub fn register() that wires handlers
HANDLERS_CRATE=your_crate_name ~/.../acceptance-pipeline-kit/rust/scripts/acceptance.sh
```

Full guide: [rust/README.md](rust/README.md).

## Repository layout

```
specs/                 vendored copy of the APS spec docs (read these first)
features/              shared sample Gherkin used by every language's example
scripts/               install-aps-tools.sh builds the Go binaries from upstream
python/                Python implementation + calculator example
typescript/            TypeScript implementation + calculator example
go/                    Go implementation + calculator example
rust/                  Rust implementation + calculator example
```

Per-language directories all follow the same shape:

```
<lang>/
  <library code>                          IR loader, runtime, step-handler registry
  cmd/acceptance-entrypoint-generator/    APS-conformant generator CLI
  cmd/aps-adapter/                        runner adapter (persistent NDJSON worker)
  examples/calculator/                    end-to-end demo
  scripts/acceptance.sh                   normal acceptance pipeline
  scripts/acceptance-mutation.sh          acceptance-mutation pipeline
```

## Conformance to the APS spec

The kit is built strictly against the three spec docs vendored at
[`specs/`](specs/). Audit notes:

- **Command name**: the generator binary is named exactly
  `acceptance-entrypoint-generator` as the spec dictates, in all four
  languages.
- **Command shape**: the generator accepts exactly the two positional
  arguments `<json-ir> <generated-test-output>`. Language-specific
  configuration (feature path recorded in metadata, Go package name, Rust
  handlers crate) is read from `APS_FEATURE_PATH`, `APS_PACKAGE`, and
  `APS_HANDLERS_CRATE` env vars.
- **Exit codes**: `0` success, `1` IO/generation error, `2` usage error.
- **Metadata**: `schema_version: 1`, all required fields, filename
  normalization per spec (`features/Hunt The Wumpus.feature →
  features-hunt-the-wumpus-feature.json`), `implementation_hash` covers only
  generated test files.
- **Runtime contract**: fresh world per scenario execution, background steps
  prepended, exact-text step matching, all failure modes reported as test
  failures.
- **Worker protocol**: NDJSON, request and response shapes match the spec,
  stdout reserved for protocol responses, diagnostics on stderr, duration in
  nanoseconds.
- **Outcome classification**: exit 0 → `test_success`, exit 1 →
  `test_failure`, anything else (including timeout) →
  `infrastructure_error`.

Empirical proof: `gherkin-mutator`, installed unmodified from upstream, kills
15/15 mutations against both the Python and Go calculator examples.

## License

MIT — see [LICENSE](LICENSE).
