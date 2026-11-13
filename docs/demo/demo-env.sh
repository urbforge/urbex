# Sourced, hidden, by readme.tape before it records: a short prompt, and
# urbex's output as the GIF shows it.
#
# - Ansible's and Terraform's own lines are left out: apply runs them,
#   and the GIF cuts the wait while they run (Hide/Show in the tape).
# - LAN addresses are replaced: nothing private on screen.
# - `urbex status` (no environment) shows only the demo's lines of its
#   Projects section, with the runs of spaces between columns shortened
#   and the internal names left out, to fit the terminal.
export PS1='> '
export COLUMNS=100
demo_filter() {
  grep --line-buffered -v -E '^(TASK|PLAY|ok:|changed:|skipping:|included:|\[WARNING\]|\s*$|.*: ok=[0-9]+ .*)' |
    grep --line-buffered -v -E '^(module\.|data\.|Apply complete|Outputs:|hostnames|ip_addresses|vmids|lxc_|\s+"|\s*\]\)?|\s*\}|Initializing|Terraform|- |Plan:|Saved the plan|To perform|Note:|plan\. |\s+[#+~-] )' |
    sed -u -E 's/192\.168\.[0-9]+\.[0-9]+/<lan>/g'
}
urbex() {
  if [ "$*" = status ]; then
    command urbex status 2>&1 | sed -n '/^Projects:/,$p' |
      awk '/^Projects:/ || /^  demo / { keep = 1 } /^  [a-z]/ && !/^  demo / { keep = 0 } keep' |
      demo_filter | sed -E 's/ dns=[^ ]*//; s/ image=[^ ]*//; s/([^ ]) {3,}/\1  /g' | cut -c1-"$COLUMNS"
    return "${PIPESTATUS[0]}"
  fi
  command urbex "$@" 2>&1 | demo_filter
  return "${PIPESTATUS[0]}"
}
