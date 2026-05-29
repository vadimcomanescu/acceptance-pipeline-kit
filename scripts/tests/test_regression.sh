#!/usr/bin/env bash
# Task 4.2 proof (AC-012): the kit does not regress under the new distribution
# path, and no generator/adapter/runtime SOURCE changed.
#
# Unlike test_e2e_go_free.sh this is NOT a Go-free proof: Go/Rust/TS legitimately
# use their native toolchains. The point here is the KIT (all four languages)
# still works when the upstream gherkin-parser/gherkin-mutator come from the new
# install.sh path, and that distribution work touched no behavior source.
#
# What it does:
#   0. Build a fixture release + install.sh the prebuilt gherkin-parser/-mutator
#      into a shared bin dir (the new acquisition path under test).
#   1. For each language (python, typescript, go, rust): install/build that
#      language's OWN acceptance-entrypoint-generator (per its README), then run
#      <lang>/scripts/acceptance.sh on its calculator example with the prebuilt
#      parser on PATH, and assert 5 tests pass (each runner's summary format).
#   2. Run python/scripts/acceptance-mutation.sh (LEVEL=full so every candidate
#      mutation is actually exercised, not differential-skipped) with the
#      prebuilt gherkin-mutator on PATH; assert total=15 killed=15 survived=0.
#      Restore the feature file afterward (the run rewrites a tested_at stamp).
#   3. Assert no generator/adapter/runtime SOURCE file differs from the merge-base
#      with main — only distribution files + tests + evidence may have changed.
#
# Evidence under .evidence/m4/. Exits non-zero on the first failed assertion.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL_SH="$REPO/install.sh"
BUILDER="$REPO/scripts/build-release-artifacts.sh"
EVID="$REPO/.evidence/m4"
mkdir -p "$EVID"

LOG="$EVID/10-regression.txt"
: >"$LOG"

note() { echo "== $*" | tee -a "$LOG"; }
emit() { echo "$*" | tee -a "$LOG"; }
fail() { echo "test_regression: FAIL: $*" | tee -a "$LOG" >&2; exit 1; }

TMP="$(mktemp -d)"
# Always restore the mutation-stamped feature file, even on early failure, so the
# working tree is left clean (the mutator rewrites its tested_at timestamp).
FEATURE_REL="python/examples/calculator/features/calculator.feature"
cleanup() {
  git -C "$REPO" checkout -- "$FEATURE_REL" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

TAG="v0.1.0"

# ---------------------------------------------------------------------------
# Step 0: build fixture + install prebuilt parser/mutator (the new path).
# ---------------------------------------------------------------------------
note "building fixture release $TAG + installing prebuilt parser/mutator via install.sh"
FIXROOT="$TMP/fixroot"; RAW="$TMP/raw"
APS_RELEASE_VERSION="$TAG" "$BUILDER" "$RAW" >>"$LOG" 2>&1 \
  || fail "fixture build failed (see $LOG)"
mkdir -p "$FIXROOT/$TAG"; cp "$RAW"/* "$FIXROOT/$TAG/"

PARSER_BIN="$TMP/parser-bin"
APS_DIST_BASE_URL="file://$FIXROOT" sh "$INSTALL_SH" --version "$TAG" --bin-dir "$PARSER_BIN" \
  >>"$LOG" 2>&1 || fail "install.sh failed (see $LOG)"
[ -x "$PARSER_BIN/gherkin-parser" ] || fail "gherkin-parser not installed"
[ -x "$PARSER_BIN/gherkin-mutator" ] || fail "gherkin-mutator not installed"
emit "prebuilt binaries installed: $(ls "$PARSER_BIN" | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# Step 1: per-language acceptance, 5 passed each. Each language uses its OWN
# acceptance-entrypoint-generator (and adapter) — never another language's — so
# the per-language generator is installed/built into an isolated location and
# placed FIRST on PATH ahead of the prebuilt parser.
# ---------------------------------------------------------------------------

# ---- Python ----
note "Python: pip install ./python[test] into a venv, run acceptance.sh"
PYVENV="$TMP/pyvenv"
python3 -m venv "$PYVENV" >>"$LOG" 2>&1 || fail "python venv creation failed"
"$PYVENV/bin/pip" install --quiet --upgrade pip >>"$LOG" 2>&1 || true
"$PYVENV/bin/pip" install --quiet "$REPO/python[test]" >>"$LOG" 2>&1 \
  || fail "pip install ./python[test] failed"
PY_LOG="$EVID/11-python-acceptance.txt"
set +e
( cd "$REPO/python/examples/calculator" \
  && PATH="$PYVENV/bin:$PARSER_BIN:$PATH" "$REPO/python/scripts/acceptance.sh" ) \
  >"$PY_LOG" 2>&1
PY_RC=$?
set -e
cat "$PY_LOG" >>"$LOG"
[ "$PY_RC" -eq 0 ] || fail "python acceptance.sh exited $PY_RC (see $PY_LOG)"
grep -Eq '(^| )5 passed' "$PY_LOG" || fail "python: pytest did not report 5 passed (see $PY_LOG)"
emit "Python: $(grep -E '5 passed' "$PY_LOG" | head -n1)"

# ---- TypeScript ----
note "TypeScript: npm install + build kit, npm install example, run acceptance.sh"
( cd "$REPO/typescript" && npm install && npm run build ) >>"$LOG" 2>&1 \
  || fail "TS kit npm install/build failed"
( cd "$REPO/typescript/examples/calculator" && npm install ) >>"$LOG" 2>&1 \
  || fail "TS example npm install failed"
TS_LOG="$EVID/12-typescript-acceptance.txt"
set +e
( cd "$REPO/typescript/examples/calculator" \
  && PATH="$PARSER_BIN:$PATH" "$REPO/typescript/scripts/acceptance.sh" ) \
  >"$TS_LOG" 2>&1
TS_RC=$?
set -e
cat "$TS_LOG" >>"$LOG"
[ "$TS_RC" -eq 0 ] || fail "TS acceptance.sh exited $TS_RC (see $TS_LOG)"
# vitest summary line: "Tests  5 passed (5)".
grep -Eq 'Tests[[:space:]]+5 passed \(5\)' "$TS_LOG" \
  || fail "TS: vitest did not report 5 passed (see $TS_LOG)"
emit "TypeScript: $(grep -E 'Tests[[:space:]]+5 passed' "$TS_LOG" | head -n1 | sed 's/^[[:space:]]*//')"

# ---- Go ----
note "Go: go install ./cmd/... into scratch GOBIN, run acceptance.sh"
GOBIN="$TMP/gobin"; mkdir -p "$GOBIN"
( cd "$REPO/go" && GOBIN="$GOBIN" go install ./cmd/acceptance-entrypoint-generator ./cmd/aps-adapter ) \
  >>"$LOG" 2>&1 || fail "go install ./cmd/... failed"
GO_LOG="$EVID/13-go-acceptance.txt"
set +e
( cd "$REPO/go/examples/calculator" \
  && PATH="$GOBIN:$PARSER_BIN:$PATH" "$REPO/go/scripts/acceptance.sh" -v ) \
  >"$GO_LOG" 2>&1
GO_RC=$?
set -e
cat "$GO_LOG" >>"$LOG"
[ "$GO_RC" -eq 0 ] || fail "go acceptance.sh exited $GO_RC (see $GO_LOG)"
# go test -v prints one "--- PASS:" line per passing (sub)test; expect exactly 5.
GO_PASS="$(grep -c '^--- PASS:' "$GO_LOG" || true)"
[ "$GO_PASS" -eq 5 ] || fail "go: expected 5 passing tests, got $GO_PASS (see $GO_LOG)"
emit "Go: $GO_PASS tests passed (--- PASS: lines)"

# ---- Rust ----
note "Rust: cargo install --path aps-kit into scratch root, run acceptance.sh"
CARGO_ROOT="$TMP/cargoroot"; mkdir -p "$CARGO_ROOT"
( cd "$REPO/rust" && cargo install --quiet --path aps-kit --root "$CARGO_ROOT" ) \
  >>"$LOG" 2>&1 || fail "cargo install --path aps-kit failed"
RUST_LOG="$EVID/14-rust-acceptance.txt"
set +e
( cd "$REPO/rust/examples/calculator" \
  && PATH="$CARGO_ROOT/bin:$PARSER_BIN:$PATH" HANDLERS_CRATE=calculator \
     "$REPO/rust/scripts/acceptance.sh" ) \
  >"$RUST_LOG" 2>&1
RUST_RC=$?
set -e
cat "$RUST_LOG" >>"$LOG"
[ "$RUST_RC" -eq 0 ] || fail "rust acceptance.sh exited $RUST_RC (see $RUST_LOG)"
# cargo test prints "test result: ok. 5 passed; ..." for the integration tests.
grep -Eq 'test result: ok\. 5 passed;' "$RUST_LOG" \
  || fail "rust: cargo test did not report 5 passed (see $RUST_LOG)"
emit "Rust: $(grep -E 'test result: ok\. 5 passed;' "$RUST_LOG" | head -n1 | sed 's/^[[:space:]]*//')"

# ---------------------------------------------------------------------------
# Step 2: mutation — prove the PREBUILT gherkin-mutator kills every candidate
# through the new install path. LEVEL=full forces all 15 candidates to run
# (the default 'hard' differential skips when the manifest stamp already matches,
# which would prove nothing). Expect total=15 killed=15 survived=0 errors=0
# (9 addition + 6 subtraction = 15, per the README).
# ---------------------------------------------------------------------------
note "Mutation: acceptance-mutation.sh LEVEL=full (prebuilt gherkin-mutator)"
MUT_LOG="$EVID/15-python-mutation.txt"
set +e
( cd "$REPO/python/examples/calculator" \
  && PATH="$PYVENV/bin:$PARSER_BIN:$PATH" LEVEL=full \
     "$REPO/python/scripts/acceptance-mutation.sh" ) \
  >"$MUT_LOG" 2>&1
MUT_RC=$?
set -e
cat "$MUT_LOG" >>"$LOG"
# Restore the feature file immediately (the run rewrote its tested_at stamp);
# the EXIT trap also restores, but doing it here keeps the diff guard below clean.
git -C "$REPO" checkout -- "$FEATURE_REL"

[ "$MUT_RC" -eq 0 ] || fail "acceptance-mutation.sh exited $MUT_RC (see $MUT_LOG)"
grep -Eq 'total=15 killed=15 survived=0 errors=0' "$MUT_LOG" \
  || fail "mutation did not report total=15 killed=15 survived=0 errors=0 (see $MUT_LOG)"
emit "Mutation: $(grep -E 'total=15 killed=15 survived=0 errors=0' "$MUT_LOG" | tail -n1)"

# ---------------------------------------------------------------------------
# Step 3: source-change guard. No generator/adapter/runtime SOURCE may differ
# from the merge-base with main. Compare the full working tree (committed +
# uncommitted, tracked + untracked) against the merge-base; any changed path
# must fall under the allow-list of distribution/test/evidence prefixes.
# ---------------------------------------------------------------------------
note "Source guard: assert no generator/adapter/runtime source changed vs merge-base"
MERGE_BASE="$(git -C "$REPO" merge-base HEAD main)"
emit "merge-base with main: $MERGE_BASE"

# All paths that differ from the merge-base: committed diff + unstaged + staged +
# untracked (excluding standard-ignored). Deduplicated.
CHANGED="$(
  {
    git -C "$REPO" diff --name-only "$MERGE_BASE" HEAD
    git -C "$REPO" diff --name-only HEAD
    git -C "$REPO" diff --name-only --cached
    git -C "$REPO" ls-files --others --exclude-standard
  } | sort -u
)"
echo "$CHANGED" >"$EVID/16-changed-files.txt"
emit "changed paths vs merge-base:"
printf '%s\n' "$CHANGED" | sed 's/^/  /' | tee -a "$LOG"

# Allow-list: distribution files, tests, evidence, docs, workflow, fixtures.
# Anything OUTSIDE this list is a forbidden source change and fails the guard.
ALLOW='^(install\.sh|scripts/|\.github/|\.evidence/|README\.md|AGENTS\.md|.*/README\.md|\.shepherd/|\.gitignore|LICENSE|NOTICE)'

VIOLATIONS=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if ! printf '%s\n' "$f" | grep -Eq "$ALLOW"; then
    VIOLATIONS="${VIOLATIONS}${f}\n"
  fi
done <<EOF_CHANGED
$CHANGED
EOF_CHANGED

if [ -n "$VIOLATIONS" ]; then
  emit "FORBIDDEN source/non-distribution changes detected:"
  printf "$VIOLATIONS" | sed 's/^/  /' | tee -a "$LOG"
  fail "distribution work changed files outside the allowed distribution/test/evidence set (AC-012)"
fi
emit "Source guard: OK — only distribution/test/evidence files differ from merge-base"

emit ""
emit "test_regression: PASS — kit does not regress via the new install path:"
emit "  - Python / TypeScript / Go / Rust acceptance: 5 passed each"
emit "  - Mutation (prebuilt gherkin-mutator, LEVEL=full): total=15 killed=15 survived=0"
emit "  - No generator/adapter/runtime source changed vs merge-base"
emit "  evidence: $LOG + 11..16-*.txt under $EVID"
