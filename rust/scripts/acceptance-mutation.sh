#!/usr/bin/env bash
set -euo pipefail

FEATURE="${FEATURE:-features/calculator.feature}"
WORK_DIR="${WORK_DIR:-build/acceptance-mutation}"
GENERATED_DIR="${GENERATED_DIR:-tests}"
LEVEL="${LEVEL:-hard}"
HANDLERS_CRATE="${HANDLERS_CRATE:-$(basename "$(pwd)")}"
HANDLERS_CRATE="${HANDLERS_CRATE//-/_}"

if ! command -v gherkin-mutator >/dev/null 2>&1; then
  echo "gherkin-mutator not on PATH. Install with scripts/install-aps-tools.sh." >&2
  exit 1
fi

mkdir -p "$WORK_DIR" "$GENERATED_DIR"
BASE_IR="${WORK_DIR}/base.json"
gherkin-parser "$FEATURE" "$BASE_IR"
APS_FEATURE_PATH="$FEATURE" APS_HANDLERS_CRATE="$HANDLERS_CRATE" \
  acceptance-entrypoint-generator "$BASE_IR" "$GENERATED_DIR"

exec gherkin-mutator \
  --feature "$FEATURE" \
  --work-dir "$WORK_DIR" \
  --generated-dir "$GENERATED_DIR" \
  --level "$LEVEL" \
  --runner-worker "aps-adapter cargo test" \
  "$@"
