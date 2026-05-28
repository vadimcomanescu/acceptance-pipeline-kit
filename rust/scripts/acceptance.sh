#!/usr/bin/env bash
# Normal acceptance pipeline for a Rust project.
#
# Expected project layout (relative to where you run this):
#   Cargo.toml
#   features/*.feature
#   src/lib.rs       provides a `pub fn register()` that registers step handlers
#                     with aps_kit::default_registry()
#   tests/           the generator writes here; one integration-test file per feature
set -euo pipefail

FEATURES_DIR="${FEATURES_DIR:-features}"
IR_DIR="${IR_DIR:-build/acceptance}"
GENERATED_DIR="${GENERATED_DIR:-tests}"
HANDLERS_CRATE="${HANDLERS_CRATE:-$(basename "$(pwd)")}"
HANDLERS_CRATE="${HANDLERS_CRATE//-/_}"

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
  echo "generating tests from $ir into $GENERATED_DIR (handlers crate: $HANDLERS_CRATE)"
  aps-generate \
    --feature-path "$(realpath -m "$feature")" \
    --handlers-crate "$HANDLERS_CRATE" \
    "$ir" "$GENERATED_DIR"
done

echo "running cargo test"
exec cargo test "$@"
