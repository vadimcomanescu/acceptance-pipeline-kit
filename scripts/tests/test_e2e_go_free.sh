#!/usr/bin/env bash
# Task 4.1 proof (AC-001, AC-005 runtime): Go-free Python end-to-end.
#
# Proves that on a machine with NO `go` on PATH for the whole acceptance run, the
# documented drop-in path works end to end:
#   1. install.sh downloads + checksum-verifies the prebuilt gherkin-parser /
#      gherkin-mutator from a local fixture release (no compilation), then
#   2. the Python calculator acceptance pipeline runs and pytest reports 5 passed.
#
# The fixture release is produced BEFORE Go is scrubbed (the builder cross-compiles
# the upstream binaries and needs `go`); everything after that runs under a PATH
# from which `go` and `gofmt` are removed.
#
# Go-scrub recipe (this host: `go`/`gofmt` live in /usr/bin alongside curl/
# sha256sum/tar/unzip/cargo; python3/pytest are under mise, NOT /usr/bin). Go has
# no private dir, so we cannot drop "the Go dir". Instead build a clean bin dir
# that symlinks every /usr/bin entry EXCEPT `go` and `gofmt` (a DENY-LIST — an
# allow-list would silently drop the bash interpreter and the coreutils the
# acceptance scripts call), then prepend the mise python3 dir. PATH for the
# install + acceptance phase is exactly "<scrubbed>:<mise python3 dir>".
#
# Evidence is captured under .evidence/m4/. The e2e log proves: empty
# `command -v go`, the install checksum-verify line, and pytest "5 passed".
#
# Usage: scripts/tests/test_e2e_go_free.sh
# Exit:  0 = AC-001/AC-005(runtime) proven; non-zero = a behavior failed.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL_SH="$REPO/install.sh"
BUILDER="$REPO/scripts/build-release-artifacts.sh"
EVID="$REPO/.evidence/m4"
mkdir -p "$EVID"

LOG="$EVID/01-e2e-go-free.txt"
: >"$LOG"

# Tee every diagnostic to both the console and the evidence log so the single
# log file is a self-contained proof artifact.
note() { echo "== $*" | tee -a "$LOG"; }
emit() { echo "$*" | tee -a "$LOG"; }
fail() { echo "test_e2e_go_free: FAIL: $*" | tee -a "$LOG" >&2; exit 1; }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

TAG="v0.1.0"

# ---------------------------------------------------------------------------
# Step 0 (Go AVAILABLE): build the fixture release. The builder needs `go` to
# cross-compile the upstream binaries, so this MUST run before the scrub.
# Layout: <FIXROOT>/<tag>/<archives + checksums.txt> so APS_DIST_BASE_URL=
# file://<FIXROOT> resolves <FIXROOT>/<tag>/<archive> exactly like a real
# GitHub Release download URL.
# ---------------------------------------------------------------------------
command -v go >/dev/null 2>&1 || fail "go must be available BEFORE the scrub to build the fixture"

FIXROOT="$TMP/fixroot"
RAW="$TMP/raw"
note "building fixture release $TAG (go available; builder cross-compiles upstream)"
APS_RELEASE_VERSION="$TAG" "$BUILDER" "$RAW" >>"$LOG" 2>&1 \
  || fail "fixture build failed (see $LOG)"
mkdir -p "$FIXROOT/$TAG"
cp "$RAW"/* "$FIXROOT/$TAG/"
[ -f "$FIXROOT/$TAG/checksums.txt" ] || fail "fixture missing checksums.txt"

# ---------------------------------------------------------------------------
# Step 1: construct the Go-free environment (deny-list go/gofmt).
# ---------------------------------------------------------------------------
note "constructing Go-free PATH (deny-list go/gofmt from /usr/bin)"

SCRUBBED_BIN="$TMP/scrubbed-bin"
mkdir -p "$SCRUBBED_BIN"
# Symlink every /usr/bin entry EXCEPT the Go toolchain into the clean bin dir.
for entry in /usr/bin/*; do
  name="$(basename "$entry")"
  case "$name" in
    go|gofmt) continue ;;
  esac
  ln -sf "$entry" "$SCRUBBED_BIN/$name"
done

# Derive the mise python3 dir (also holds pytest/pip) from the live python3.
PY3="$(command -v python3)"
PY_DIR="$(dirname "$PY3")"
[ -x "$PY_DIR/python3" ] || fail "mise python3 not found at $PY_DIR/python3"

# This is the only PATH used for the rest of the run.
GOFREE_PATH="$SCRUBBED_BIN:$PY_DIR"

# ---------------------------------------------------------------------------
# Step 2: assert the environment is genuinely Go-free yet otherwise complete.
# `command -v go` MUST print NOTHING (empty), not merely fail.
# ---------------------------------------------------------------------------
note "asserting Go-free PATH: command -v go must be empty"
GO_LOC="$(PATH="$GOFREE_PATH" bash -c 'command -v go || true')"
GOFMT_LOC="$(PATH="$GOFREE_PATH" bash -c 'command -v gofmt || true')"
emit "command -v go    -> '${GO_LOC}'"
emit "command -v gofmt -> '${GOFMT_LOC}'"
[ -z "$GO_LOC" ] || fail "go is still resolvable on the scrubbed PATH: $GO_LOC"
[ -z "$GOFMT_LOC" ] || fail "gofmt is still resolvable on the scrubbed PATH: $GOFMT_LOC"

note "asserting required tools resolve on the scrubbed PATH"
for tool in bash python3 curl sha256sum tar; do
  loc="$(PATH="$GOFREE_PATH" bash -c "command -v $tool || true")"
  emit "command -v $tool -> '${loc}'"
  [ -n "$loc" ] || fail "required tool '$tool' missing from the scrubbed PATH"
done

# ---------------------------------------------------------------------------
# Step 3a (Go-free): create a venv and install the Python kit WITHOUT go.
# `pip install ./python[test]` is the no-clone install stand-in (the README's
# git+ URL targets the same package) and pulls pytest into the venv.
# ---------------------------------------------------------------------------
note "creating venv + pip install ./python[test] (no go on PATH)"
VENV="$TMP/venv"
PATH="$GOFREE_PATH" python3 -m venv "$VENV" >>"$LOG" 2>&1 \
  || fail "venv creation failed under Go-free PATH"

# The venv's bin dir goes first; the scrubbed system tools + mise python follow.
# `go` never appears anywhere in this PATH.
RUN_PATH="$VENV/bin:$GOFREE_PATH"

PATH="$RUN_PATH" pip install --quiet --upgrade pip >>"$LOG" 2>&1 || true
PATH="$RUN_PATH" pip install "$REPO/python[test]" >>"$LOG" 2>&1 \
  || fail "pip install ./python[test] failed under Go-free PATH (see $LOG)"

# ---------------------------------------------------------------------------
# Step 3b (Go-free): run install.sh against the file:// fixture to place the
# prebuilt gherkin-parser/gherkin-mutator on PATH. Capture stderr so the
# checksum-verify line lands in the log (install.sh logs to stderr).
# ---------------------------------------------------------------------------
note "running install.sh --version $TAG --bin-dir <bin> against file:// fixture (no go)"
BIN_DIR="$TMP/bin"
INSTALL_LOG="$EVID/02-install-go-free.txt"
PATH="$RUN_PATH" APS_DIST_BASE_URL="file://$FIXROOT" \
  sh "$INSTALL_SH" --version "$TAG" --bin-dir "$BIN_DIR" \
  >"$INSTALL_LOG" 2>&1 \
  || { cat "$INSTALL_LOG" >>"$LOG"; fail "install.sh failed under Go-free PATH (see $INSTALL_LOG)"; }
cat "$INSTALL_LOG" | tee -a "$LOG" >/dev/null

# The binaries must have come from the verified archive, not a local compile:
# assert install.sh emitted a checksum-verify line ("verified <archive> (<hash>)").
note "asserting install.sh checksum-verify line is present (binaries from archive, not compiled)"
CHECKSUM_LINE="$(grep -E 'verified .*\.(tar\.gz|zip) \([0-9a-f]{64}\)' "$INSTALL_LOG" | head -n1 || true)"
emit "checksum-verify line: ${CHECKSUM_LINE:-<none>}"
[ -n "$CHECKSUM_LINE" ] || fail "no checksum-verify line in install output (cannot prove binaries came from the archive)"

[ -x "$BIN_DIR/gherkin-parser" ] || fail "gherkin-parser not installed/executable"
[ -x "$BIN_DIR/gherkin-mutator" ] || fail "gherkin-mutator not installed/executable"

# ---------------------------------------------------------------------------
# Step 4 (Go-free): run the Python calculator acceptance pipeline end to end.
# Per python/README.md "Try the demo": cd python/examples/calculator && run the
# kit's python/scripts/acceptance.sh (defaults FEATURES_DIR=features, which the
# example provides). The installed bin dir goes first so the prebuilt
# gherkin-parser is found; the venv supplies pytest + the generator console
# script; `go` is absent throughout.
# ---------------------------------------------------------------------------
note "running python/scripts/acceptance.sh on the calculator example (no go)"
ACCEPT_PATH="$BIN_DIR:$RUN_PATH"

# Final pre-flight: prove go is STILL empty on the exact PATH the pipeline runs.
GO_LOC2="$(PATH="$ACCEPT_PATH" bash -c 'command -v go || true')"
emit "command -v go (pipeline PATH) -> '${GO_LOC2}'"
[ -z "$GO_LOC2" ] || fail "go reappeared on the acceptance PATH: $GO_LOC2"

PYTEST_LOG="$EVID/03-pytest.txt"
set +e
( cd "$REPO/python/examples/calculator" \
  && PATH="$ACCEPT_PATH" "$REPO/python/scripts/acceptance.sh" ) \
  >"$PYTEST_LOG" 2>&1
RC=$?
set -e
cat "$PYTEST_LOG" | tee -a "$LOG" >/dev/null

[ "$RC" -eq 0 ] || fail "acceptance.sh exited $RC (expected 0); see $PYTEST_LOG"

# pytest must report exactly 5 passed.
note "asserting pytest reports 5 passed"
PASS_LINE="$(grep -E '5 passed' "$PYTEST_LOG" | head -n1 || true)"
emit "pytest summary: ${PASS_LINE:-<none>}"
[ -n "$PASS_LINE" ] || fail "pytest did not report '5 passed' (see $PYTEST_LOG)"

# ---------------------------------------------------------------------------
# Step 5: final guard — go must STILL be empty after the whole run.
# ---------------------------------------------------------------------------
note "final assertion: command -v go is still empty after the full run"
GO_LOC3="$(PATH="$ACCEPT_PATH" bash -c 'command -v go || true')"
emit "command -v go (post-run) -> '${GO_LOC3}'"
[ -z "$GO_LOC3" ] || fail "go became resolvable after the run: $GO_LOC3"

emit ""
emit "test_e2e_go_free: PASS — Go-free install.sh + Python acceptance.sh ran end to end:"
emit "  - command -v go EMPTY throughout (build phase used go; acceptance phase did not)"
emit "  - install.sh checksum-verified the prebuilt binaries (not compiled): $CHECKSUM_LINE"
emit "  - pytest: $PASS_LINE"
emit "  evidence: $LOG, $INSTALL_LOG, $PYTEST_LOG"
