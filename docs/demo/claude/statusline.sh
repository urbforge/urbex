#!/bin/bash
# Claude Code's status line in claude.tape: "● ready" when Claude waits
# for the user - the tape waits for it - else "○ working". The hooks in
# settings.json set the state when a prompt is sent and when Claude
# stops; while bin/urbex runs (in the background, say) it is working
# whatever the hooks said.
pid=$(cat /tmp/claude-demo-urbex.pid 2>/dev/null)
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  echo '○ working'
else
  cat /tmp/claude-demo-state 2>/dev/null || echo '● ready'
fi
