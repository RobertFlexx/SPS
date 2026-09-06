#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
fail() { printf 'test_config_status: %s\n' "$*" >&2; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-confstatus.XXXXXX") || fail 'mktemp failed'
trap 'rm -rf "$tmp"' 0 HUP INT TERM
root=$tmp/root
db=$tmp/db
cache=$tmp/cache
build=$tmp/build
mkdir -p "$root" "$cache" "$build" "$tmp/pkg"

run()
{
    SPS_ROOT=$root SPS_DB=$db SPS_CACHE=$cache SPS_BUILD=$build \
    SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null SPS_PRESERVE=etc \
    SPS_LIBDIR=$project_dir/lib "$@"
}

make_recipe_pkg()
{
    dir=$1 name=$2 version=$3 config_text=$4
    mkdir -p "$dir"
    cat >"$dir/recipe" <<EOF_RECIPE
name $name
version $version
release 1
arch any
description config review test package
install mkdir -p "\$PKG/etc"
install printf '%s\\n' '$config_text' > "\$PKG/etc/$name.conf"
EOF_RECIPE
    rm -f "$tmp/pkg/artifact"
    run "$project_dir/bin/mkpkg" --artifact-file "$tmp/pkg/artifact" \
        --compression none --output "$tmp/pkg" "$dir/recipe" || return $?
    sed -n '1p' "$tmp/pkg/artifact"
}

recipe=$tmp/recipe
artifact1=$(make_recipe_pkg "$recipe" confpkg 1.0 'default-value-1')
run "$project_dir/bin/pkin" "$artifact1" >/dev/null

# No local changes: config-status is empty.
status=0
run "$project_dir/bin/sget" config-status >"$tmp/clean.out" 2>"$tmp/clean.err" || status=$?
[ "$status" -eq 0 ] || fail 'config-status failed on a clean system'
grep -q 'no protected configuration changes' "$tmp/clean.out" ||
    fail 'config-status did not report a clean system'

# Modify the protected file, then upgrade with a changed packaged default.
# pkin must keep the local file and write .sps-new.
printf '%s\n' 'local-admin-value' >"$root/etc/confpkg.conf"
artifact2=$(make_recipe_pkg "$recipe" confpkg 2.0 'default-value-2')
run "$project_dir/bin/pkin" "$artifact2" >"$tmp/upgrade.out" 2>"$tmp/upgrade.err"
[ "$(cat "$root/etc/confpkg.conf")" = local-admin-value ] ||
    fail 'upgrade overwrote protected config'
[ "$(cat "$root/etc/confpkg.conf.sps-new")" = default-value-2 ] ||
    fail 'new config was not emitted as .sps-new'

# config-status must now list the package/path and the pending default.
run "$project_dir/bin/sget" config-status >"$tmp/list.out" 2>"$tmp/list.err" || status=$?
[ "$status" -eq 0 ] || fail 'config-status failed after an upgrade'
grep -q '^confpkg' "$tmp/list.out" ||
    fail 'config-status did not report confpkg'
grep -q '/etc/confpkg.conf' "$tmp/list.out" ||
    fail 'config-status did not report the modified path'
grep -q 'new packaged default' "$tmp/list.out" ||
    fail 'config-status did not flag the pending .sps-new'

# The package-scoped spelling narrows output to that package.
run "$project_dir/bin/sget" config-status confpkg >"$tmp/one.out" 2>"$tmp/one.err"
grep -q '^confpkg' "$tmp/one.out" ||
    fail 'config-status PACKAGE did not list the package'

# --raw is tab-separated and scriptable.
run "$project_dir/bin/sget" config-status --raw >"$tmp/raw.out" 2>"$tmp/raw.err"
grep -q '^confpkg	etc/confpkg.conf	modified	1$' "$tmp/raw.out" ||
    fail 'config-status --raw record was not as expected'

# Unknown or unrelated packages produce no rows for that package.
status=0
run "$project_dir/bin/sget" config-status zzz-nonexistent >"$tmp/no.out" 2>"$tmp/no.err" || status=$?
[ "$status" -eq 0 ] || fail 'config-status PACKAGE failed for a missing name'
grep -q 'no protected configuration' "$tmp/no.out" ||
    fail 'config-status printed rows for a package that is not installed'

# --diff shows a unified diff of the local file and the .sps-new default.
run "$project_dir/bin/sget" config-status --diff /etc/confpkg.conf \
    >"$tmp/diff.out" 2>"$tmp/diff.err" || status=$?
[ "$status" -eq 0 ] || fail 'config-status --diff failed'
grep -q 'local-admin-value' "$tmp/diff.out" ||
    fail 'config-status --diff omitted the local side'
grep -q 'default-value-2' "$tmp/diff.out" ||
    fail 'config-status --diff omitted the packaged default'
grep -q '^@' "$tmp/diff.out" ||
    fail 'config-status --diff produced no unified hunk header'

# The .sps-new spelling is accepted by --diff too.
run "$project_dir/bin/sget" config-status --diff /etc/confpkg.conf.sps-new \
    >"$tmp/diff2.out" 2>"$tmp/diff2.err" || status=$?
[ "$status" -eq 0 ] || fail 'config-status --diff .sps-new spelling failed'
grep -q 'default-value-2' "$tmp/diff2.out" ||
    fail 'config-status --diff omitted the packaged default (.sps-new spelling)'

# --diff on a non-config path must fail cleanly and not modify anything.
status=0
run "$project_dir/bin/sget" config-status --diff /etc \
    >"$tmp/bad.out" 2>"$tmp/bad.err" || status=$?
[ "$status" -ne 0 ] || fail 'config-status --diff /etc should have failed'
[ ! -s "$tmp/bad.out" ] || fail 'config-status --diff wrote to stdout on failure'

# When the local file is returned to the packaged content while a .sps-new
# remains, the review reports the stale sibling instead of silence.
printf '%s\n' 'default-value-2' >"$root/etc/confpkg.conf"
run "$project_dir/bin/sget" config-status >"$tmp/stale.out" 2>"$tmp/stale.err"
grep -q 'matches package; .sps-new left over' "$tmp/stale.out" ||
    fail 'config-status did not report the stale .sps-new sibling'

# Diverge the local file again, then upgrade to 3.0 with a changed default.
# An existing differing .sps-new sibling forces the .sps-new.VERSION-RELEASE
# spelling, and pkin must not clobber the sibling.
printf '%s\n' 'local-admin-value-again' >"$root/etc/confpkg.conf"
printf '%s\n' 'admin-kept-sibling' >"$root/etc/confpkg.conf.sps-new"
artifact3=$(make_recipe_pkg "$recipe" confpkg 3.0 'default-value-3')
run "$project_dir/bin/pkin" "$artifact3" >"$tmp/collide.out" 2>"$tmp/collide.err"
[ "$(cat "$root/etc/confpkg.conf.sps-new")" = admin-kept-sibling ] ||
    fail 'pkin clobbered an existing .sps-new sibling'
[ "$(cat "$root/etc/confpkg.conf.sps-new.3.0-1")" = default-value-3 ] ||
    fail 'pkin did not write the versioned .sps-new.3.0-1'
grep -q 'kept it and wrote.*confpkg.conf.sps-new.3.0-1' "$tmp/collide.err" ||
    fail 'upgrade to 3.0 did not write the versioned .sps-new'

# config-status still reports the pending default after the collision.
run "$project_dir/bin/sget" config-status --raw >"$tmp/raw2.out" 2>"$tmp/raw2.err"
grep -q '^confpkg	etc/confpkg.conf	modified	1$' "$tmp/raw2.out" ||
    fail 'config-status --raw did not list the pending default'

# --diff accepts the .sps-new.VERSION-RELEASE spelling and diffs that sibling.
status=0
run "$project_dir/bin/sget" config-status --diff /etc/confpkg.conf.sps-new.3.0-1 \
    >"$tmp/diffv.out" 2>"$tmp/diffv.err" || status=$?
[ "$status" -eq 0 ] || fail 'config-status --diff versioned spelling failed'
grep -q 'local-admin-value-again' "$tmp/diffv.out" ||
    fail 'config-status --diff versioned omitted the local side'
grep -q 'default-value-3' "$tmp/diffv.out" ||
    fail 'config-status --diff versioned omitted the packaged default'
grep -q 'admin-kept-sibling' "$tmp/diffv.out" ||
    fail 'config-status --diff versioned omitted the plain .sps-new sibling'

printf '%s\n' 'config status tests passed'