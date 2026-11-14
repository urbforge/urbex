#!/usr/bin/env python3
"""Follow a running `urbex bootstrap` or `urbex apply`, one line per change.

    follow-progress.py [--workspace ~/urbex-work] [--every 15] [--native]

Polls `urbex status --progress` (through urbex-op unless --native, or
when urbex-op isn't there) and prints a line only when something changes:

    ▶ Install Gitea and Komodo, pull the other images (about 4m50s left)
    ✓ Install Gitea and Komodo, pull the other images 5m12s
    ✗ Deploy the platform's Stacks (Komodo) failed after 9m03s
    urbex bootstrap: done in 21m40s (2026-11-06 01:02)

It waits up to two minutes for the run to start, then exits with the
last line: 0 done, 1 failed, 2 stopped without finishing (killed, lost
terminal), 3 no run found. Made for an agent's background watch (each
line is an event); it reads no credential.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import time

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
PHASE = re.compile(r"^\s*([✓✗▶·-])\s+(.+?)\s{2,}(.*?)\s*$")
# "urbex bootstrap: running ...", "urbex apply staging (my-app): done ..."
HEADER = re.compile(r"^urbex (\w+)[^:]*: (running|done|failed|stopped)")


def snapshot(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None, {}
    lines = [ANSI.sub("", l) for l in out.splitlines()]
    header = next((l.strip() for l in lines if HEADER.match(l.strip())), None)
    phases = {}
    for l in lines:
        m = PHASE.match(l)
        if m:
            phases[m.group(2)] = (m.group(1), m.group(3))
    return header, phases


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workspace", default=os.environ.get("URBEX_WORKSPACE", "~/urbex-work"))
    ap.add_argument("--every", type=int, default=15, help="seconds between checks")
    ap.add_argument("--native", action="store_true", help="run urbex directly, not through urbex-op")
    args = ap.parse_args()
    op = shutil.which("urbex-op")
    if op and not args.native:
        cmd = [op, "-w", os.path.expanduser(args.workspace), "urbex status --progress"]
    elif shutil.which("urbex"):
        cmd = ["urbex", "status", "--progress"]
    else:
        print("neither urbex-op nor urbex found", flush=True)
        sys.exit(3)

    deadline = time.time() + 120
    while True:
        header, phases = snapshot(cmd)
        if header and HEADER.match(header).group(2) == "running":
            break
        if time.time() > deadline:
            print(header or "no urbex bootstrap or apply run found", flush=True)
            sys.exit(3)
        time.sleep(5)

    print(header.split(",")[0], flush=True)
    seen = {}
    while True:
        for name, (mark, detail) in phases.items():
            if seen.get(name, (None,))[0] == mark:
                continue
            if mark == "▶":
                left = re.search(r"about (\S+) left", detail)
                print(f"▶ {name}" + (f" (about {left.group(1)} left)" if left else ""), flush=True)
            elif mark in "✓✗":
                print(f"{mark} {name} {detail}", flush=True)
            elif mark == "-" and name not in seen:
                print(f"- {name}: {detail}", flush=True)
            seen[name] = (mark, detail)
        state = HEADER.match(header).group(2) if header else "running"
        if state != "running":
            print(header, flush=True)
            sys.exit({"done": 0, "failed": 1, "stopped": 2}[state])
        time.sleep(args.every)
        new_header, new_phases = snapshot(cmd)
        if new_header:  # a failed poll (container hiccup) keeps the last state
            header, phases = new_header, new_phases


if __name__ == "__main__":
    main()
