#!/usr/bin/env bash
# Normal acceptance pipeline for a Go project:
#   1. gherkin-parser turns each .feature into JSON IR
#   2. aps-generate writes _test.go entry points + metadata
#   3. go test runs the generated tests
#
# Expected project layout:
#   features/*.feature
#   handlers/  (its init() registers steps with apskit.DefaultRegistry)
#   acceptance/generated/  (output dir; create a small _test.go that
#                            imports handlers for its side effects)
set -euo pipefail

FEATURES_DIR="${FEATURES_DIR:-features}"
IR_DIR="${IR_DIR:-build/acceptance}"
GENERATED_DIR="${GENERATED_DIR:-acceptance/generated}"

if ! command -v gherkin-parser >/dev/null 2>&1; then
  echo "gherkin-parser not on PATH. Install with scripts/install-aps-tools.sh." >&2
  exit 1
fi

mkdir -p "$IR_DIR" "$GENERATED_DIR"

shopt -s nullglob
features=("$FEATURES_DIR"/*.feature)
if [ ${#features[@]} -eq 0 ]; then
  echo "no .feature files under $FEATURES_DIR" >&2
  exit 1
fi

for feature in "${features[@]}"; do
  stem="$(basename "$feature" .feature)"
  ir="$(realpath -m "$IR_DIR/${stem}.json")"
  echo "parsing $feature -> $ir"
  gherkin-parser "$feature" "$ir"
  echo "generating tests from $ir into $GENERATED_DIR"
  # Use an absolute IR path so the generated _test.go works from any cwd.
  aps-generate --feature-path "$(realpath -m "$feature")" "$ir" "$GENERATED_DIR"
done

echo "running go test"
exec go test "./${GENERATED_DIR}/..." "$@"
