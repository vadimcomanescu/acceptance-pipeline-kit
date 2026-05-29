#!/usr/bin/env sh
# install.sh -- download, verify, and install the prebuilt upstream Go binaries
# (gherkin-parser, gherkin-mutator) for the host platform. NO Go toolchain
# required: the binaries arrive as checksum-verified release archives and are
# never compiled here.
#
# Usage:
#   ./install.sh                      install the default release into ~/.local/bin
#   ./install.sh --version <tag>      pin to a specific release tag (e.g. v0.1.0)
#   ./install.sh --bin-dir <dir>      install into <dir> instead of ~/.local/bin
#
# Download source is the GitHub Release for the resolved tag. The base URL is
# overridable via APS_DIST_BASE_URL (a download-base seam used by the test
# fixtures to serve a local release over file://). The final asset URL is
#   ${APS_DIST_BASE_URL}/<tag>/<archive>
# which mirrors GitHub's .../releases/download/<tag>/<asset> layout.
#
# Style mirrors scripts/install-aps-tools.sh: POSIX sh, set -eu, all diagnostics
# to stderr, checksum verification mandatory before anything lands on PATH.
#
# Integrity note: checksums.txt is fetched over the same channel as the archives,
# so the SHA-256 check guards against corrupted/truncated downloads and a swapped
# asset -- but it is not an independent signature. The trust root is the HTTPS
# GitHub Release channel; an attacker able to replace both the archive and
# checksums.txt on that channel would defeat the check.
set -eu

# --- configuration -----------------------------------------------------------

# Default release tag. Pinned so a bare `./install.sh` is reproducible; override
# with --version <tag>. Bump this constant when cutting a new default release.
DEFAULT_VERSION="v0.1.0"

# Download-base seam. Defaults to the project's GitHub Releases download root;
# tests point it at a local fixture via file://.
BASE="${APS_DIST_BASE_URL:-https://github.com/vadimcomanescu/acceptance-pipeline-kit/releases/download}"

# The two upstream tools this installer places on PATH.
TOOLS="gherkin-parser
gherkin-mutator"

# --- helpers -----------------------------------------------------------------

die() { echo "install.sh: $*" >&2; exit 1; }
log() { echo "install.sh: $*" >&2; }

# detect_platform -- map `uname` output to one of the five supported targets and
# echo "<os>_<arch>". Fails closed (before any download) on anything outside the
# matrix, naming the EXACT detected os and arch strings (AC-004).
detect_platform() {
  _raw_os="$(uname -s)"
  _raw_arch="$(uname -m)"

  case "$_raw_os" in
    Linux)  _os=linux ;;
    Darwin) _os=darwin ;;
    *)      _os="" ;;
  esac

  case "$_raw_arch" in
    x86_64|amd64)  _arch=amd64 ;;
    arm64|aarch64) _arch=arm64 ;;
    *)             _arch="" ;;
  esac

  # Validate against the exact five-target matrix. Any miss is fatal with the
  # raw detected strings echoed (not the mapped ones), so the user sees what
  # their machine actually reports.
  if [ -z "$_os" ] || [ -z "$_arch" ]; then
    die "unsupported platform: os='$_raw_os' arch='$_raw_arch' (detected os/arch is outside the supported matrix: darwin_amd64, darwin_arm64, linux_amd64, linux_arm64, windows_amd64)"
  fi
  case "${_os}_${_arch}" in
    darwin_amd64|darwin_arm64|linux_amd64|linux_arm64|windows_amd64) ;;
    *) die "unsupported platform: os='$_raw_os' arch='$_raw_arch' (resolved ${_os}_${_arch} is outside the supported matrix: darwin_amd64, darwin_arm64, linux_amd64, linux_arm64, windows_amd64)" ;;
  esac

  echo "${_os}_${_arch}"
}

# sha256_of <file> -- echo the SHA-256 hex digest of <file>, using whichever of
# sha256sum / shasum is available.
sha256_of() {
  _f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$_f" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$_f" | cut -d' ' -f1
  else
    die "neither sha256sum nor shasum found; cannot verify downloads"
  fi
}

# expected_sum <checksums-file> <archive-name> -- echo the expected digest for
# <archive-name> from a sha256sum-format checksums file ("<hex>  <name>" lines).
expected_sum() {
  _checksums="$1"; _name="$2"
  # Match the line whose filename field equals <name> exactly (avoid substring
  # collisions between e.g. _amd64 and ..._amd64.zip by anchoring on the field).
  awk -v want="$_name" '{ if ($2 == want) { print $1; found=1 } } END { exit (found ? 0 : 1) }' \
    "$_checksums"
}

# fetch <url> <dest> -- download <url> to <dest> via curl, failing on HTTP error.
fetch() {
  _url="$1"; _dest="$2"
  curl -fsSL "$_url" -o "$_dest" \
    || die "download failed: $_url"
}

# --- argument parsing --------------------------------------------------------

VERSION="$DEFAULT_VERSION"
BIN_DIR="$HOME/.local/bin"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || die "--version requires a tag argument"
      VERSION="$2"; shift 2 ;;
    --version=*)
      VERSION="${1#--version=}"; shift ;;
    --bin-dir)
      [ "$#" -ge 2 ] || die "--bin-dir requires a directory argument"
      BIN_DIR="$2"; shift 2 ;;
    --bin-dir=*)
      BIN_DIR="${1#--bin-dir=}"; shift ;;
    -h|--help)
      cat >&2 <<EOF
Usage: install.sh [--version <tag>] [--bin-dir <dir>]
  --version <tag>   release tag to install (default: $DEFAULT_VERSION)
  --bin-dir <dir>   install directory (default: \$HOME/.local/bin)
Environment:
  APS_DIST_BASE_URL  download base (default: GitHub Releases download root)
EOF
      exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

# --- preflight (must precede any download) -----------------------------------

# Resolve and validate the platform BEFORE touching the network (AC-004).
PLATFORM="$(detect_platform)"
OS="${PLATFORM%_*}"
ARCH="${PLATFORM#*_}"

# Archive extension: zip on windows, tar.gz elsewhere -- matches the builder.
EXT="tar.gz"
if [ "$OS" = "windows" ]; then
  EXT="zip"
fi

command -v curl >/dev/null 2>&1 || die "curl is required to download release assets"

RELEASE_URL="${BASE}/${VERSION}"
log "installing $VERSION for ${OS}_${ARCH} from ${RELEASE_URL}"

# --- download into a trapped temp dir ----------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

CHECKSUMS="$TMP_DIR/checksums.txt"
fetch "${RELEASE_URL}/checksums.txt" "$CHECKSUMS"

# Fetch and verify each tool's archive into the temp dir. Nothing is placed in
# the bin dir until ALL archives have passed checksum verification, so a
# mismatch (AC-003) leaves the bin dir untouched.
for tool in $TOOLS; do
  archive="${tool}_${VERSION}_${OS}_${ARCH}.${EXT}"
  archive_path="$TMP_DIR/$archive"
  log "downloading $archive"
  fetch "${RELEASE_URL}/${archive}" "$archive_path"

  expected="$(expected_sum "$CHECKSUMS" "$archive")" \
    || die "no checksum entry for $archive in checksums.txt"
  actual="$(sha256_of "$archive_path")"
  if [ "$actual" != "$expected" ]; then
    die "checksum mismatch for $archive (expected $expected, got $actual); nothing installed"
  fi
  log "verified $archive ($actual)"
done

# --- extract into the temp dir -----------------------------------------------

# Extraction also stays in the temp dir; the bin dir only receives the final,
# verified binaries via an atomic-ish move below.
for tool in $TOOLS; do
  archive="${tool}_${VERSION}_${OS}_${ARCH}.${EXT}"
  archive_path="$TMP_DIR/$archive"
  extract_dir="$TMP_DIR/extract_${tool}"
  mkdir -p "$extract_dir"
  if [ "$EXT" = "zip" ]; then
    command -v unzip >/dev/null 2>&1 || die "unzip is required to extract $archive"
    unzip -q -o "$archive_path" -d "$extract_dir" || die "failed to extract $archive"
  else
    tar -xzf "$archive_path" -C "$extract_dir" || die "failed to extract $archive"
  fi
done

# --- install into the bin dir ------------------------------------------------

mkdir -p "$BIN_DIR"

for tool in $TOOLS; do
  bin_name="$tool"
  [ "$OS" = "windows" ] && bin_name="$tool.exe"
  src="$TMP_DIR/extract_${tool}/$bin_name"
  [ -f "$src" ] || die "expected binary $bin_name not found inside ${tool} archive"
  chmod +x "$src"
  # Move into place. mv overwrites an existing file, so a second run replaces the
  # binary with a byte-identical one -- idempotent, no duplication (AC-002).
  mv -f "$src" "$BIN_DIR/$bin_name" || die "failed to install $bin_name into $BIN_DIR"
  log "installed $bin_name -> $BIN_DIR/$bin_name"
done

# --- PATH hint ---------------------------------------------------------------

# Print a hint (to stderr) if the bin dir is not already on PATH (AC-002).
case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *) log "note: $BIN_DIR is not on your PATH; add it, e.g.: export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

log "done."
