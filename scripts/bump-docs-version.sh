#!/bin/bash
# bump-docs-version.sh OLD NEW: the docs install NEW instead of OLD - the
# install links, the image, the version samples listed in
# scripts/docs-version.conf - leaving the references that mean an old
# version on purpose (its allow lines). Idempotent. Run by urbex-cli's
# prepare-release workflow (urbforge/urbex-cli#156).
#
#   scripts/bump-docs-version.sh 0.2.0 0.3.0
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 OLD NEW (e.g. 0.2.0 0.3.0)" >&2; exit 2; }
exec python3 "$(dirname "$0")/docs-version.py" bump "$1" "$2"
