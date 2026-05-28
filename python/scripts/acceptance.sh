#!/usr/bin/env bash
# Normal acceptance pipeline:
#   1. gherkin-parser turns each .feature into JSON IR
#   2. acceptance-entrypoint-generator writes pytest entry points + metadata
#   3. pytest runs the generated tests
#
# Run from a project root that has:
#   features/*.feature
#   handlers/  (or any conftest.py-imported module that registers steps)
set -euo pipefail

FEATURES_DIR="${FEATURES_DIR:-features}"
IR_DIR="${IR_DIR:-build/acceptance}"
GENERATED_DIR="${GENERATED_DIR:-acceptance/generated}"

if ! command -v gherkin-parser >/dev/null 2>&1; then
  echo "gherkin-parser not on PATH. Install with scripts/install-aps-tools.sh." >&2
  exit 1
fi

rm -rf "$IR_DIR" "$GENERATED_DIR"
mkdir -p "$IR_DIR" "$GENERATED_DIR"

shopt -s nullglob
features=("$FEATURES_DIR"/*.feature)
if [ ${#features[@]} -eq 0 ]; then
  echo "no .feature files under $FEATURES_DIR" >&2
  exit 1
fi

for feature in "${features[@]}"; do
  stem="$(basename "$feature" .feature)"
  ir="$IR_DIR/${stem}.json"
  echo "parsing $feature -> $ir"
  gherkin-parser "$feature" "$ir"
  echo "generating tests from $ir into $GENERATED_DIR"
  APS_FEATURE_PATH="$feature" acceptance-entrypoint-generator "$ir" "$GENERATED_DIR"
done

echo "running pytest against $GENERATED_DIR"
exec pytest "$GENERATED_DIR" -q "$@"
