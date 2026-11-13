#!/bin/bash
# Records the README's GIF (docs/demo/readme.gif) on a platform, with a
# fresh project made from examples/demo. See docs/demo/README.md.
#
#   record.sh <workspace>
#
# <workspace> is an urbex-op workspace (tools/operator in urbex-cli) with
# the platform's credentials. The image to start from is
# URBEX_OPERATOR_IMAGE (default urbex-operator), built by
# 'mise run operator-image' in urbex-cli; urbex-op is found on PATH or as
# URBEX_OP.
set -euo pipefail
WS=$(cd "${1:?usage: record.sh <workspace>}" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=${URBEX_OPERATOR_IMAGE:-urbex-operator}
OP=${URBEX_OP:-urbex-op}
ENGINE=$(command -v podman || command -v docker)

# The project, as a repo of its own: apply pushes it to Gitea.
rm -rf "$WS/demo" && mkdir -p "$WS/demo"
cp -r "$HERE/../../examples/demo" "$WS/demo/app"
cp "$HERE/demo-env.sh" "$HERE/readme.tape" "$WS/demo/"
git -C "$WS/demo/app" init -q -b main
git -C "$WS/demo/app" add -A
git -C "$WS/demo/app" -c user.name=urbex -c user.email=urbex@localhost commit -qm "The Urbex demo"

"$ENGINE" build -q -t urbex-operator-demo --build-arg "BASE=$BASE" -f "$HERE/Containerfile" "$HERE"

# Production first, outside the recording: promote needs it applied.
URBEX_OPERATOR_IMAGE=$BASE "$OP" -w "$WS" 'cd /work/demo/app && urbex apply prod'
URBEX_OPERATOR_IMAGE=urbex-operator-demo "$OP" -w "$WS" 'cd /work/demo && vhs readme.tape'
cp "$WS/demo/readme.gif" "$HERE/readme.gif"
ls -l "$HERE/readme.gif"
