#!/usr/bin/env bash
# Install the APS-supplied Go binaries (gherkin-parser, gherkin-mutator) into
# ${GOBIN:-$(go env GOPATH)/bin}. Requires Go on PATH.
#
# The upstream repo declares a non-canonical module path, so `go install
# github.com/...@latest` does not work. We clone into a temp dir and run
# `go install` from there.
set -euo pipefail

if ! command -v go >/dev/null 2>&1; then
  echo "go is required to install the APS binaries; install Go and re-run." >&2
  exit 1
fi

repo_url="https://github.com/unclebob/Acceptance-Pipeline-Specification.git"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

echo "cloning APS into $work_dir..."
git clone --depth 1 "$repo_url" "$work_dir/aps" >/dev/null

bin_dir="${GOBIN:-$(go env GOPATH)/bin}"
mkdir -p "$bin_dir"

echo "building gherkin-parser..."
(cd "$work_dir/aps" && go build -o "$bin_dir/gherkin-parser" ./cmd/gherkin-parser)
echo "building gherkin-mutator..."
(cd "$work_dir/aps" && go build -o "$bin_dir/gherkin-mutator" ./cmd/gherkin-mutator)

echo
echo "installed into: ${bin_dir}"
echo "add ${bin_dir} to PATH if it is not already there."
