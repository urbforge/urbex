#!/bin/bash
# Tests scripts/docs-version.py (urbforge/urbex#112) on copies of the
# docs: today's pass, a stale link fails naming its file, line and the
# expected version, and the pull-request rules hold.
#
#   tests/docs-version.sh
set -euo pipefail

cd "$(dirname "$0")/.."
script=$PWD/scripts/docs-version.py
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

# The listed files, copied to a fixture root.
fixture() {
  rm -rf "$tmp/root"
  mkdir -p "$tmp/root"
  sed -n 's/^file //p' scripts/docs-version.conf | while read -r f; do
    mkdir -p "$tmp/root/$(dirname "$f")"
    cp "$f" "$tmp/root/$f"
  done
}

# expect <ok|fail> <description> <text the output must contain, or ""> -- <args>
expect() {
  local want=$1 what=$2 needle=$3
  shift 4
  local out rc=0
  out=$(python3 "$script" --root "$tmp/root" "$@" 2>&1) || rc=$?
  local got=ok
  [ "$rc" -eq 0 ] || got=fail
  if [ "$got" != "$want" ] || { [ -n "$needle" ] && ! grep -qF -- "$needle" <<<"$out"; }; then
    echo "FAIL $what (wanted $want${needle:+ with \"$needle\"}, got $got):"
    sed 's/^/     /' <<<"$out"
    failed=1
  else
    echo "ok   $what"
  fi
}

current=$(python3 "$script" list | head -1 | sed 's/.*: //')
[ -n "$current" ] || { echo "FAIL no reference in today's docs"; exit 1; }
IFS=. read -r major minor patch <<<"${current%%-*}"
next="$major.$((minor + 1)).0"

fixture
expect ok "today's docs agree on a tag v$current" "" -- check --tag "v$current"
expect ok "today's docs pass a pull request" "" -- check --latest "v$current"
expect fail "a tag v$next with the docs on $current" "expected $next (the tag v$next)" -- check --tag "v$next"

# A stale link: the release page in the install guide still names 0.0.9.
sed -i "s#releases/download/v$current/urbex-op#releases/download/v0.0.9/urbex-op#" "$tmp/root/docs/getting-started/with-the-cli.md"
line=$(grep -n 'releases/download/v0.0.9/urbex-op' "$tmp/root/docs/getting-started/with-the-cli.md" | head -1 | cut -d: -f1)
expect fail "a stale download link on a tag" "docs/getting-started/with-the-cli.md:$line: names 0.0.9, expected $current (the tag v$current)" -- check --tag "v$current"
expect fail "a stale download link on a pull request" "docs/getting-started/with-the-cli.md:$line: names 0.0.9, expected $current like the other" -- check --latest "v$current"

# The release preparation's branch may name the next version, nothing else may.
fixture
for f in $(sed -n 's/^file //p' scripts/docs-version.conf); do
  sed -i "s/${current//./\\.}/$next/g" "$tmp/root/$f"
done
expect ok "docs/release-v$next names $next" "" -- check --latest "v$current" --branch "docs/release-v$next"
expect fail "another branch names $next" "newer than the latest tag v$current" -- check --latest "v$current" --branch feat/something
expect fail "docs/release-v9.9.9 names $next" "prepares 9.9.9" -- check --latest "v$current" --branch docs/release-v9.9.9

# What the configuration allows stays: the upgrading guide's old image.
fixture
printf '\n`podman rmi ghcr.io/urbforge/urbex-op:0.0.1`\n' >>"$tmp/root/docs/upgrading.md"
expect ok "an allowed old version" "" -- check --tag "v$current"

# A configuration that finds nothing is an error, not a pass.
fixture
printf 'file README.md\nmatch nothing-matches-(this)\n' >"$tmp/empty.conf"
expect fail "no reference found" "no version reference found" -- check --tag "v$current" --conf "$tmp/empty.conf"

# The bump of the release preparation (urbforge/urbex-cli#156): what names
# the release changes, what means another version stays, and a second
# run changes nothing.
fixture
printf '\n`podman rmi ghcr.io/urbforge/urbex-op:%s`\n' "$current" >>"$tmp/root/docs/upgrading.md"
printf '\n## From 0.1.0 to %s\n\nA project tagged v%s keeps its own version.\n' "$current" "$current" >>"$tmp/root/docs/upgrading.md"
cp -r "$tmp/root" "$tmp/before"
expect ok "bump $current to $next" "lines now name $next" -- bump "$current" "$next"
expect ok "after the bump, a tag v$next" "" -- check --tag "v$next"
grep -q "releases/download/v$next/urbex-op" "$tmp/root/docs/getting-started/with-the-cli.md" \
  && echo "ok   the download link names $next" || { echo "FAIL the download link wasn't bumped"; failed=1; }
for kept in "podman rmi ghcr.io/urbforge/urbex-op:$current" "## From 0.1.0 to $current" "A project tagged v$current"; do
  grep -qF -- "$kept" "$tmp/root/docs/upgrading.md" \
    && echo "ok   kept: $kept" || { echo "FAIL changed what means another version: $kept"; failed=1; }
done
cp -r "$tmp/root" "$tmp/once"
expect ok "a second bump changes nothing" "names $next already" -- bump "$current" "$next"
diff -r "$tmp/once" "$tmp/root" >/dev/null && echo "ok   idempotent" || { echo "FAIL the second bump changed files"; failed=1; }
rm -rf "$tmp/once" "$tmp/before"

# A reference to a third version is left for a person, and fails.
fixture
sed -i "s#releases/download/v$current/urbex-op#releases/download/v0.0.9/urbex-op#" "$tmp/root/docs/getting-started/with-the-cli.md"
expect fail "bump with a stale reference" "names 0.0.9, expected $next" -- bump "$current" "$next"

# A pre-release sorts before its release.
python3 - "$script" <<'PY' && echo "ok   pre-release ordering" || failed=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dv", sys.argv[1])
dv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dv)
v = dv.parse_version
assert v("0.3.0-rc.1") < v("0.3.0") < v("v0.3.1") < v("1.0.0"), "ordering"
PY

exit "$failed"
