#!/usr/bin/env python3
"""Static assertions over .github/workflows/release.yml and the builder script.

These cover AC-006 (a-e), the AC-011 trigger, and release-contract assertions
without needing a live release: the workflow logic is verified structurally,
and the build matrix / checksums / secret usage are asserted against the YAML
source. `actionlint` is not installed on this host (recorded waiver in
.shepherd/standards.md), so this is the committed fallback alongside
`yaml.safe_load` well-formedness.

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

# The exactly-four supported targets (AC-006a). Both binaries are built for
# each (AC-006b); the builder is the single producer, so the tuples live there.
EXPECTED_TARGETS = {
    ("darwin", "amd64"),
    ("darwin", "arm64"),
    ("linux", "amd64"),
    ("linux", "arm64"),
}

EXPECTED_ACTIONS = {
    "actions/checkout": "v6.0.2",
    "actions/setup-go": "v6.4.0",
    "actions/setup-node": "v6.4.0",
    "softprops/action-gh-release": "v3.0.0",
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


def action_pin(action, workflow_text):
    m = re.search(
        rf"uses:\s+{re.escape(action)}@([0-9a-f]{{40}})\s+#\s+(v[0-9]+\.[0-9]+\.[0-9]+)",
        workflow_text,
    )
    if not m:
        fail(f"{action} is not pinned to a 40-char SHA with a version comment")
    return m.group(1), m.group(2)


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

    # (AC-006a/b) all four target tuples appear in the builder's matrix (the
    # single producer the workflow invokes).
    found = parse_targets(builder_text)
    check(
        EXPECTED_TARGETS.issubset(found),
        f"all four target tuples present in builder TARGETS ({sorted(found)})",
        f"missing target tuples: {EXPECTED_TARGETS - found}",
    )
    check(
        found == EXPECTED_TARGETS,
        "builder declares EXACTLY the four supported targets (no more, no fewer)",
        f"unexpected/extra target tuples: {found ^ EXPECTED_TARGETS}",
    )
    forbidden_artifact_refs = re.findall(
        r"\bwindows\b|windows_|windows/|\.exe|zip -|archive_ext|_archive_ext",
        builder_text + wf_text,
        re.I,
    )
    check(
        not forbidden_artifact_refs,
        "release workflow and builder do not teach Windows artifacts",
        f"release workflow or builder still references Windows artifacts: {forbidden_artifact_refs}",
    )
    check(
        '"$OUT_DIR"/*.zip' in builder_text,
        "builder deletes stale zip artifacts from reused output dirs",
        "builder does not delete stale zip artifacts from reused output dirs",
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

    for action, expected_version in EXPECTED_ACTIONS.items():
        _, version = action_pin(action, wf_text)
        check(
            version == expected_version,
            f"{action} is SHA-pinned with comment {version}",
            f"{action} comment is {version}, expected {expected_version}",
        )

    check(
        "node-version: '24'" in wf_text,
        "workflow uses Node 24 for the TypeScript package build",
        "workflow does not set node-version: '24'",
    )
    check(
        "node-version: 'latest'" not in wf_text,
        "workflow does not use floating latest Node",
        "workflow uses floating latest Node",
    )
    check(
        "typescript/package.json" in wf_text
        and "EXPECTED_TAG=\"v$PACKAGE_VERSION\"" in wf_text
        and "GITHUB_REF_NAME" in wf_text,
        "workflow preflights github.ref_name against typescript/package.json version",
        "workflow does not preflight release tag against TypeScript package version",
    )
    check(
        wf_text.index("Verify release tag matches TypeScript package version")
        < wf_text.index("Build release archives + checksums")
        < wf_text.index("Publish GitHub Release"),
        "version preflight runs before artifacts are built and published",
        "version preflight is not before build/publish steps",
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
