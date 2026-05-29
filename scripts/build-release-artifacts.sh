#!/usr/bin/env sh
# Build the APS release payload: cross-compiles the two upstream Go binaries
# (gherkin-parser, gherkin-mutator) for the supported OS/arch matrix, packages
# each (tool x target) as an archive containing the binary + attribution NOTICE
# (+ upstream LICENSE iff one exists at the pinned ref), and writes a single
# checksums.txt covering every archive.
#
# This script is the SINGLE producer of release artifacts. Both
# .github/workflows/release.yml and the test fixtures call it, so the archive
# naming scheme and checksums.txt format cannot drift (AC-006d).
#
# Usage:   build-release-artifacts.sh <out-dir>
# Version: read from $APS_RELEASE_VERSION (default vX.Y.Z-dev).
#
# Upstream is pinned to a specific commit for reproducibility (see UPSTREAM_REF).
# The upstream repo declares a non-canonical module path, so we clone+build
# from a temp checkout rather than `go install ...@<ref>`.
set -eu

# --- configuration ----------------------------------------------------------

# Pinned upstream ref. As of 2026-05-29 this is the repository's sole commit.
# Pinning a commit (not a moving branch) makes the build reproducible.
UPSTREAM_REPO="https://github.com/unclebob/Acceptance-Pipeline-Specification.git"
UPSTREAM_REF="56ae63a9efb6299af543504218b81c3d1b3f1dcf"
UPSTREAM_SLUG="unclebob/Acceptance-Pipeline-Specification"

# Tools to build: "<name> <package-path>" per line.
TOOLS="gherkin-parser ./cmd/gherkin-parser
gherkin-mutator ./cmd/gherkin-mutator"

# Target matrix: "<os> <arch>" per line. Exactly these five (AC-006a).
TARGETS="darwin amd64
darwin arm64
linux amd64
linux arm64
windows amd64"

# --- helpers -----------------------------------------------------------------

die() { echo "build-release-artifacts.sh: $*" >&2; exit 1; }

# --- argument handling -------------------------------------------------------

[ "$#" -eq 1 ] || die "usage: build-release-artifacts.sh <out-dir>"
OUT_DIR="$1"
VERSION="${APS_RELEASE_VERSION:-vX.Y.Z-dev}"

command -v go >/dev/null 2>&1 || die "go is required to cross-compile the upstream binaries"
command -v git >/dev/null 2>&1 || die "git is required to clone the upstream repository"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required to write checksums.txt"
command -v tar >/dev/null 2>&1 || die "tar is required to package unix archives"
command -v zip >/dev/null 2>&1 || die "zip is required to package windows archives"

mkdir -p "$OUT_DIR"
# Absolute path so the build can cd into the upstream checkout freely.
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
UPSTREAM_DIR="$WORK_DIR/upstream"

# --- clone upstream at the pinned ref ---------------------------------------

echo "cloning $UPSTREAM_SLUG @ $UPSTREAM_REF ..."
git clone --quiet "$UPSTREAM_REPO" "$UPSTREAM_DIR" >/dev/null
( cd "$UPSTREAM_DIR" && git checkout --quiet "$UPSTREAM_REF" )

# Upstream LICENSE is copied into each archive only if it exists at the pinned
# ref (future-proofing). Today there is none, so we skip it silently -- we do
# NOT invent a license. The NOTICE (below) always documents the situation.
UPSTREAM_LICENSE=""
if [ -f "$UPSTREAM_DIR/LICENSE" ]; then
  UPSTREAM_LICENSE="$UPSTREAM_DIR/LICENSE"
  echo "found upstream LICENSE; it will be included in each archive"
else
  echo "no upstream LICENSE at ref $UPSTREAM_REF; archives carry NOTICE only"
fi

# --- generate the attribution NOTICE (shared by every archive) --------------

NOTICE_FILE="$WORK_DIR/NOTICE"
cat > "$NOTICE_FILE" <<EOF
NOTICE
======

The binaries gherkin-parser and gherkin-mutator distributed in this archive are
built from upstream source:

    Source:  $UPSTREAM_SLUG
    URL:     https://github.com/$UPSTREAM_SLUG
    Ref:     $UPSTREAM_REF

They are NOT part of acceptance-pipeline-kit's own source; this kit redistributes
them as a convenience so consumers need no Go toolchain.

LICENSE DISCLOSURE
------------------

At the pinned upstream ref ($UPSTREAM_REF) the upstream repository ships NO
explicit license file or license declaration. These binaries are therefore
redistributed AS-IS, per the acceptance-pipeline-kit maintainer's decision
(2026-05-29). No warranty is provided. Consumers and redistributors should
make their own assessment of the upstream terms.

This NOTICE concerns ONLY the bundled upstream binaries. acceptance-pipeline-kit's
own source is licensed separately; see the kit's LICENSE.
EOF

# --- build, package, accumulate checksums -----------------------------------

CHECKSUMS="$OUT_DIR/checksums.txt"
: > "$CHECKSUMS"

# build_one <tool> <pkg> <os> <arch> -- build, package, append checksum.
# Runs in the current shell (no pipe-to-while subshell), so `die`/`set -e`
# inside it aborts the whole script as intended.
build_one() {
  _tool="$1"; _pkg="$2"; _os="$3"; _arch="$4"

  _bin_name="$_tool"
  _archive_ext="tar.gz"
  if [ "$_os" = "windows" ]; then
    _bin_name="$_tool.exe"
    _archive_ext="zip"
  fi

  # Staging dir holds exactly what goes inside the archive.
  _stage="$WORK_DIR/stage/${_tool}_${_os}_${_arch}"
  rm -rf "$_stage"
  mkdir -p "$_stage"

  echo "building $_tool for $_os/$_arch ..."
  ( cd "$UPSTREAM_DIR" && \
    CGO_ENABLED=0 GOOS="$_os" GOARCH="$_arch" \
    go build -trimpath -o "$_stage/$_bin_name" "$_pkg" ) \
    || die "go build failed for $_tool $_os/$_arch"

  [ -s "$_stage/$_bin_name" ] || die "built binary is empty: $_tool $_os/$_arch"

  cp "$NOTICE_FILE" "$_stage/NOTICE"
  [ -n "$UPSTREAM_LICENSE" ] && cp "$UPSTREAM_LICENSE" "$_stage/LICENSE"

  _archive="${_tool}_${VERSION}_${_os}_${_arch}.${_archive_ext}"
  if [ "$_archive_ext" = "zip" ]; then
    ( cd "$_stage" && zip -q -X "$OUT_DIR/$_archive" ./* )
  else
    # Deterministic-ish tar: sorted entries, fixed owner.
    ( cd "$_stage" && tar --sort=name --owner=0 --group=0 --numeric-owner \
        -czf "$OUT_DIR/$_archive" ./* )
  fi

  ( cd "$OUT_DIR" && sha256sum "$_archive" >> "$CHECKSUMS" )
  echo "packaged $_archive"
}

# Iterate targets x tools without pipes into `while` (which would subshell and
# swallow `die`). Use here-doc redirection on the read loop instead.
while IFS=' ' read -r os arch; do
  [ -n "$os" ] || continue
  while IFS=' ' read -r tool pkg; do
    [ -n "$tool" ] || continue
    build_one "$tool" "$pkg" "$os" "$arch"
  done <<EOF_TOOLS
$TOOLS
EOF_TOOLS
done <<EOF_TARGETS
$TARGETS
EOF_TARGETS

# Sort checksums for stable, deterministic output.
sort -k2 "$CHECKSUMS" -o "$CHECKSUMS"

archive_count="$(grep -c . "$CHECKSUMS" || true)"
echo
echo "wrote $archive_count archive(s) + checksums.txt into $OUT_DIR"
[ "$archive_count" -eq 10 ] || die "expected 10 archives, got $archive_count"
