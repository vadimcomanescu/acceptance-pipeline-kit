# acceptance-pipeline-kit

Per-language scaffolding for the [Acceptance Pipeline Specification][aps] (APS),
ready to drop into a Python, TypeScript, Go, or Rust project.

## Who supplies what

The pipeline has three layers, each owned by a different place:

| Layer | What it is | Where it comes from |
| --- | --- | --- |
| Spec + Go binaries | The APS spec, plus `gherkin-parser` and `gherkin-mutator` | [upstream APS][aps] |
| Per-language scaffolding | Entrypoint generator, runtime, step-handler registry, runner adapter, convenience scripts | **this kit** |
| Feature files + step handlers | Your `.feature` files and the handlers that wire step text to your code | **your project** |

APS deliberately leaves the middle layer to each project (its README splits
"portable tools in this repository" from "project-specific components created
by agents"). This kit implements that middle layer once for four languages so
you don't rewrite the same plumbing every time.

"Acceptance mutation" here means what the spec says it means — quoting
[`specs/APS-README.md`](specs/APS-README.md):

> Acceptance mutation means mutating Gherkin example values in the
> specification-derived JSON IR. It does not mean conventional mutation testing
> of application source code.

[aps]: https://github.com/unclebob/Acceptance-Pipeline-Specification

## Contents

- [Who supplies what](#who-supplies-what)
- [How the pipeline works](#how-the-pipeline-works)
- [Reading the spec](#reading-the-spec)
- [Quick start](#quick-start-in-your-own-project)
- [Per-language setup](#per-language-setup)
- [Repository layout](#repository-layout)
- [Critical rules for writing step handlers](#critical-rules-for-writing-step-handlers)
- [Troubleshooting](#troubleshooting)
- [Multiple features and handler files](#multiple-features-and-handler-files)
- [Conformance to the APS spec](#conformance-to-the-aps-spec)
- [License](#license)

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

## Reading the spec

The spec docs are vendored under [`specs/`](specs/) and are authoritative. Read
them in this order:

1. [`specs/APS-README.md`](specs/APS-README.md) — pipeline shape and component map.
2. [`specs/parser-spec.md`](specs/parser-spec.md) — the JSON IR this kit consumes.
3. [`specs/acceptance-generator.md`](specs/acceptance-generator.md) — generator command, runtime contract, step-handler contract, metadata, hashing.
4. [`specs/mutator-spec.md`](specs/mutator-spec.md) — mutator behavior and the runner-adapter protocol.

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
`<lang>/examples/calculator/`. Install the kit for your language (per its full
guide), run that calculator example to confirm the pipeline works on your
machine, then port the pattern into your real project.

The per-language READMEs are the authoritative setup instructions — they carry
the exact install, handler, and wiring details, and they stay in sync with the
code. Each one covers: installing the kit for that language, writing handlers
with the idiomatic registration mechanism, wiring those handlers to load before
the generated tests, and running both the normal and mutation pipelines.

| Language | Run the calculator demo (after installing the kit — see guide) | Full guide |
| --- | --- | --- |
| Python | `cd python/examples/calculator && ../../scripts/acceptance.sh` | [python/README.md](python/README.md) |
| TypeScript | `cd typescript/examples/calculator && npm install && ../../scripts/acceptance.sh` | [typescript/README.md](typescript/README.md) |
| Go | `cd go/examples/calculator && ../../scripts/acceptance.sh` | [go/README.md](go/README.md) |
| Rust | `cd rust/examples/calculator && HANDLERS_CRATE=calculator ../../scripts/acceptance.sh` | [rust/README.md](rust/README.md) |

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

## Critical rules for writing step handlers

Every language follows the same four rules. Get these right and the pipeline
just works.

1. **Match step text exactly, with placeholders kept literal.** If your feature
   says `When I add <a> and <b>`, your handler registers against the literal
   string `"I add <a> and <b>"`. The runtime resolves `<a>` and `<b>` from the
   current example row at run time. Never substitute placeholders in your
   handler key.

2. **Example values are always strings.** The IR stores every example cell as
   a string, even when it looks like a number, boolean, date, or list. Handler
   code that does arithmetic, comparisons, or type-sensitive logic must parse
   the string itself (`int(ex["a"])` in Python, `parseInt(ex.a, 10)` in TS,
   etc.).

3. **Step parameter names in `<...>` must exactly match column names in the
   `Examples:` header.** Case-sensitive. A typo here surfaces as "missing
   example value" at run time.

4. **Use the `world` argument to carry state between steps within one
   scenario execution.** Each `Given/When/Then` is a separate function call;
   the only shared state across them is the `world` object. A fresh `world`
   is created for each (scenario, example) pair — never carry state in module
   globals.

## Troubleshooting

**`unsupported step: "..."`** — Your handler registration text does not match
the feature step text. Causes: typo, wrong placeholders, wrong whitespace.
Run `gherkin-parser features/foo.feature out.json && cat out.json` and copy
the `text` field byte-for-byte into your handler.

**`step "..." references missing example values: [...]`** — A `<placeholder>`
in your step text isn't a column name in the `Examples:` table. Check
spelling and case.

**Test passes but mutation shows surviving mutations.** Your `Then` step is
not actually asserting the example value. Make sure the handler reads
`ex[...]` and compares it to project state.

**`gherkin-parser: command not found` or similar.** Run
`scripts/install-aps-tools.sh` once and add `$(go env GOPATH)/bin` to your
`PATH`.

**Mutator says "worker exited" for every job.** The runner adapter died
before sending its first response. Most often: the test command inside
`--runner-worker` wasn't found, or the quoting got mangled. The kit's
acceptance-mutation scripts use the positional form (`aps-adapter pytest
acceptance/generated -q`) which is robust against the mutator's
whitespace-splitting of `--runner-worker`.

**Handlers aren't picked up — every step is "unsupported".** The handlers
module isn't being imported before the generated tests run. Re-check:
- **Python:** `conftest.py` at project root imports your handlers module.
- **TypeScript:** `vitest.config.ts` lists the handlers file in `setupFiles`.
- **Go:** `acceptance/generated/handlers_init_test.go` blank-imports your
  handlers package.
- **Rust:** your crate exposes `pub fn register()` and the generator was run
  with `APS_HANDLERS_CRATE=<your_crate>`.

## Multiple features and handler files

Drop additional `.feature` files into `features/`; the scripts process every
file in the directory and generate one test module per feature. Handler
registrations can also be split across multiple files — as long as each file
is loaded before tests run (per the wiring for your language above), every
registration anywhere in the project populates the one shared registry
(`default_registry` in Python/TypeScript, `apskit.DefaultRegistry` in Go,
`aps_kit::default_registry()` in Rust).

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
15/15 mutations (9 in `addition`, 6 in `subtraction`) against the calculator
example in **all four languages** — Python, TypeScript, Go, and Rust. Each
example commits the resulting `acceptance-mutation-manifest` back into its
feature file. Re-verify any language yourself with
`<lang>/scripts/acceptance-mutation.sh` after `scripts/install-aps-tools.sh`.

## License

MIT — see [LICENSE](LICENSE).
