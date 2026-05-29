# aps-kit (Go)

Go scaffolding for the [Acceptance Pipeline Specification][aps].

Module path: `github.com/vadimcomanescu/acceptance-pipeline-kit/go`.

[aps]: https://github.com/unclebob/Acceptance-Pipeline-Specification

## What you get

- `apskit.RunExecution(irPath, scenarioIndex, exampleIndex, registry)` — the
  runtime called from generated `*_acceptance_test.go` functions. Loads the
  IR, prepends background steps, dispatches each step to the registered
  handler with a fresh `World` map.
- `apskit.DefaultRegistry` — process-wide `*Registry`. Project handler
  packages register against it from `func init()`.
- `acceptance-entrypoint-generator` (binary) — APS-conformant: takes two
  positional args (`<json-ir> <generated-test-output>`). Emits a Go test file
  and `metadata/<feature-metadata-name>.json`.
- `aps-adapter` (binary) — persistent NDJSON worker that `gherkin-mutator`
  launches via `--runner-worker`.

## Install

1. **Install the prebuilt APS binaries.** Run `./install.sh` from a clone of
   this repo (or pipe the repo's `install.sh` to `sh`). It detects your
   OS/arch, resolves the latest GitHub Release, downloads `gherkin-parser` and
   `gherkin-mutator`, checksum-verifies them, and installs them into
   `$HOME/.local/bin` (override with `--bin-dir`, pin a release with
   `--version <tag>`). Supported installer platforms are Linux amd64/arm64 and
   macOS amd64/arm64. These two binaries are prebuilt downloads — they are
   never compiled on your machine.

   ```bash
   ./install.sh
   # pin a specific release:
   ./install.sh --version v0.1.0
   ```

   Make sure the install dir (`$HOME/.local/bin` by default) is on your `PATH`.

2. **Install the Go kit binaries from git.** Go projects already have the
   toolchain, so the kit's generator and adapter install with `go install`
   (no clone needed):

   ```bash
   go install github.com/vadimcomanescu/acceptance-pipeline-kit/go/cmd/acceptance-entrypoint-generator@<tag>
   go install github.com/vadimcomanescu/acceptance-pipeline-kit/go/cmd/aps-adapter@<tag>
   ```

   Replace `<tag>` with a pushed release tag (e.g. `v0.1.0`). Ensure
   `$(go env GOPATH)/bin` is on your `PATH`.

For local development against a checkout, use
`cd go && go install ./cmd/acceptance-entrypoint-generator ./cmd/aps-adapter`.

(Contributors and the release maintainer can build the parser/mutator from
source instead — see the [contributor appendix](#contributor--maintainer-build-the-aps-binaries-from-source).)

## Try the demo

```bash
cd go/examples/calculator
../../scripts/acceptance.sh
```

Expected: five tests pass.

## Adopt in your own project

1. **Install the kit and APS binaries** (steps above; once per machine).

2. **Add aps-kit as a module dependency.**

   ```bash
   go get github.com/vadimcomanescu/acceptance-pipeline-kit/go/apskit
   ```

3. **Write a feature file** under `features/`.

4. **Write handlers** in a package the generated tests can import, and
   register them from `init()`.

   ```go
   // handlers/handlers.go
   package handlers

   import "github.com/vadimcomanescu/acceptance-pipeline-kit/go/apskit"

   func init() {
       r := apskit.DefaultRegistry
       r.Step("an empty cart", func(world apskit.World, _ apskit.Example) error {
           world["cart"] = NewCart()
           return nil
       })
       r.Step("I add <quantity> of <sku>", func(world apskit.World, ex apskit.Example) error {
           qty, _ := strconv.Atoi(ex["quantity"])
           world["cart"].(*Cart).Add(ex["sku"], qty)
           return nil
       })
       r.Step("the cart total is <total>", func(world apskit.World, ex apskit.Example) error {
           if got := world["cart"].(*Cart).Total(); got.String() != ex["total"] {
               return fmt.Errorf("expected %s, got %s", ex["total"], got)
           }
           return nil
       })
   }
   ```

5. **Add a one-line blank-import file** inside the generated tests directory
   so its package wires up your handlers before any test runs.

   ```go
   // acceptance/generated/handlers_init_test.go (hand-written, not generated)
   package generated

   import _ "yourmodule/handlers"
   ```

   The generator never touches this file. The blank import triggers your
   `init()` so `DefaultRegistry` is populated when the generated tests run.

6. **Run the pipeline.**

   ```bash
   /path/to/acceptance-pipeline-kit/go/scripts/acceptance.sh
   ```

7. **Optionally run mutation:**

   ```bash
   FEATURE=features/orders.feature \
     /path/to/acceptance-pipeline-kit/go/scripts/acceptance-mutation.sh
   ```

## Expected project layout

```
your-project/
  go.mod
  features/*.feature
  handlers/                       init() registers steps with apskit.DefaultRegistry
  acceptance/generated/
    handlers_init_test.go         hand-written, one-line blank import
    *_acceptance_test.go          generated (gitignore these)
    metadata/                     generated (gitignore this)
  build/acceptance/               created by gherkin-parser (gitignore this)
```

## Script options

Same env vars as the Python script: `FEATURES_DIR`, `IR_DIR`, `GENERATED_DIR`,
`FEATURE`, `WORK_DIR`, `LEVEL`. Extra arguments pass through to `go test` or
`gherkin-mutator`.

## Generator CLI shape

```
acceptance-entrypoint-generator <json-ir> <generated-test-output>
```

Env vars:

- `APS_FEATURE_PATH` overrides the feature path recorded in metadata.
- `APS_PACKAGE` sets the Go package name for the generated test file
  (default: `generated`).

Exit codes: `0` success, `1` IO/generation error, `2` usage error.

## Conformance notes

- The generator emits one `Test_Scenario_<sIdx>_<Name>_Example_<eIdx>` per
  (scenario, example).
- Generated tests read the IR via `APS_IR_PATH`; the fallback is the absolute
  IR path captured when the generator ran. The script uses `realpath -m` so
  the test binary (which `go test` runs with cwd = package dir) can locate
  the IR.
- `metadata/<feature-metadata-name>.json` follows the lowercase-and-hyphen
  filename mapping and records `implementation_hash` over generated
  `*_acceptance_test.go` files only.
- The adapter classifies `go test` exit code 0 as `test_success`, 1 as
  `test_failure`, any other non-zero or non-exit error as
  `infrastructure_error`. Timeouts become `infrastructure_error`.

## Contributor / maintainer: build the APS binaries from source

The prebuilt `./install.sh` path above is the recommended way to get
`gherkin-parser`/`gherkin-mutator`. Contributors and the maintainer can instead
build them from upstream source:

```bash
/path/to/acceptance-pipeline-kit/scripts/install-aps-tools.sh
```

This clones the upstream APS repo and builds both binaries into `$GOBIN`. Add
`$GOBIN` to your `PATH`. This is a fallback for development on the kit, not the
default install path.
