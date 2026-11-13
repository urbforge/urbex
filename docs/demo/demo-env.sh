# Sourced, hidden, by readme.tape before it records: a short prompt, and
# urbex's output as the GIF shows it.
#
# - Ansible's and Terraform's own lines are left out: apply runs them,
#   and the GIF cuts the wait while they run (Hide/Show in the tape).
# - LAN addresses are replaced: nothing private on screen.
# - `urbex status` (no environment) shows the platform's services with
#   their public addresses (its Endpoints section, without the internal
#   and LAN columns), then the demo's lines of its Projects section, with
#   the runs of spaces between columns shortened and the internal names
#   left out, to fit the terminal.
export PS1='> '
export COLUMNS=100
demo_filter() {
  grep --line-buffered -v -E '^(TASK|PLAY|ok:|changed:|skipping:|included:|\[WARNING\]|\s*$|.*: ok=[0-9]+ .*)' |
    grep --line-buffered -v -E '^(module\.|data\.|Apply complete|Outputs:|hostnames|ip_addresses|vmids|lxc_|\s+"|\s*\]\)?|\s*\}|Initializing|Terraform|- |Plan:|Saved the plan|To perform|Note:|plan\. |\s+[#+~-] )' |
    sed -u -E 's/192\.168\.[0-9]+\.[0-9]+/<lan>/g'
}
urbex() {
  if [ "$*" = status ]; then
    local out
    out=$(command urbex status 2>&1)
    {
      echo "Platform:"
      printf '%s\n' "$out" | sed -n '/^Endpoints:/,/^$/p' | grep '^  ' | grep -v 'webhooks' |
        awk '{ name = $0; sub(/ +http:\/\/.*/, "", name); sub(/^ +/, "", name)
               url = "-"; for (i = 1; i <= NF; i++) if ($i ~ /^https:\/\//) { url = $i; break }
               printf "  %-28s %s\n", name, url }'
      echo
      printf '%s\n' "$out" | sed -n '/^Projects:/,$p' |
        awk '/^Projects:/ || /^  demo / { keep = 1 } /^  [a-z]/ && !/^  demo / { keep = 0 } keep' |
        sed -E 's/ dns=[^ ]*//; s/ image=[^ ]*//; s/([^ ]) {3,}/\1  /g'
    } | demo_filter | cut -c1-"$COLUMNS"
    return 0
    return "${PIPESTATUS[0]}"
  fi
  command urbex "$@" 2>&1 | demo_filter
  return "${PIPESTATUS[0]}"
}
