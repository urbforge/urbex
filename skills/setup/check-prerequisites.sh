#!/bin/bash
# Checks what Urbex needs on this machine, and optionally that a Proxmox
# node answers. Reads no credential and changes nothing.
#
#   check-prerequisites.sh [https://<proxmox>:8006]
#
# Prints one line per check (ok / missing / warn) and exits 1 if something
# required is missing.
set -uo pipefail

missing=0
ok()   { printf '  ok       %s\n' "$*"; }
miss() { printf '  missing  %s\n' "$*"; missing=1; }
warn() { printf '  warn     %s\n' "$*"; }

echo "This machine:"
case "$(uname -s)" in
  Linux|Darwin) ok "OS: $(uname -s)" ;;
  *) warn "OS: $(uname -s) - Urbex is tested on Linux and macOS" ;;
esac

command -v git >/dev/null && ok "git $(git --version | awk '{print $3}')" || miss "git"
command -v ssh-keygen >/dev/null && ok "ssh-keygen" || miss "ssh-keygen (OpenSSH client)"
# The setup's scripts need Python 3.8 or later (tests/plugin-scripts.sh).
if ! command -v python3 >/dev/null; then
  warn "no python3: the setup can't find the values by itself, and asks for them"
elif python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null; then
  ok "python3 $(python3 -c 'import platform; print(platform.python_version())') (the setup's scripts need 3.8 or later)"
else
  warn "python3 $(python3 -V 2>&1 | awk '{print $2}') is older than 3.8, which the setup's scripts need: install a newer one, or the setup asks for the values"
fi

engine=
if command -v podman >/dev/null; then engine=podman; elif command -v docker >/dev/null; then engine=docker; fi
if [ -n "$engine" ]; then
  if "$engine" info >/dev/null 2>&1; then ok "$engine (runs)"; else miss "$engine is installed but '$engine info' fails"; fi
else
  native=1
  for t in terraform ansible-playbook sops age; do command -v "$t" >/dev/null || native=0; done
  if [ "$native" = 1 ]; then
    warn "no podman or docker: the native tools are there, use the native path"
  else
    miss "podman or docker (or the native tools: urbex, terraform, ansible-core, sops, age)"
  fi
fi

if command -v urbex-op >/dev/null; then
  ok "urbex-op on the PATH: $(command -v urbex-op)"
  ws=${URBEX_WORKSPACE:-$HOME/urbex-workspace}
  if [ -d "$ws/home" ]; then ok "workspace: $ws"; else warn "no workspace at $ws yet (urbex-op init)"; fi
  # A release's urbex-op names its image ("urbex-op 0.1.0, image ghcr.io/..."); one from
  # before releases has no version command and runs the image urbex-op build makes.
  image=$(urbex-op version 2>/dev/null | sed -n 's/^urbex-op .*, image //p')
  image=${image:-${URBEX_OPERATOR_IMAGE:-urbex-operator}}
  if [ -n "$engine" ] && "$engine" image inspect "$image" >/dev/null 2>&1; then
    ok "operator image $image"
  else
    case "$image" in
      */*) warn "operator image $image not pulled yet (urbex-op init pulls it)" ;;
      *) warn "no operator image $image yet (urbex-op build in the urbex-cli checkout)" ;;
    esac
  fi
elif command -v urbex >/dev/null; then
  ok "urbex on the PATH (native): $(command -v urbex)"
else
  warn "urbex is not installed yet"
fi

# urbex-op and urbex come from urbex-cli's releases.
if curl -fsS -o /dev/null --max-time 10 'https://api.github.com/repos/urbforge/urbex-cli/releases?per_page=1'; then
  ok "urbex-cli's releases reachable on github.com"
else
  warn "can't reach urbex-cli's releases (api.github.com): urbex-op is downloaded from there"
fi

if [ $# -ge 1 ] && [ -n "$1" ]; then
  url=${1%/}; url=${url%/api2/json}
  echo "Proxmox at $url:"
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$url/api2/json/version" || true)
  case "$code" in
    200|401) ok "the API answers (HTTP $code)" ;;
    000|"") miss "no answer from $url/api2/json/version: check the address, port 8006, and the network" ;;
    *) warn "unexpected HTTP $code from $url/api2/json/version" ;;
  esac
fi

exit $missing
