# Sourced, hidden, by readme.tape before it records: a short prompt, and
# urbex's output as the GIF shows it.
#
# - Ansible's and Terraform's own lines are left out: apply runs them,
#   and the GIF cuts the wait while they run (Hide/Show in the tape).
# - LAN addresses are replaced: nothing private on screen.
# - `urbex status` (no environment) shows only the projects, each line
#   cut at the terminal's width.
export PS1='> '
export COLUMNS=100
demo_filter() {
  grep --line-buffered -v -E '^(TASK|PLAY|ok:|changed:|skipping:|included:|\[WARNING\]|\s*$|.*: ok=[0-9]+ .*)' |
    sed -u -E 's/192\.168\.[0-9]+\.[0-9]+/<lan>/g'
}
urbex() {
  if [ "$*" = status ]; then
    command urbex status 2>&1 | sed -n '/^Projects:/,$p' | demo_filter | cut -c1-"$COLUMNS"
    return "${PIPESTATUS[0]}"
  fi
  command urbex "$@" 2>&1 | demo_filter
  return "${PIPESTATUS[0]}"
}
