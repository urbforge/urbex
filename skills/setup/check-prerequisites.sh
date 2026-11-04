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
    miss "podman or docker (or the native tools: Go, terraform, ansible-core, sops, age)"
  fi
fi

if command -v urbex-op >/dev/null; then
  ok "urbex-op on the PATH: $(command -v urbex-op)"
  ws=${URBEX_WORKSPACE:-$HOME/urbex-workspace}
  if [ -d "$ws/home" ]; then ok "workspace: $ws"; else warn "no workspace at $ws yet (urbex-op init)"; fi
  if [ -n "$engine" ] && "$engine" image exists "${URBEX_OPERATOR_IMAGE:-urbex-operator}" 2>/dev/null; then
    ok "operator image ${URBEX_OPERATOR_IMAGE:-urbex-operator}"
  elif [ "$engine" = docker ] && docker image inspect "${URBEX_OPERATOR_IMAGE:-urbex-operator}" >/dev/null 2>&1; then
    ok "operator image ${URBEX_OPERATOR_IMAGE:-urbex-operator}"
  else
    warn "no operator image yet (urbex-op build)"
  fi
elif command -v urbex >/dev/null; then
  ok "urbex on the PATH (native): $(command -v urbex)"
else
  warn "urbex is not installed yet"
fi

# urbex-cli is private until the first release: cloning it needs access.
if GIT_TERMINAL_PROMPT=0 git ls-remote https://github.com/urbforge/urbex-cli.git HEAD >/dev/null 2>&1; then
  ok "access to github.com/urbforge/urbex-cli"
else
  warn "can't read github.com/urbforge/urbex-cli over HTTPS without credentials: it is private until the first release (fine if you clone it with SSH or gh)"
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
