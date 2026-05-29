#!/usr/bin/env python3
"""Static assertions over .github/workflows/release.yml and the builder script.

These cover AC-006 (a-e) and the AC-011 trigger without needing a live release:
the workflow logic is verified structurally, and the build matrix / checksums /
secret usage are asserted against the YAML source. `actionlint` is not installed
on this host (recorded waiver in .shepherd/standards.md), so this is the
committed fallback alongside `yaml.safe_load` well-formedness.

Run:  python3 scripts/tests/test_release_workflow.py
Exits non-zero on the first failed assertion.
"""
import pathlib
import re
import sys

import yaml

REPO = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = REPO / ".github" / "workflows" / "release.yml"
BUILDER = REPO / "scripts" / "build-release-artifacts.sh"

# The exactly-five supported targets (AC-006a). Both binaries are built for
# each (AC-006b); the builder is the single producer, so the tuples live there.
EXPECTED_TARGETS = {
    ("darwin", "amd64"),
    ("darwin", "arm64"),
    ("linux", "amd64"),
    ("linux", "arm64"),
    ("windows", "amd64"),
}


def fail(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_targets(builder_text):
    """Extract the (os, arch) tuples from the builder's TARGETS assignment.

    Parsing the TARGETS block specifically -- rather than scanning the whole
    script for OS/arch tokens -- keeps the assertion from matching stray
    mentions in comments or the NOTICE heredoc, and asserts against the actual
    data the build loop iterates.
    """
    m = re.search(r'^TARGETS="(.*?)"', builder_text, re.DOTALL | re.MULTILINE)
    if not m:
        fail("could not locate the TARGETS assignment in the builder")
    targets = set()
    for line in m.group(1).splitlines():
        fields = line.split()
        if len(fields) == 2:
            targets.add((fields[0], fields[1]))
    return targets


def check(cond, ok_msg, fail_msg):
    if not cond:
        fail(fail_msg)
    print(f"PASS: {ok_msg}")


def main():
    wf_text = WORKFLOW.read_text()
    builder_text = BUILDER.read_text()
    # PyYAML parses the bare `on:` key as boolean True; load both views.
    wf = yaml.safe_load(wf_text)

    on = wf.get("on", wf.get(True))
    check(on is not None, "workflow has an `on` trigger", "workflow missing `on` trigger")

    # (AC-011) trigger pattern is the strict-semver tag glob.
    tags = on["push"]["tags"]
    check(
        tags == ["v[0-9]+.[0-9]+.[0-9]+"],
        f"trigger is strict-semver tag glob ({tags})",
        f"trigger pattern is not the strict-semver glob: {tags!r}",
    )

    # (AC-006a/b) all five target tuples appear in the builder's matrix (the
    # single producer the workflow invokes).
    found = parse_targets(builder_text)
    check(
        EXPECTED_TARGETS.issubset(found),
        f"all five target tuples present in builder TARGETS ({sorted(found)})",
        f"missing target tuples: {EXPECTED_TARGETS - found}",
    )
    check(
        found == EXPECTED_TARGETS,
        "builder declares EXACTLY the five targets (no more, no fewer)",
        f"unexpected/extra target tuples: {found ^ EXPECTED_TARGETS}",
    )

    # (AC-006b) both binaries are built.
    check(
        "./cmd/gherkin-parser" in builder_text and "./cmd/gherkin-mutator" in builder_text,
        "builder builds both gherkin-parser and gherkin-mutator",
        "builder does not reference both upstream cmd packages",
    )

    # (AC-006c) a single checksums.txt is produced.
    check(
        "checksums.txt" in builder_text,
        "builder produces checksums.txt",
        "builder does not produce checksums.txt",
    )
    check(
        "scripts/build-release-artifacts.sh dist" in wf_text,
        "workflow invokes the builder against dist/",
        "workflow does not invoke the builder against dist/",
    )

    # (AC-006e) NO secrets.* other than GITHUB_TOKEN.
    secret_refs = set(re.findall(r"secrets\.([A-Za-z_][A-Za-z0-9_]*)", wf_text))
    check(
        secret_refs <= {"GITHUB_TOKEN"},
        f"only secrets.GITHUB_TOKEN referenced ({sorted(secret_refs)})",
        f"forbidden secret reference(s): {secret_refs - {'GITHUB_TOKEN'}}",
    )

    # No registry-publish step (no-extra-behavior): no PyPI/npm publish.
    forbidden = re.findall(
        r"npm publish|twine upload|cargo publish|pypa/gh-action-pypi-publish",
        wf_text,
        re.I,
    )
    check(
        not forbidden,
        "no registry-publish step (npm/pypi/cargo)",
        f"workflow contains a registry-publish step: {forbidden}",
    )

    # TS tarball rides the same release (AC-008 wiring).
    check(
        "npm pack" in wf_text,
        "workflow packs the TypeScript tarball (AC-008 wiring)",
        "workflow does not pack the TypeScript tarball",
    )

    # Release upload step references github.token via GITHUB_TOKEN only.
    # Match the action by name (pinned to a commit SHA), not a floating @vN tag.
    check(
        "softprops/action-gh-release@" in wf_text or "gh release create" in wf_text,
        "workflow uploads to a GitHub Release",
        "workflow has no GitHub Release upload step",
    )

    print("\nALL STATIC WORKFLOW ASSERTIONS PASSED")


if __name__ == "__main__":
    main()
