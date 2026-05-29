#!/usr/bin/env bash
# Task 3.2 proof (AC-009): exact per-language no-clone git-install commands.
#
# Proves the exact working commands M5 docs will use. No tags are pushed; local
# stand-ins are used (pip install ./python for the git+ URL; static verification
# for Go/Rust module/crate identities).
#
#   Python: fresh venv, `pip install ./python` (stand-in for
#           `pip install "git+https://github.com/vadimcomanescu/acceptance-pipeline-kit@<tag>#subdirectory=python"`),
#           then assert BOTH console scripts execute.
#   Go:     `(cd go && go list ./cmd/...)` must print the exact cmd package paths
#           that the documented `go install …/go/cmd/<bin>@<tag>` commands name.
#   Rust:   `cargo metadata` must show crate `aps-kit` with two [[bin]] targets,
#           confirming `cargo install --git … --tag <tag> aps-kit`.
#
# Self-contained: builds its own tmp venv, cleans up, captures evidence under
# .evidence/m3/. Exits non-zero on the first failed assertion.
set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
EVID="$REPO/.evidence/m3"
mkdir -p "$EVID"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "test_git_installs: FAIL: $*" >&2; exit 1; }
note() { echo "== $*"; }

MODULE="github.com/vadimcomanescu/acceptance-pipeline-kit"

# ---------------------------------------------------------------------------
# Python: fresh venv + pip install ./python (git+ URL stand-in)
# ---------------------------------------------------------------------------
note "Python: create fresh venv"
python3 -m venv "$TMP/venv" || fail "venv creation failed"
# shellcheck disable=SC1091
. "$TMP/venv/bin/activate"

note "Python: pip install ./python (stand-in for git+ subdirectory=python)"
pip install --quiet --upgrade pip >"$EVID/20-py-pip-upgrade.txt" 2>&1 || true
pip install "$REPO/python" >"$EVID/21-py-pip-install.txt" 2>&1 \
  || { cat "$EVID/21-py-pip-install.txt"; fail "pip install ./python failed"; }

# Both console scripts must execute. Generator with no args -> usage, exit 2.
note "Python: execute acceptance-entrypoint-generator (no args -> usage, exit 2)"
PY_GEN="$(acceptance-entrypoint-generator 2>&1)" && PY_GEN_RC=0 || PY_GEN_RC=$?
{ echo "exit=$PY_GEN_RC"; echo "$PY_GEN"; } >"$EVID/22-py-exec-generator.txt"
[ "$PY_GEN_RC" = "2" ] || fail "python generator no-args exit was $PY_GEN_RC, expected 2"
echo "$PY_GEN" | grep -q 'usage: acceptance-entrypoint-generator' \
  || fail "python generator did not print its usage line"

note "Python: execute aps-adapter --help (-> usage, exit 0)"
PY_ADP="$(aps-adapter --help 2>&1)" && PY_ADP_RC=0 || PY_ADP_RC=$?
{ echo "exit=$PY_ADP_RC"; echo "$PY_ADP"; } >"$EVID/23-py-exec-adapter.txt"
[ "$PY_ADP_RC" = "0" ] || fail "python aps-adapter --help exit was $PY_ADP_RC, expected 0"
echo "$PY_ADP" | grep -q 'usage: aps-adapter' \
  || fail "python aps-adapter did not print its usage line"
deactivate

# ---------------------------------------------------------------------------
# Go: static-verify the exact cmd package paths
# ---------------------------------------------------------------------------
note "Go: (cd go && go list ./cmd/...)"
GO_LIST="$( cd "$REPO/go" && go list ./cmd/... )" \
  || fail "go list ./cmd/... failed"
echo "$GO_LIST" >"$EVID/24-go-list-cmd.txt"

GEN_PKG="$MODULE/go/cmd/acceptance-entrypoint-generator"
ADP_PKG="$MODULE/go/cmd/aps-adapter"
echo "$GO_LIST" | grep -qx "$GEN_PKG" \
  || fail "go list missing $GEN_PKG"
echo "$GO_LIST" | grep -qx "$ADP_PKG" \
  || fail "go list missing $ADP_PKG"

# ---------------------------------------------------------------------------
# Rust: static-verify crate aps-kit with two [[bin]] targets
# ---------------------------------------------------------------------------
note "Rust: cargo metadata -> aps-kit bin targets"
RUST_BINS="$(cargo metadata --no-deps --format-version 1 \
  --manifest-path "$REPO/rust/Cargo.toml" \
  | jq -r '.packages[] | select(.name=="aps-kit") | .targets[] | select(.kind[]=="bin") | .name' \
  | sort)" || fail "cargo metadata failed"
echo "$RUST_BINS" >"$EVID/25-rust-bins.txt"

echo "$RUST_BINS" | grep -qx 'acceptance-entrypoint-generator' \
  || fail "rust crate aps-kit missing bin acceptance-entrypoint-generator"
echo "$RUST_BINS" | grep -qx 'aps-adapter' \
  || fail "rust crate aps-kit missing bin aps-adapter"

# ---------------------------------------------------------------------------
# Record the EXACT documented command strings M5 must use.
# ---------------------------------------------------------------------------
cat >"$EVID/26-documented-commands.txt" <<'EOF'
# Exact no-clone git-install commands verified by this proof (AC-009).
# <tag> is a placeholder for a pushed semver tag, e.g. v0.1.0.

Python:
  pip install "git+https://github.com/vadimcomanescu/acceptance-pipeline-kit@<tag>#subdirectory=python"

Go:
  go install github.com/vadimcomanescu/acceptance-pipeline-kit/go/cmd/acceptance-entrypoint-generator@<tag>
  go install github.com/vadimcomanescu/acceptance-pipeline-kit/go/cmd/aps-adapter@<tag>

Rust:
  cargo install --git https://github.com/vadimcomanescu/acceptance-pipeline-kit --tag <tag> aps-kit
EOF
cat "$EVID/26-documented-commands.txt"

echo
echo "test_git_installs: PASS — Python git-install runs both console scripts; Go cmd packages and Rust aps-kit bins verified (AC-009)"
