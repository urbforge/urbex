# Sourced, hidden, by readme.tape before it records: a short prompt, and
# urbex's output as the GIF shows it.
#
# - Ansible's and Terraform's own lines are left out: apply runs them,
#   and the GIF cuts the wait while they run (Hide/Show in the tape).
#   Their colours go first, or the patterns below miss the lines; of
#   apply, only urbex's own lines are kept (demo_apply_lines).
# - LAN addresses are replaced, and the platform's domain shows as
#   example.com: nothing private on screen. The tape types example.com
#   too; curl asks the real domain, read from the workspace's
#   gitops/urbex.platform.yaml.
# - `urbex status` (no environment) shows the platform's services with
#   their public addresses (its Endpoints section, without the internal
#   and LAN columns), then the demo's lines of its Projects section,
#   without the internal names and the LAN addresses, to fit the terminal.
# - Colours lead the eye: the command typed in bold, what each command
#   ends with (deployed, released, running) in green, the public
#   addresses in cyan, the new versions in yellow, the plumbing (LAN
#   addresses, image references) dimmed.
export COLUMNS=100
demo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
demo_domain=$(awk '/^domain:/ { print $2 }' "$demo_dir/../gitops/urbex.platform.yaml" 2>/dev/null)
demo_domain_re=${demo_domain//./\\.}
# The prompt in mauve, the command typed in bold; PS0 resets the colour
# before the command's output.
PS1='\[\e[1;35m\]> \[\e[0;1m\]'
PS0='\[\e[0m\]'

demo_filter() {
  sed -u -E 's/\x1b\[[0-9;?]*[A-Za-z]//g' |
    grep --line-buffered -v -E '^(TASK|PLAY|ok:|changed:|skipping:|included:|\[WARNING\]|\s*$|.*: ok=[0-9]+ .*)' |
    grep --line-buffered -v -E '^(module\.|data\.|Apply complete|Outputs:|hostnames|ip_addresses|vmids|lxc_|\s+"|\s*\]\)?|\s*\}|Initializing|Terraform|- |Plan:|Saved the plan|To perform|Note:|plan\. |\s*[#+~-] |\s+[a-z_]+\s+= )' |
    demo_hide
}

# What no one outside should see: LAN addresses, the platform's domain,
# credentials in a URL.
demo_hide() {
  # A URL's user and password, if any, go too.
  local e='s/192\.168\.[0-9]+\.[0-9]+/<lan>/g; s#://[^/@ ]+@#://#g'
  if [ -n "$demo_domain" ]; then
    e="$e; s/([./-])$demo_domain_re/\\1example.com/g"
  fi
  sed -u -E "$e"
}

demo_color() {
  # bin/urbex, what Claude Code runs, wants its output plain.
  if [ -n "${DEMO_PLAIN:-}" ]; then
    cat
    return
  fi
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
  # The view fits the terminal; Claude (DEMO_PLAIN) reads the whole of it.
  if [ "$*" = status ] && [ -z "${DEMO_PLAIN:-}" ]; then
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
  if [[ " $* " == *" --events "* ]]; then
    # Progress events, one JSON object a line (what the plugin's skill
    # follows): nothing to leave out, only what no one should see.
    command urbex "$@" 2>&1 | demo_hide
    return "${PIPESTATUS[0]}"
  fi
  if [ "$1" = apply ]; then
    # Terraform's and Ansible's prose can't all be foreseen: of apply,
    # only urbex's own lines show.
    # The whole output goes to apply-<env>.log next to this file; when
    # apply fails, its last lines show: a failure is never hidden.
    local log=$demo_dir/apply-${2:-}.log rc
    command urbex "$@" 2>&1 | tee "$log" | demo_filter | grep --line-buffered -E "$demo_apply_lines" | demo_color
    rc=${PIPESTATUS[0]}
    if [ "$rc" != 0 ]; then
      demo_filter < "$log" | tail -n 8 | if [ -n "${DEMO_PLAIN:-}" ]; then cat; else sed -E $'s/.*/\e[1;31m&\e[0m/'; fi
    fi
    return "$rc"
  fi
  command urbex "$@" 2>&1 | demo_filter | demo_color
  return "${PIPESTATUS[0]}"
}
demo_apply_lines='^(Keycloak:|Building |Waiting for |Deployed |staging follows|Created |Error|error)|^  [a-z][a-z0-9-]* +(http|[0-9a-f]{7}|[0-9]+\.)|^ {10,}https://'

# The app's answer, from the real domain: its first line in green.
curl() {
  command curl -s "${@//example.com/${demo_domain:-example.com}}" | demo_hide |
    if [ -n "${DEMO_PLAIN:-}" ]; then cat; else sed -E $'1s/.*/\e[1;32m&\e[0m/'; fi
  return "${PIPESTATUS[0]}"
}
