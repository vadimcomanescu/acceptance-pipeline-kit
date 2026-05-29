#!/usr/bin/env bash
# Task 3.1 proof (AC-008): TypeScript no-clone, no-token install.
#
# Proves a TS project can consume @aps-kit/typescript from a `npm pack` tarball
# produced after `npm run build` — no repo clone, no npm registry credential.
# Steps:
#   1. In typescript/: npm install (lockfile gitignored, so NOT npm ci), npm run build.
#   2. npm pack into a tmp dir; assert the tarball listing contains dist/ (built JS).
#   3. Assert package.json `files` is exactly ["dist","src"] (no dev artifacts).
#   4. npm init -y a scratch project and `npm install <tarball>` into it.
#   5. Assert BOTH bins resolve AND execute from the scratch install
#      (acceptance-entrypoint-generator, aps-adapter) — observe usage/exit, not
#      mere resolution.
#
# Self-contained: builds its own tmp dirs, cleans up, captures evidence under
# .evidence/m3/. Exits non-zero on the first failed assertion.
set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TS_DIR="$REPO/typescript"
EVID="$REPO/.evidence/m3"
mkdir -p "$EVID"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "test_ts_tarball: FAIL: $*" >&2; exit 1; }
note() { echo "== $*"; }

PACK_DEST="$TMP/pack"
SCRATCH="$TMP/scratch"
mkdir -p "$PACK_DEST" "$SCRATCH"

# --- Step 1: install deps + build dist/ ------------------------------------
note "npm install (lockfile is gitignored -> install, not ci)"
( cd "$TS_DIR" && npm install ) >"$EVID/10-ts-npm-install.txt" 2>&1 \
  || { cat "$EVID/10-ts-npm-install.txt"; fail "npm install failed"; }

note "npm run build"
( cd "$TS_DIR" && npm run build ) >"$EVID/11-ts-build.txt" 2>&1 \
  || { cat "$EVID/11-ts-build.txt"; fail "npm run build failed"; }

[ -d "$TS_DIR/dist" ] || fail "dist/ not produced by npm run build"

# --- Step 2: npm pack + tarball listing ------------------------------------
note "npm pack into $PACK_DEST"
( cd "$TS_DIR" && npm pack --pack-destination "$PACK_DEST" ) \
  >"$EVID/12-ts-pack.txt" 2>&1 \
  || { cat "$EVID/12-ts-pack.txt"; fail "npm pack failed"; }

TARBALL="$(ls "$PACK_DEST"/*.tgz 2>/dev/null | head -n1 || true)"
[ -n "$TARBALL" ] || fail "no .tgz produced by npm pack"
note "tarball: $TARBALL"

note "tarball listing (tar tzf)"
tar tzf "$TARBALL" | sort >"$EVID/13-ts-tarball-listing.txt"

# dist/ (built JS) must be present.
grep -Eq '(^|/)dist/' "$EVID/13-ts-tarball-listing.txt" \
  || { cat "$EVID/13-ts-tarball-listing.txt"; fail "tarball is missing dist/"; }
# The two built bin entrypoints must be present in dist/cmd/.
grep -q 'dist/cmd/acceptance-entrypoint-generator.js' "$EVID/13-ts-tarball-listing.txt" \
  || fail "tarball missing dist/cmd/acceptance-entrypoint-generator.js"
grep -q 'dist/cmd/aps-adapter.js' "$EVID/13-ts-tarball-listing.txt" \
  || fail "tarball missing dist/cmd/aps-adapter.js"
# No dev artifacts: nothing outside package/{dist,src} (e.g. no node_modules,
# no coverage, no tsconfig, no vitest config).
if grep -Ev '^package/(dist/|src/|package\.json$|README|LICENSE)' \
     "$EVID/13-ts-tarball-listing.txt" | grep -q .; then
  echo "unexpected entries:" >&2
  grep -Ev '^package/(dist/|src/|package\.json$|README|LICENSE)' \
     "$EVID/13-ts-tarball-listing.txt" >&2
  fail "tarball contains entries outside dist/ + src/ (dev artifacts leaked)"
fi

# --- Step 3: package.json files == ["dist","src"] --------------------------
note "assert package.json files == [dist, src]"
FILES_JSON="$(node -e 'const p=require("'"$TS_DIR"'/package.json"); process.stdout.write(JSON.stringify(p.files))')"
echo "$FILES_JSON" >"$EVID/14-ts-files-field.txt"
[ "$FILES_JSON" = '["dist","src"]' ] \
  || fail "package.json files is $FILES_JSON, expected [\"dist\",\"src\"]"

# --- Step 4: scratch install (no clone, no registry token) -----------------
note "npm init -y scratch project + install tarball"
( cd "$SCRATCH" && npm init -y ) >"$EVID/15-scratch-init.txt" 2>&1 \
  || { cat "$EVID/15-scratch-init.txt"; fail "npm init failed"; }
( cd "$SCRATCH" && npm install "$TARBALL" ) >"$EVID/16-scratch-install.txt" 2>&1 \
  || { cat "$EVID/16-scratch-install.txt"; fail "npm install <tarball> failed"; }

GEN_BIN="$SCRATCH/node_modules/.bin/acceptance-entrypoint-generator"
ADP_BIN="$SCRATCH/node_modules/.bin/aps-adapter"
[ -e "$GEN_BIN" ] || fail "acceptance-entrypoint-generator did not resolve in scratch install"
[ -e "$ADP_BIN" ] || fail "aps-adapter did not resolve in scratch install"

# --- Step 5: execute both bins from the scratch install --------------------
# Generator with no args -> usage to stderr, exit 2 (per cmd source).
note "execute acceptance-entrypoint-generator (no args -> usage, exit 2)"
GEN_OUT="$("$GEN_BIN" 2>&1)" && GEN_RC=0 || GEN_RC=$?
{ echo "exit=$GEN_RC"; echo "$GEN_OUT"; } >"$EVID/17-exec-generator.txt"
[ "$GEN_RC" = "2" ] || fail "generator no-args exit was $GEN_RC, expected 2"
echo "$GEN_OUT" | grep -q 'usage: acceptance-entrypoint-generator' \
  || fail "generator did not print its usage line"

# Adapter with --help -> usage to stderr, exit 0 (no-args would exit 2 via usage()).
note "execute aps-adapter --help (-> usage, exit 0)"
ADP_OUT="$("$ADP_BIN" --help 2>&1)" && ADP_RC=0 || ADP_RC=$?
{ echo "exit=$ADP_RC"; echo "$ADP_OUT"; } >"$EVID/18-exec-adapter.txt"
[ "$ADP_RC" = "0" ] || fail "adapter --help exit was $ADP_RC, expected 0"
echo "$ADP_OUT" | grep -q 'usage: aps-adapter' \
  || fail "adapter did not print its usage line"

echo
echo "test_ts_tarball: PASS — tarball ships dist/+src, both bins resolve and execute from scratch install (AC-008)"
