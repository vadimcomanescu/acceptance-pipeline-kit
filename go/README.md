# aps-kit (Go)

Go scaffolding for the Acceptance Pipeline Specification.

Module path: `github.com/vadimcomanescu/acceptance-pipeline-kit/go`.

## What this module provides

- `apskit.RunExecution(irPath, scenarioIndex, exampleIndex, reg)` — runtime
  called from generated `_test.go` functions.
- `apskit.DefaultRegistry` — process-wide registry. Project handler packages
  register steps from `func init() { ... }`.
- `aps-generate` (cmd) — reads JSON IR, writes a Go test file plus
  `metadata/<feature-metadata-name>.json` per the APS generator spec.
- `aps-adapter` (cmd) — persistent NDJSON worker spawned by gherkin-mutator.

## Install

```
cd go
go build ./...
go install ./cmd/aps-generate ./cmd/aps-adapter
~/Code/acceptance-pipeline-kit/scripts/install-aps-tools.sh
```

## End-to-end demo

```
cd go/examples/calculator
../../scripts/acceptance.sh
```

## Project layout this expects

```
project-root/
  go.mod
  features/*.feature
  handlers/                  init() registers steps with apskit.DefaultRegistry
  acceptance/generated/      generator output, plus one hand-written file:
    handlers_init_test.go    blank-imports the handlers package
```

The blank-import file is one line per project and gives the generated
`_test.go` package a stable hook back to your handlers. The generator does
not write it because the import path is project-specific.

## Conformance notes

- The generator emits one `Test_Scenario_<sIdx>_<Name>_Example_<eIdx>` per
  (scenario, example).
- Generated tests read the IR via `APS_IR_PATH`; the default falls back to the
  IR path that was current when `aps-generate` ran.
- `metadata/<feature-metadata-name>.json` follows the lowercase-and-hyphen
  filename mapping and records `implementation_hash` over the generated `_test.go`
  files only.
- The adapter classifies `go test` exit code 0 as `test_success`, 1 as
  `test_failure`, any other non-zero or non-exit error as
  `infrastructure_error`. Timeouts become `infrastructure_error`.
