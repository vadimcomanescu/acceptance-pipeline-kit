#!/usr/bin/env bash
# Acceptance mutation pipeline:
#   1. gherkin-parser produces a base IR (handled internally by gherkin-mutator)
#   2. aps-generate writes generated tests + metadata into the mutator's
#      generated-dir
#   3. gherkin-mutator drives aps-adapter as a persistent worker.
set -euo pipefail

FEATURE="${FEATURE:-features/calculator.feature}"
WORK_DIR="${WORK_DIR:-build/acceptance-mutation}"
GENERATED_DIR="${GENERATED_DIR:-${WORK_DIR}/generated}"
LEVEL="${LEVEL:-hard}"

if ! command -v gherkin-mutator >/dev/null 2>&1; then
  echo "gherkin-mutator not on PATH. Install with scripts/install-aps-tools.sh." >&2
  exit 1
fi

# Prime the generated tests against the base IR. gherkin-mutator will re-parse
# the feature itself, but its workers need test entrypoints + metadata already
# present in GENERATED_DIR so the implementation hash can be verified.
mkdir -p "$WORK_DIR" "$GENERATED_DIR"
BASE_IR="${WORK_DIR}/base.json"
gherkin-parser "$FEATURE" "$BASE_IR"
aps-generate "$BASE_IR" "$GENERATED_DIR" --feature-path "$FEATURE"

exec gherkin-mutator \
  --feature "$FEATURE" \
  --work-dir "$WORK_DIR" \
  --generated-dir "$GENERATED_DIR" \
  --level "$LEVEL" \
  --runner-worker "aps-adapter pytest $GENERATED_DIR -q" \
  "$@"
