#!/usr/bin/env sh
# Behavior tests for install.sh (the download-verify-install script).
#
# These run install.sh end-to-end against a LOCAL fixture release built by the
# single artifact producer (scripts/build-release-artifacts.sh), served over
# file:// via the APS_DIST_BASE_URL seam -- no network, no live GitHub Release.
#
# Fixture layout mirrors a real release URL: <FIXROOT>/<tag>/<archives + checksums.txt>.
# install.sh resolves ${APS_DIST_BASE_URL}/<tag>/<archive>, so APS_DIST_BASE_URL
# points at file://<FIXROOT>.
#
# Usage: scripts/tests/test_install.sh
# Exit:  0 = all behaviors pass; non-zero = a behavior failed.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"
BUILDER="$REPO_ROOT/scripts/build-release-artifacts.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [ -n "${2:-}" ] && echo "       $2"; }

# --- shared fixture: build once, lay out per-tag dirs ------------------------

FIXROOT="$(mktemp -d)"
WORKROOT="$(mktemp -d)"
trap 'rm -rf "$FIXROOT" "$WORKROOT"' EXIT

build_fixture() {
  # build_fixture <tag> -- produce a release for <tag> under $FIXROOT/<tag>.
  _tag="$1"
  _raw="$WORKROOT/raw_$_tag"
  APS_RELEASE_VERSION="$_tag" "$BUILDER" "$_raw" >/dev/null 2>&1 \
    || { echo "fixture build failed for $_tag" >&2; exit 1; }
  mkdir -p "$FIXROOT/$_tag"
  cp "$_raw"/* "$FIXROOT/$_tag/"
}

echo "# building fixtures (v0.1.0, v0.2.0) ..." >&2
build_fixture v0.1.0
build_fixture v0.2.0

BASE_URL="file://$FIXROOT"

# Detect this host's expected target so assertions name the right archive.
HOST_OS="$(uname -s)"; HOST_ARCH="$(uname -m)"
case "$HOST_OS" in Linux) HOST_OS=linux ;; Darwin) HOST_OS=darwin ;; esac
case "$HOST_ARCH" in x86_64|amd64) HOST_ARCH=amd64 ;; arm64|aarch64) HOST_ARCH=arm64 ;; esac

# ---------------------------------------------------------------------------
# Behavior: success path installs both executable binaries into --bin-dir.
# ---------------------------------------------------------------------------
test_success_installs_both_binaries() {
  bindir="$WORKROOT/bin_success"
  rm -rf "$bindir"
  if APS_DIST_BASE_URL="$BASE_URL" sh "$INSTALL_SH" --bin-dir "$bindir" >/dev/null 2>&1; then
    if [ -x "$bindir/gherkin-parser" ] && [ -x "$bindir/gherkin-mutator" ]; then
      pass "success path installs executable gherkin-parser and gherkin-mutator"
    else
      fail "success path installs executable gherkin-parser and gherkin-mutator" \
           "binaries missing or not executable in $bindir"
    fi
  else
    fail "success path installs executable gherkin-parser and gherkin-mutator" \
         "install.sh exited non-zero"
  fi
}

# ---------------------------------------------------------------------------
# Behavior: the installed gherkin-parser actually executes (not merely present
# and +x). The installed binary is the host-native target built into the
# fixture, so it really runs here. We assert it ran -- emitting its own output
# without an exec/not-found failure -- rather than just inspecting the file
# mode. A no-arg run prints a usage line (observed exit 2); we require that
# usage line so a non-runnable file (wrong arch, truncated) is caught.
# ---------------------------------------------------------------------------
test_installed_parser_runs() {
  bindir="$WORKROOT/bin_runs"
  rm -rf "$bindir"
  if ! APS_DIST_BASE_URL="$BASE_URL" sh "$INSTALL_SH" --bin-dir "$bindir" >/dev/null 2>&1; then
    fail "installed gherkin-parser executes" "install.sh exited non-zero"
    return
  fi
  if [ ! -x "$bindir/gherkin-parser" ]; then
    fail "installed gherkin-parser executes" "binary missing or not executable"
    return
  fi
  # Capture both streams and the exit code. A no-arg run exits non-zero (usage),
  # so guard the assignment against `set -e`. A failure to exec (e.g. 127
  # "not found" / "exec format error") yields no usage output.
  rc=0
  out="$("$bindir/gherkin-parser" 2>&1)" || rc=$?
  if [ "$rc" -eq 127 ]; then
    fail "installed gherkin-parser executes" "binary could not be executed (exit 127)"
  elif printf '%s' "$out" | grep -q 'usage: gherkin-parser'; then
    pass "installed gherkin-parser executes"
  else
    fail "installed gherkin-parser executes" "binary ran but did not emit its usage line (exit $rc): $out"
  fi
}

# ---------------------------------------------------------------------------
# Behavior: idempotent -- second run exits 0, binaries byte-identical.
# ---------------------------------------------------------------------------
test_idempotent_second_run() {
  bindir="$WORKROOT/bin_idem"
  rm -rf "$bindir"
  APS_DIST_BASE_URL="$BASE_URL" sh "$INSTALL_SH" --bin-dir "$bindir" >/dev/null 2>&1 || {
    fail "second run is idempotent (exit 0, byte-identical)" "first run failed"; return; }
  cp "$bindir/gherkin-parser" "$WORKROOT/parser_first"
  cp "$bindir/gherkin-mutator" "$WORKROOT/mutator_first"
  if APS_DIST_BASE_URL="$BASE_URL" sh "$INSTALL_SH" --bin-dir "$bindir" >/dev/null 2>&1; then
    if cmp -s "$WORKROOT/parser_first" "$bindir/gherkin-parser" \
       && cmp -s "$WORKROOT/mutator_first" "$bindir/gherkin-mutator"; then
      pass "second run is idempotent (exit 0, byte-identical)"
    else
      fail "second run is idempotent (exit 0, byte-identical)" "binaries differ after second run"
    fi
  else
    fail "second run is idempotent (exit 0, byte-identical)" "second run exited non-zero"
  fi
}

# ---------------------------------------------------------------------------
# Behavior: checksum mismatch is fatal -- non-zero exit, stderr names file +
# both hashes, no binary installed, no temp leftover in bin dir.
# ---------------------------------------------------------------------------
test_checksum_mismatch_fatal() {
  # Build an isolated tampered copy of the v0.1.0 release so we don't corrupt
  # the shared fixture other tests rely on.
  tamperroot="$WORKROOT/tamper"
  rm -rf "$tamperroot"
  mkdir -p "$tamperroot/v0.1.0"
  cp "$FIXROOT/v0.1.0"/* "$tamperroot/v0.1.0/"
  archive="gherkin-parser_v0.1.0_${HOST_OS}_${HOST_ARCH}.tar.gz"
  # Corrupt the RECORDED checksum for this archive (not the archive bytes), so the
  # archive stays a valid, extractable tar.gz: only the SHA-256 comparison can
  # catch the discrepancy. (Tampering the archive bytes would also be caught by
  # gzip/tar failing to extract, which would not prove the checksum gate fires.)
  # Flip the first hex digit of that archive's line in checksums.txt.
  awk -v want="$archive" '{
    if ($2 == want) {
      first=substr($1,1,1); rest=substr($1,2);
      newfirst=(first=="0"?"1":"0");
      print newfirst rest "  " $2;
    } else { print }
  }' "$tamperroot/v0.1.0/checksums.txt" > "$tamperroot/v0.1.0/checksums.txt.new"
  mv "$tamperroot/v0.1.0/checksums.txt.new" "$tamperroot/v0.1.0/checksums.txt"

  bindir="$WORKROOT/bin_tamper"
  rm -rf "$bindir"
  stderr_file="$WORKROOT/tamper_stderr"
  if APS_DIST_BASE_URL="file://$tamperroot" sh "$INSTALL_SH" --bin-dir "$bindir" \
       >/dev/null 2>"$stderr_file"; then
    fail "checksum mismatch is fatal and installs nothing" "install.sh exited 0 on tampered archive"
    return
  fi
  ok=1; why=""
  # The mismatch DIAGNOSTIC itself must name the file -- not merely some earlier
  # "downloading X" log line. Require the archive name on a line that also
  # reports the mismatch, so dropping the name from the die message is caught.
  grep -E 'mismatch' "$stderr_file" | grep -q "$archive" \
    || { ok=0; why="mismatch message does not name the file"; }
  # The mismatch message must name BOTH hashes (expected + actual): two distinct
  # 64-hex strings on mismatch line(s).
  hashcount="$(grep -E 'mismatch' "$stderr_file" | grep -oE '[0-9a-f]{64}' | sort -u | wc -l)"
  [ "$hashcount" -ge 2 ] || { ok=0; why="${why:+$why; }mismatch message lacks both hashes (found $hashcount)"; }
  # No binary installed.
  if [ -e "$bindir/gherkin-parser" ] || [ -e "$bindir/gherkin-mutator" ]; then
    ok=0; why="${why:+$why; }a binary was installed despite mismatch"
  fi
  # No leftover temp/partial file in the bin dir (dir may be absent or empty).
  if [ -d "$bindir" ] && [ -n "$(ls -A "$bindir" 2>/dev/null)" ]; then
    ok=0; why="${why:+$why; }bin dir not empty: $(ls -A "$bindir")"
  fi
  if [ "$ok" -eq 1 ]; then
    pass "checksum mismatch is fatal and installs nothing"
  else
    fail "checksum mismatch is fatal and installs nothing" "$why"
  fi
}

# ---------------------------------------------------------------------------
# Behavior: unsupported platform fails BEFORE any download, echoing os/arch.
# ---------------------------------------------------------------------------
test_unsupported_platform_fails_before_download() {
  stubdir="$WORKROOT/stub"
  rm -rf "$stubdir"; mkdir -p "$stubdir"
  cat > "$stubdir/uname" <<'EOF'
#!/usr/bin/env sh
case "$1" in
  -s) echo FreeBSD ;;
  -m) echo riscv64 ;;
  *)  echo FreeBSD ;;
esac
EOF
  chmod +x "$stubdir/uname"
  # A curl stub that records if it was ever called -- proves no download happened.
  cat > "$stubdir/curl" <<EOF
#!/usr/bin/env sh
echo called >> "$WORKROOT/curl_called"
exit 0
EOF
  chmod +x "$stubdir/curl"
  rm -f "$WORKROOT/curl_called"

  bindir="$WORKROOT/bin_unsupported"
  rm -rf "$bindir"
  stderr_file="$WORKROOT/unsupported_stderr"
  if PATH="$stubdir:$PATH" APS_DIST_BASE_URL="$BASE_URL" sh "$INSTALL_SH" \
       --bin-dir "$bindir" >/dev/null 2>"$stderr_file"; then
    fail "unsupported platform fails before download with os/arch echoed" "exited 0"
    return
  fi
  ok=1; why=""
  grep -q "FreeBSD" "$stderr_file" || { ok=0; why="stderr lacks detected os 'FreeBSD'"; }
  grep -q "riscv64" "$stderr_file" || { ok=0; why="${why:+$why; }stderr lacks detected arch 'riscv64'"; }
  if [ -f "$WORKROOT/curl_called" ]; then
    ok=0; why="${why:+$why; }download was attempted before platform check"
  fi
  if [ "$ok" -eq 1 ]; then
    pass "unsupported platform fails before download with os/arch echoed"
  else
    fail "unsupported platform fails before download with os/arch echoed" "$why"
  fi
}

# ---------------------------------------------------------------------------
# Behavior: --version <tag> drives which release dir is fetched.
# ---------------------------------------------------------------------------
test_version_flag_selects_release() {
  # Both v0.1.0 and v0.2.0 fixtures exist. Request v0.2.0 and assert install.sh's
  # own report references the v0.2.0 release dir and never the v0.1.0 one -- so
  # the requested tag, not the default, drove which release dir was fetched.
  bindir="$WORKROOT/bin_v2"
  rm -rf "$bindir"
  out_file="$WORKROOT/v2_out"
  if APS_DIST_BASE_URL="$BASE_URL" sh "$INSTALL_SH" --version v0.2.0 --bin-dir "$bindir" \
       >"$out_file" 2>&1; then
    if grep -q "v0.2.0" "$out_file" && ! grep -q "/v0.1.0/" "$out_file"; then
      pass "--version v0.2.0 fetches from the v0.2.0 release dir"
    else
      fail "--version v0.2.0 fetches from the v0.2.0 release dir" \
           "output did not reference v0.2.0 archives: $(cat "$out_file")"
    fi
  else
    fail "--version v0.2.0 fetches from the v0.2.0 release dir" "install.sh exited non-zero"
  fi
}

# ---------------------------------------------------------------------------
# Behavior: --version isolation -- requesting a tag whose dir is absent fails,
# and does NOT silently fall back to another tag.
# ---------------------------------------------------------------------------
test_version_flag_no_fallback() {
  bindir="$WORKROOT/bin_missing"
  rm -rf "$bindir"
  if APS_DIST_BASE_URL="$BASE_URL" sh "$INSTALL_SH" --version v9.9.9 --bin-dir "$bindir" \
       >/dev/null 2>&1; then
    fail "--version with a missing release fails (no fallback)" "exited 0 for absent tag"
  else
    if [ -e "$bindir/gherkin-parser" ]; then
      fail "--version with a missing release fails (no fallback)" "installed a binary from a fallback tag"
    else
      pass "--version with a missing release fails (no fallback)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Behavior (static, AC-005): install.sh invokes no go/go build/go install.
# ---------------------------------------------------------------------------
test_no_go_invocation() {
  if grep -nE '\bgo( |$|build|install)\b' "$INSTALL_SH" >/dev/null 2>&1; then
    fail "install.sh contains no go/go build/go install invocation" \
         "$(grep -nE '\bgo( |$|build|install)\b' "$INSTALL_SH")"
  else
    pass "install.sh contains no go/go build/go install invocation"
  fi
}

# --- run ---------------------------------------------------------------------

test_success_installs_both_binaries
test_installed_parser_runs
test_idempotent_second_run
test_checksum_mismatch_fatal
test_unsupported_platform_fails_before_download
test_version_flag_selects_release
test_version_flag_no_fallback
test_no_go_invocation

echo
echo "# passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
