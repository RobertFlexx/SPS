#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd)
src=$project_dir/bin/src

fail()
{
    printf 'test_src_check: %s\n' "$*" >&2
    exit 1
}

expect_status()
{
    expected=$1
    shift
    set +e
    "$@" >"$tmp/out" 2>"$tmp/err"
    got=$?
    set -e
    [ "$got" -eq "$expected" ] ||
        fail "expected status $expected, got $got for: $*"
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-src-check.XXXXXX")
trap 'rm -rf "$tmp"' 0 1 2 3 15
mkdir -p "$tmp/root" "$tmp/cache" "$tmp/db" "$tmp/build" "$tmp/ok" "$tmp/bad" \
    "$tmp/missing-dep"

SPS_ROOT=$tmp/root
SPS_DB=$tmp/db
SPS_CACHE=$tmp/cache
SPS_BUILD=$tmp/build
SPS_CONFIG=/dev/null
SPS_REPOS_CONFIG=/dev/null
export SPS_ROOT SPS_DB SPS_CACHE SPS_BUILD SPS_CONFIG SPS_REPOS_CONFIG

# A complete, valid recipe passes.
cat >"$tmp/ok/recipe" <<'EOF'
name        validpkg
version     1.0
release     2
description A complete, valid test recipe
source      https://example.invalid/validpkg-1.0.tar.gz
hash        sha256:0000000000000000000000000000000000000000000000000000000000000000
install     true
EOF
expect_status 0 "$src" check "$tmp/ok"
$src check "$tmp/ok" >/dev/null 2>&1 || fail "valid recipe rejected"
$src check "$tmp/ok/recipe" | grep -q '^check: ok ' ||
    fail "valid recipe was not reported ok"

# A directory argument resolves to its recipe file.
$src check "$tmp/ok/recipe" >/dev/null 2>&1 || fail "file recipe rejected"

# Paths with spaces must not be word-split.
mkdir -p "$tmp/ok dir"
cp "$tmp/ok/recipe" "$tmp/ok dir/recipe"
$src check "$tmp/ok dir" | grep -q '^check: ok ' ||
    fail "recipe path with a space was not accepted"

# Missing the required install command is a syntax failure.
cat >"$tmp/bad/recipe" <<'EOF'
name        badpkg
version     1.0
release     1
description Recipe missing its install command
EOF
expect_status 4 "$src" check "$tmp/bad"

# A nonexistent path is reported and exits with the not-found status.
expect_status 3 "$src" check "$tmp/nonexistent"

# --help exits cleanly.
expect_status 0 "$src" check --help

# An unknown option is a usage error.
expect_status 2 "$src" check --no-such-option "$tmp/ok"

# --deps validates a self-consistent graph.
cat >"$tmp/missing-dep/recipe" <<'EOF'
name        needsnothing
version     1
release     1
description No dependencies to declare
install     true
EOF
expect_status 0 "$src" check --deps "$tmp/missing-dep"

# --deps flags an unresolvable declared dependency.
cat >"$tmp/bad/deps" <<'EOF'
name        needsghost
version     1
release     1
description Declares a dependency that is not in the checked set
depend      ghost-pkg
install     true
EOF
mv "$tmp/bad/deps" "$tmp/bad/recipe2"
expect_status 5 "$src" check --deps "$tmp/bad/recipe2"

printf '%s\n' 'test_src_check: ok'
