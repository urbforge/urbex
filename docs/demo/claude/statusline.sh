#!/bin/bash
# Claude Code's status line in claude.tape: "● ready" when Claude waits
# for the user - the tape waits for it - else "○ working". The hooks in
# settings.json set the state when a prompt is sent and when Claude
# stops. While an urbex command (bin/urbex) or the skill's progress
# follower runs in the background it is working whatever the hooks said,
# and for 10 seconds after: the time Claude takes to be told it ended
# and start on it.
busy=
for f in /tmp/claude-demo-urbex/*; do
  [ -f "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null && busy=1
done
pgrep -f follow-progress.py >/dev/null && busy=1
if [ -n "$busy" ]; then
  date +%s >/tmp/claude-demo-busy
fi
last=$(cat /tmp/claude-demo-busy 2>/dev/null || echo 0)
if [ $(($(date +%s) - last)) -lt 10 ]; then
  echo '○ working'
else
  cat /tmp/claude-demo-state 2>/dev/null || echo '● ready'
fi
