# Sourced, hidden, by readme.tape before it records: a short prompt, and
# urbex's output as the GIF shows it.
#
# - Ansible's and Terraform's own lines are left out: apply runs them,
#   and the GIF cuts the wait while they run (Hide/Show in the tape).
#   Their colours go first, or the patterns below miss the lines.
# - LAN addresses are replaced: nothing private on screen.
# - `urbex status` (no environment) shows the platform's services with
#   their public addresses (its Endpoints section, without the internal
#   and LAN columns), then the demo's lines of its Projects section,
#   without the internal names and the LAN addresses, to fit the terminal.
# - Colours lead the eye: the command typed in bold, what each command
#   ends with (deployed, released, running) in green, the public
#   addresses in cyan, the new versions in yellow, the plumbing (LAN
#   addresses, image references) dimmed.
export COLUMNS=100
# The prompt in mauve, the command typed in bold; PS0 resets the colour
# before the command's output.
PS1='\[\e[1;35m\]> \[\e[0;1m\]'
PS0='\[\e[0m\]'

demo_filter() {
  sed -u -E 's/\x1b\[[0-9;?]*[A-Za-z]//g' |
    grep --line-buffered -v -E '^(TASK|PLAY|ok:|changed:|skipping:|included:|\[WARNING\]|\s*$|.*: ok=[0-9]+ .*)' |
    grep --line-buffered -v -E '^(module\.|data\.|Apply complete|Outputs:|hostnames|ip_addresses|vmids|lxc_|\s+"|\s*\]\)?|\s*\}|Initializing|Terraform|- |Plan:|Saved the plan|To perform|Note:|plan\. |\s*[#+~-] |\s+[a-z_]+\s+= )' |
    sed -u -E 's/192\.168\.[0-9]+\.[0-9]+/<lan>/g'
}

demo_color() {
  local G=$'\e[1;32m' C=$'\e[36m' Y=$'\e[1;33m' D=$'\e[90m' B=$'\e[1m' R=$'\e[0m'
  sed -u -E \
    -e "s/^((Deployed|Released) .*:)$/$G\1$R/" \
    -e "s/^(Platform:|Projects:|  demo \([a-z]+\))$/$B\1$R/" \
    -e "s#(http://<lan>:[0-9]+)#$D\1$R#g" \
    -e "s#(\(git\.[^ ]*\))#$D\1$R#g" \
    -e "s#(https://[^ )]+[^ ).])#$C\1$R#g" \
    -e "s/(-> )([0-9][^ ]*)/\1$Y\2$R/" \
    -e "s/(version=)([^ ]+)/\1$Y\2$R/" \
    -e "s/(stack=running)/$G\1$R/"
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
        sed -E 's/ dns=[^ ]*//; s/ image=[^ ]*//; s# +http://[0-9.]+:[0-9]+##; s/([^ ]) {3,}/\1  /g'
    } | demo_filter | cut -c1-"$COLUMNS" | demo_color
    return 0
  fi
  command urbex "$@" 2>&1 | demo_filter | demo_color
  return "${PIPESTATUS[0]}"
}

# The app's answer: its first line in green.
curl() {
  command curl -s "$@" | sed -E $'1s/.*/\e[1;32m&\e[0m/'
}
