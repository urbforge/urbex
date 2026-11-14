#!/bin/bash
# Checks the plugin's Python scripts on the oldest Python they support,
# 3.8, in a container (podman or docker), with no network:
#   - each script parses as Python 3.8 and prints its --help;
#   - the helpers that took 3.9+ features work (urbforge/urbex#56).
# Python 3.8 parses some 3.9+ code fine and fails only when it runs (a
# method such as str.removeprefix), so a new helper gets a line below.
#
#   tests/plugin-scripts.sh
set -euo pipefail

cd "$(dirname "$0")/.."
engine=$(command -v podman || command -v docker) || { echo "needs podman or docker" >&2; exit 1; }
image=${PYTHON_IMAGE:-docker.io/library/python:3.8-slim}

"$engine" run --rm -i --network none -v "$PWD/skills:/skills:ro,Z" "$image" python - <<'PY'
import ast, glob, importlib.util, subprocess, sys

assert sys.version_info[:2] == (3, 8), sys.version
failed = False
for path in sorted(glob.glob("/skills/*/*.py")):
    with open(path) as f:
        source = f.read()
    try:
        ast.parse(source, path, feature_version=(3, 8))
        subprocess.run([sys.executable, path, "--help"], check=True, capture_output=True, timeout=30)
        print("ok  ", path)
    except Exception as err:
        failed = True
        print("FAIL", path, err, getattr(err, "stderr", b"").decode()[-500:])

def load(path):
    spec = importlib.util.spec_from_file_location("m", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

prepare = load("/skills/setup/prepare-proxmox.py")
for arg, want in [
    ("https://pve.example.com:8006/", ("pve.example.com", 8006)),
    ("pve.example.com", ("pve.example.com", 8006)),
    ("192.0.2.10:8007", ("192.0.2.10", 8007)),
    ("http://pve", ("pve", 8006)),
]:
    got = prepare.parse_host(arg)
    if got != want:
        failed = True
        print("FAIL parse_host(%r) = %r, want %r" % (arg, got, want))
print("ok   prepare-proxmox.py parse_host")

follow = load("/skills/cli/follow-progress.py")
for line, want in [
    ("urbex bootstrap: running for 2m, about 18m left (started 10:02)", "running"),
    ("urbex apply staging (my-app): done in 9m12s", "done"),
    ("urbex destroy prod (my-app): failed after 30s", "failed"),
]:
    m = follow.HEADER.match(line)
    if not m or m.group(2) != want:
        failed = True
        print("FAIL HEADER on %r" % line)
print("ok   follow-progress.py HEADER")
sys.exit(1 if failed else 0)
PY
