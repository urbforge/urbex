#!/bin/bash
# Records the README's GIF (docs/demo/readme.gif) on a platform, with a
# fresh project made from examples/demo. See docs/demo/README.md.
#
#   record.sh <workspace> [readme|claude]
#
# readme (the default) records readme.tape, the CLI typed by hand;
# claude records claude.tape, the same flow asked of Claude Code with
# Urbex's plugin. claude logs in as CLAUDE_CODE_OAUTH_TOKEN (from
# 'claude setup-token') if set, else with a copy of
# ~/.claude/.credentials.json, deleted when the recording ends.
#
# <workspace> is an urbex-op workspace (tools/operator in urbex-cli) with
# the platform's credentials. The image to start from is
# URBEX_OPERATOR_IMAGE (default urbex-operator), built by
# 'mise run operator-image' in urbex-cli; urbex-op is found on PATH or as
# URBEX_OP.
set -euo pipefail
WS=$(cd "${1:?usage: record.sh <workspace> [readme|claude]}" && pwd)
TAPE=${2:-readme}
case $TAPE in readme | claude) ;; *) echo "record.sh: no tape $TAPE" >&2; exit 1 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=${URBEX_OPERATOR_IMAGE:-urbex-operator}
OP=${URBEX_OP:-urbex-op}
ENGINE=$(command -v podman || command -v docker)

# The project, as a repo of its own: apply pushes it to Gitea.
rm -rf "$WS/demo" && mkdir -p "$WS/demo"
cp -r "$HERE/../../examples/demo" "$WS/demo/app"
cp "$HERE/demo-env.sh" "$HERE/$TAPE.tape" "$WS/demo/"
git -C "$WS/demo/app" init -q -b main
git -C "$WS/demo/app" add -A
git -C "$WS/demo/app" -c user.name=urbex -c user.email=urbex@localhost commit -qm "The Urbex demo"

if [ "$TAPE" = claude ]; then
  # The plugin as this checkout has it, Claude Code's settings, and its
  # login - never left behind.
  mkdir -p "$WS/demo/plugin"
  cp -r "$HERE/../../.claude-plugin" "$HERE/../../skills" "$HERE/../../docs" "$HERE/../../schemas" "$WS/demo/plugin/"
  cp -r "$HERE/bin" "$HERE/claude-env.sh" "$WS/demo/"
  C=$WS/demo/claude-home
  mkdir -m 700 "$C"
  trap 'rm -f "$C/.credentials.json" "$C/oauth-token"' EXIT
  cp "$HERE/claude/settings.json" "$HERE/claude/statusline.sh" "$C/"
  printf '{"hasCompletedOnboarding":true,"projects":{"/work/demo/app":{"hasTrustDialogAccepted":true}}}\n' >"$C/.claude.json"
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    (umask 077 && printf %s "$CLAUDE_CODE_OAUTH_TOKEN" >"$C/oauth-token")
  elif [ -f "$HOME/.claude/.credentials.json" ]; then
    install -m 600 "$HOME/.claude/.credentials.json" "$C/.credentials.json"
  else
    echo "record.sh: no Claude Code login - set CLAUDE_CODE_OAUTH_TOKEN ('claude setup-token') or log in with claude" >&2
    exit 1
  fi
fi

"$ENGINE" build -q -t urbex-operator-demo --build-arg "BASE=$BASE" -f "$HERE/Containerfile" "$HERE"

# Production first, outside the recording: promote needs it applied.
URBEX_OPERATOR_IMAGE=$BASE "$OP" -w "$WS" 'cd /work/demo/app && urbex apply prod'
URBEX_OPERATOR_IMAGE=urbex-operator-demo "$OP" -w "$WS" "cd /work/demo && vhs $TAPE.tape"
cp "$WS/demo/$TAPE.gif" "$HERE/$TAPE.gif"
ls -l "$HERE/$TAPE.gif"
