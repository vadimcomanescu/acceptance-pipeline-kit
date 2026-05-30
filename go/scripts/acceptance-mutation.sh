#!/usr/bin/env bash
set -euo pipefail

FEATURE="${FEATURE:-features/calculator.feature}"
WORK_DIR="${WORK_DIR:-build/acceptance-mutation}"
GENERATED_DIR="${GENERATED_DIR:-${WORK_DIR}/generated}"
LEVEL="${LEVEL:-hard}"

if ! command -v gherkin-mutator >/dev/null 2>&1; then
  echo "gherkin-mutator not on PATH. Install with scripts/install-aps-tools.sh." >&2
  exit 1
fi

mkdir -p "$WORK_DIR" "$GENERATED_DIR"
# Absolute IR path (go test runs with cwd=package dir); `cd … && pwd` instead of
# `realpath -m` keeps it portable — macOS realpath has no -m flag.
BASE_IR="$(cd "$WORK_DIR" && pwd)/base.json"
gherkin-parser "$FEATURE" "$BASE_IR"
APS_FEATURE_PATH="$FEATURE" acceptance-entrypoint-generator "$BASE_IR" "$GENERATED_DIR"

exec gherkin-mutator \
  --feature "$FEATURE" \
  --work-dir "$WORK_DIR" \
  --generated-dir "$GENERATED_DIR" \
  --level "$LEVEL" \
  --runner-worker "aps-adapter go test ./${GENERATED_DIR}/..." \
  "$@"
