#!/usr/bin/env python3
"""Check that the docs install the right release of urbex (urbforge/urbex#112).

The files and patterns are in scripts/docs-version.conf, shared with the
release preparation's bump (urbforge/urbex-cli#156).

  scripts/docs-version.py list
      every version reference: file:line: version
  scripts/docs-version.py check --tag v0.3.0
      on a release tag: every reference names 0.3.0
  scripts/docs-version.py check --latest v0.2.0 [--branch docs/release-v0.3.0]
      on a pull request: the references agree, and name no version newer
      than the latest tag - except the one a docs/release-vX.Y.Z branch
      prepares
  scripts/docs-version.py bump 0.2.0 0.3.0
      the release preparation (urbforge/urbex-cli#156): every reference
      to 0.2.0 names 0.3.0, the allowed lines stay; then every reference
      must name 0.3.0. Running it again changes nothing.

Options: --root DIR (default: the repository), --conf FILE.
Exit status: 0 ok, 1 a check failed, 2 a usage or configuration error.
"""

import argparse
import os
import re
import sys

VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$")


def parse_version(s):
    m = VERSION.match(s.lstrip("v"))
    if not m:
        raise ValueError("not a version: %r" % s)
    major, minor, patch, pre = m.groups()
    # A pre-release sorts before its release: 0.3.0-rc.1 < 0.3.0.
    return (int(major), int(minor), int(patch), pre is None, pre or "")


def load_conf(path):
    files, matches, allows = [], [], []
    with open(path) as f:
        for n, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            kind, _, rest = line.partition(" ")
            try:
                if kind == "file":
                    files.append(rest.strip())
                elif kind in ("match", "allow"):
                    scope, regex = None, rest
                    first, _, after = rest.partition(" ")
                    if first in files and after:
                        scope, regex = first, after
                    elif kind == "allow":
                        raise ValueError("allow needs a listed file first")
                    compiled = re.compile(regex)
                    if kind == "match" and compiled.groups < 1:
                        raise ValueError("match needs a group: the version")
                    (matches if kind == "match" else allows).append((scope, compiled))
                else:
                    raise ValueError("unknown entry %r" % kind)
            except (ValueError, re.error) as err:
                sys.exit("%s:%d: %s" % (path, n, err))
    return files, matches, allows


def references(root, conf):
    """Yields (file, line number, version, line) for every reference."""
    files, matches, allows = conf
    for name in files:
        path = os.path.join(root, name)
        if not os.path.exists(path):
            sys.exit("%s: listed in the configuration but missing" % name)
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                line = line.rstrip("\n")
                if any(s == name and r.search(line) for s, r in allows):
                    continue
                seen = set()
                for scope, regex in matches:
                    if scope not in (None, name):
                        continue
                    for m in regex.finditer(line):
                        if m.start(1) in seen:
                            continue
                        seen.add(m.start(1))
                        yield name, n, m.group(1), line


def bump(root, conf, old, new):
    """Replaces old with new in every reference; returns the lines changed,
    as file:line."""
    files, matches, allows = conf
    changed = []
    for name in files:
        path = os.path.join(root, name)
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
        touched = False
        for i, line in enumerate(lines):
            if any(s == name and r.search(line) for s, r in allows):
                continue
            spans = set()
            for scope, regex in matches:
                if scope not in (None, name):
                    continue
                for m in regex.finditer(line):
                    if m.group(1) == old:
                        spans.add(m.span(1))
            if not spans:
                continue
            for start, end in sorted(spans, reverse=True):
                line = line[:start] + new + line[end:]
            lines[i] = line
            touched = True
            changed.append("%s:%d" % (name, i + 1))
        if touched:
            with open(path, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))
    return changed


def check(refs, tag=None, latest=None, branch=None):
    """Returns the problems found, one line each."""
    if not refs:
        return ["no version reference found: is scripts/docs-version.conf still right?"]
    problems = []
    if tag:
        want = tag.lstrip("v")
        for name, n, version, _ in refs:
            if version != want:
                problems.append("%s:%d: names %s, expected %s (the tag %s)" % (name, n, version, want, tag))
        return problems

    counts = {}
    for _, _, version, _ in refs:
        counts[version] = counts.get(version, 0) + 1
    if len(counts) > 1:
        common = max(counts, key=lambda v: (counts[v], parse_version(v)))
        for name, n, version, _ in refs:
            if version != common:
                problems.append("%s:%d: names %s, expected %s like the other %d references" % (name, n, version, common, counts[common]))
        return problems

    version = next(iter(counts))
    if latest and parse_version(version) > parse_version(latest):
        prepared = None
        m = re.match(r"^docs/release-v(.+)$", branch or "")
        if m:
            prepared = m.group(1)
        if version != prepared:
            name, n, _, _ = refs[0]
            where = "the branch %s prepares %s" % (branch, prepared) if prepared else "only a docs/release-v%s branch may name it" % version
            problems.append("%s:%d and the other references: name %s, newer than the latest tag %s; %s" % (name, n, version, latest, where))
    return problems


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("command", choices=["list", "check", "bump"])
    p.add_argument("versions", nargs="*", help="bump: the old and the new version")
    p.add_argument("--root", default=os.path.dirname(here))
    p.add_argument("--conf", default=None)
    p.add_argument("--tag", help="a release tag, vX.Y.Z: every reference names it")
    p.add_argument("--latest", help="the latest release tag, for a pull request")
    p.add_argument("--branch", help="the pull request's branch")
    a = p.parse_args(argv)
    try:
        for v in (a.tag, a.latest):
            if v:
                parse_version(v)
    except ValueError as err:
        p.error(str(err))

    conf = load_conf(a.conf or os.path.join(here, "docs-version.conf"))
    if a.command == "bump":
        if len(a.versions) != 2:
            p.error("bump needs the old and the new version: bump 0.2.0 0.3.0")
        old, new = (v.lstrip("v") for v in a.versions)
        for v in (old, new):
            try:
                parse_version(v)
            except ValueError as err:
                p.error(str(err))
        changed = bump(a.root, conf, old, new)
        for where in changed:
            print("%s: %s -> %s" % (where, old, new))
        problems = check(list(references(a.root, conf)), tag="v" + new)
        for line in problems:
            print(line)
        if problems:
            print("Some references name neither %s nor %s: fix them by hand." % (old, new), file=sys.stderr)
            return 1
        print("ok: %s" % ("%d lines now name %s" % (len(changed), new) if changed else "every reference names %s already" % new))
        return 0
    elif a.versions:
        p.error("only bump takes versions")
    refs = list(references(a.root, conf))
    if a.command == "list":
        for name, n, version, _ in refs:
            print("%s:%d: %s" % (name, n, version))
        return 0

    problems = check(refs, tag=a.tag, latest=a.latest, branch=a.branch)
    for line in problems:
        print(line)
    if problems:
        print("The docs must name the release they install: fix the lines above (scripts/docs-version.conf lists where).", file=sys.stderr)
        return 1
    versions = sorted({r[2] for r in refs})
    print("ok: %d references in the docs name %s" % (len(refs), ", ".join(versions)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
