#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
fail() { printf 'test_upgrade_recipes: %s\n' "$*" >&2; exit 1; }

tool=$project_dir/tools/upgrade-recipes
[ -f "$tool" ] || fail "missing $tool"
command -v python3 >/dev/null 2>&1 || fail 'python3 is required for upgrade-recipes'

python3 "$tool" --selftest >/dev/null || fail 'upgrade-recipes --selftest failed'

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-upgrade-test.XXXXXX") || fail mktemp
trap 'rm -rf "$tmp"' 0 HUP INT TERM

mkdir -p "$tmp/tree/demo"
cat >"$tmp/tree/demo/recipe" <<'EOF'
name        demo
version     1.0
release     3
arch        any
description demo: offline fixture for upgrade-recipes

source      https://example.org/demo-1.0.tar.gz
hash        sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

depend      filesystem
install     mkdir -p "$PKG/usr/share/demo"
install     printf '%s\n' "${version}" >"$PKG/usr/share/demo/version"
EOF

# A dry-run against an unreachable host must still parse the tree.
out=$(python3 "$tool" --trees "$tmp/tree" --only demo --jobs 1 2>/dev/null || true)
printf '%s\n' "$out" | grep -q 'summary' || fail "plan output missing summary: $out"

printf '%s\n' 'upgrade-recipes tests passed'
