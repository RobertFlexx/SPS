#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
fail() { printf 'test_highlevel: %s\n' "$*" >&2; exit 1; }
contains() { case $1 in *"$2"*) : ;; *) fail "expected output to contain '$2'" ;; esac; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-highlevel.XXXXXX") || fail mktemp
trap 'rm -rf "$tmp"' 0 HUP INT TERM
root=$tmp/root; db=$tmp/db; cache=$tmp/cache; build=$tmp/build; repo=$tmp/repo
mkdir -p "$root/etc/sps" "$db/installed" "$cache" "$build" "$repo/base" "$repo/lib" "$repo/app"
: >"$db/owners"; : >"$db/world"; : >"$db/history"
printf 'repo test %s 10\n' "$repo" >"$tmp/repos.conf"
: >"$tmp/sps.conf"

export SPS_ROOT=$root SPS_DB=$db SPS_CACHE=$cache SPS_BUILD=$build
export SPS_CONFIG=$tmp/sps.conf SPS_REPOS_CONFIG=$tmp/repos.conf SPS_LIBDIR=$project_dir/lib
PATH=$project_dir/bin:$PATH
export PATH

recipe()
{
    dir=$1 name=$2 version=$3 dep=${4-}
    {
        printf 'name %s\n' "$name"
        printf 'version %s\n' "$version"
        printf 'release 1\n'
        printf 'arch any\n'
        printf 'description high-level %s\n' "$name"
        [ -z "$dep" ] || printf 'depend %s\n' "$dep"
        printf 'install mkdir -p "$PKG/usr/share/sps-test"\n'
        printf 'install printf "%%s\\n" "%s" > "$PKG/usr/share/sps-test/%s"\n' "$version" "$name"
    } >"$dir/recipe"
}

recipe "$repo/base" base 1.0
recipe "$repo/lib" lib 1.0 base
recipe "$repo/app" app 1.0 lib
src update >/dev/null
sget install app >"$tmp/install.out"
[ "$(cat "$root/usr/share/sps-test/base")" = 1.0 ] || fail 'base was not installed'
[ "$(cat "$root/usr/share/sps-test/lib")" = 1.0 ] || fail 'lib was not installed'
[ "$(cat "$root/usr/share/sps-test/app")" = 1.0 ] || fail 'app was not installed'
grep -qx app "$db/world" || fail 'requested app was not explicit'
! grep -qx base "$db/world" || fail 'dependency base was explicit'
[ -z "$(pkstat --orphans)" ] || fail 'reachable dependencies were reported as orphans'

[ "$(sget dependees base)" = lib ] || fail 'dependees query is wrong'
why=$(sget why app base)
[ "$why" = "$(printf 'app\nlib\nbase')" ] || fail "why path is wrong: $why"

set +e
sget remove --plan lib >"$tmp/remove-block.out" 2>"$tmp/remove-block.err"
status=$?
set -e
[ "$status" -eq 5 ] || fail "unsafe high-level removal returned $status"
contains "$(cat "$tmp/remove-block.err")" 'app requires lib'

# Dependencies can move forward even when the explicit root stays at the same
# version.
recipe "$repo/base" base 2.0
recipe "$repo/lib" lib 2.0 base
src update >/dev/null
plan=$(sget upgrade --plan)
contains "$plan" 'upgrade    base 1.0-1 -> 2.0-1'
contains "$plan" 'upgrade    lib 1.0-1 -> 2.0-1'
sget upgrade >"$tmp/upgrade.out"
[ "$(cat "$root/usr/share/sps-test/base")" = 2.0 ] || fail 'base was not upgraded'
[ "$(cat "$root/usr/share/sps-test/lib")" = 2.0 ] || fail 'lib was not upgraded'

# An exact reinstall should reuse the binary cache.
reinstall=$(sget install --reinstall app)
contains "$reinstall" 'using cached app-1.0-1-any.pkg.tar'

# A cache filename is not enough to prove that an artifact matches the
# current recipe/support tree. Rebuild an unchanged version when its package
# definition changes, rather than reusing a stale library from an earlier
# live-setup attempt.
printf '%s\n' '# definition changed without a release bump' >>"$repo/app/recipe"
src update >/dev/null
reinstall=$(sget install --reinstall app)
contains "$reinstall" 'discarding stale cached app-1.0-1-any.pkg.tar'

# Do not trust the cache filename. A different valid package under this name
# must be rejected before pkin sees it.
app_cache=$(find "$cache/packages" -type f -name 'app-1.0-1-any.pkg.tar*' | head -1)
base_cache=$(find "$cache/packages" -type f -name 'base-2.0-1-any.pkg.tar*' | head -1)
[ -n "$app_cache" ] && [ -n "$base_cache" ] || fail 'expected binary cache artifacts are missing'
cp "$app_cache" "$tmp/app-cache.good"
cp "$base_cache" "$app_cache"
set +e
sget install --reinstall app >"$tmp/bad-cache.out" 2>"$tmp/bad-cache.err"
status=$?
set -e
[ "$status" -eq 4 ] || fail "mismatched cached artifact returned $status"
contains "$(cat "$tmp/bad-cache.err")" 'cached artifact identity is invalid'
cp "$tmp/app-cache.good" "$app_cache"

# Writers take the high-level transaction lock. Read-only plans still work
# while that lock exists.
mkdir "$db/.transaction"
printf '%s\n' $$ >"$db/.transaction/pid"
sget install --plan app >/dev/null || fail 'read-only plan was blocked by transaction lock'
set +e
sget install --reinstall app >"$tmp/tx.out" 2>"$tmp/tx.err"
status=$?
set -e
[ "$status" -eq 11 ] || fail "concurrent transaction returned $status"
contains "$(cat "$tmp/tx.err")" 'another high-level SPS transaction is active'
rm -rf "$db/.transaction"

sget remove app >/dev/null
orphans=$(pkstat --orphans)
[ "$orphans" = "$(printf 'base\nlib')" ] || fail "transitive orphan set is wrong: $orphans"

# Asking for an installed dependency should just mark it explicit.
promote=$(sget install base)
contains "$promote" 'marked base as explicit'
grep -qx base "$db/world" || fail 'exact dependency was not promoted to explicit'
orphans=$(pkstat --orphans)
[ "$orphans" = lib ] || fail "orphan reachability after promotion is wrong: $orphans"

# When both are requested, remove the depender first.
plan=$(sget remove --plan lib base)
first=$(printf '%s\n' "$plan" | awk '/^  remove/ {print $2; exit}')
[ "$first" = lib ] || fail "remove order did not put depender first: $plan"
sget remove lib base >/dev/null
[ -z "$(pkstat)" ] || fail 'packages remain after complete removal'

printf '%s\n' 'test_highlevel: ok'
