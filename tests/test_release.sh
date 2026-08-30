#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
fail() { printf 'test_release: %s\n' "$*" >&2; exit 1; }

[ "$(cat "$project_dir/VERSION")" = 1.0.0 ] || fail 'VERSION is not 1.0.0'

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-release.XXXXXX") || fail 'mktemp failed'
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
    dir=$1 name=$2 version=$3 arch=$4 config_text=$5
    mkdir -p "$dir"
    cat >"$dir/recipe" <<EOF_RECIPE
name $name
version $version
release 1
arch $arch
description release regression package
install mkdir -p "\$PKG/etc" "\$PKG/var/lib/$name"
install printf '%s\\n' '$config_text' > "\$PKG/etc/$name.conf"
install printf '%s\\n' '$version' > "\$PKG/var/lib/$name/data"
install chmod 0700 "\$PKG/var/lib/$name"
EOF_RECIPE
    run "$project_dir/bin/mkpkg" --compression none --output "$tmp/pkg" "$dir/recipe"
}

recipe=$tmp/recipe
artifact1=$(make_recipe_pkg "$recipe" relpkg 1.0 any default-v1)
run "$project_dir/bin/pkin" "$artifact1" >/dev/null
[ "$(cat "$root/etc/relpkg.conf")" = default-v1 ] || fail 'initial config missing'
mode=$(LC_ALL=C ls -ld "$root/var/lib/relpkg" | awk '{ print substr($1,1,10) }')
[ "$mode" = drwx------ ] || fail "directory mode not preserved: $mode"

# Package reason can change without reinstalling the package.
run "$project_dir/bin/pkmark" dependency relpkg >/dev/null
! grep -qx relpkg "$db/world" || fail 'pkmark dependency did not clear world entry'
run "$project_dir/bin/pkmark" explicit relpkg >/dev/null
grep -qx relpkg "$db/world" || fail 'pkmark explicit did not add world entry'

# A dead PID lock must be recoverable.
mkdir "$db/.lock"
printf '%s\n' 99999999 >"$db/.lock/pid"
run "$project_dir/bin/pkmark" dependency relpkg >"$tmp/stale.out" 2>"$tmp/stale.err" ||
    fail 'stale database lock was not recovered'
grep -q 'stale package database lock' "$tmp/stale.err" || fail 'stale-lock recovery was silent'
run "$project_dir/bin/pkmark" explicit relpkg >/dev/null

# Keep a locally changed protected file. If the package default changed too,
# leave the new copy next to it.
printf '%s\n' local-admin-value >"$root/etc/relpkg.conf"
artifact2=$(make_recipe_pkg "$recipe" relpkg 2.0 any default-v2)
run "$project_dir/bin/pkin" "$artifact2" >"$tmp/upgrade.out" 2>"$tmp/upgrade.err"
[ "$(cat "$root/etc/relpkg.conf")" = local-admin-value ] || fail 'upgrade overwrote protected config'
[ "$(cat "$root/etc/relpkg.conf.sps-new")" = default-v2 ] || fail 'new config was not emitted as .sps-new'
run "$project_dir/bin/pkcheck" --modified relpkg >"$tmp/modified.out" 2>/dev/null || status=$?
[ "${status:-0}" -eq 1 ] || fail 'pkcheck did not report preserved config as modified'

# Hooks are files beside the recipe and run with SPS_ROOT set.
mkdir -p "$recipe/hooks"
for hook in pre-install post-install pre-remove post-remove; do
    cat >"$recipe/hooks/$hook" <<EOF_HOOK
printf '%s\\n' '$hook' >> "\$SPS_ROOT/hook.log"
EOF_HOOK
done
sed 's/version 2.0/version 3.0/' "$recipe/recipe" >"$recipe/recipe.new"
mv "$recipe/recipe.new" "$recipe/recipe"
artifact3=$(run "$project_dir/bin/mkpkg" --compression none --output "$tmp/pkg" "$recipe/recipe")
run "$project_dir/bin/pkin" "$artifact3" >/dev/null
[ "$(sed -n '1p' "$root/hook.log")" = pre-install ] || fail 'pre-install hook did not run'
[ "$(sed -n '2p' "$root/hook.log")" = post-install ] || fail 'post-install hook did not run'
run "$project_dir/bin/pkdel" relpkg >/dev/null
[ "$(sed -n '3p' "$root/hook.log")" = pre-remove ] || fail 'pre-remove hook did not run'
[ "$(sed -n '4p' "$root/hook.log")" = post-remove ] || fail 'post-remove hook did not run'
[ "$(cat "$root/etc/relpkg.conf")" = local-admin-value ] || fail 'remove deleted modified protected config'

# A root install must not inherit the builder's uid/gid. This check only runs
# when the test suite itself is root.
if [ "$(id -u)" -eq 0 ]; then
    owner_dir=$tmp/owner
    owner_artifact=$(make_recipe_pkg "$owner_dir" ownerpkg 1.0 any owner-default)
    unpack=$tmp/owner-unpack
    mkdir -p "$unpack"
    tar -xf "$owner_artifact" -C "$unpack"
    chown 1234:1234 "$unpack/var/lib/ownerpkg/data"
    chmod 6751 "$unpack/var/lib/ownerpkg/data"
    repacked=$tmp/pkg/ownerpkg-1.0-1-any-repacked.pkg.tar
    tar -cf "$repacked" -C "$unpack" .
    run "$project_dir/bin/pkin" "$repacked" >/dev/null
    set -- $(LC_ALL=C ls -ln "$root/var/lib/ownerpkg/data")
    [ "$3" = 0 ] && [ "$4" = 0 ] || fail "root install preserved builder uid/gid: $3:$4"
    case $1 in -rwsr-s--x*) ;; *) fail "setuid/setgid file mode was not preserved: $1" ;; esac
    run "$project_dir/bin/pkdel" ownerpkg >/dev/null
fi

# If a post hook fails, the already-committed package state and history must
# still tell the truth.
hookfail_dir=$tmp/hookfail
mkdir -p "$hookfail_dir/hooks"
cat >"$hookfail_dir/recipe" <<'EOF_HOOKFAIL_RECIPE'
name hookfail
version 1.0
release 1
arch any
description post hook transaction regression
install mkdir -p "$PKG/usr/share"
install printf '%s\n' hookfail > "$PKG/usr/share/hookfail"
EOF_HOOKFAIL_RECIPE
printf '%s\n' 'exit 1' >"$hookfail_dir/hooks/post-install"
printf '%s\n' 'exit 1' >"$hookfail_dir/hooks/post-remove"
hookfail_artifact=$(run "$project_dir/bin/mkpkg" --compression none --output "$tmp/pkg" "$hookfail_dir/recipe")
set +e
run "$project_dir/bin/pkin" "$hookfail_artifact" >/dev/null 2>"$tmp/hookfail-install.err"
status=$?
set -e
[ "$status" -eq 10 ] || fail "failing post-install hook returned $status"
[ -d "$db/installed/hookfail" ] || fail 'post-install failure rolled back committed package metadata'
grep -q ' install hookfail 1.0-1$' "$db/history" || fail 'post-install failure omitted committed install history'
set +e
run "$project_dir/bin/pkdel" hookfail >/dev/null 2>"$tmp/hookfail-remove.err"
status=$?
set -e
[ "$status" -eq 10 ] || fail "failing post-remove hook returned $status"
[ ! -d "$db/installed/hookfail" ] || fail 'post-remove failure restored a removed package'
grep -q ' remove hookfail 1.0$' "$db/history" || fail 'post-remove failure omitted committed removal history'

# Reject a foreign architecture before writing payload state.
foreign_dir=$tmp/foreign
foreign=$(make_recipe_pkg "$foreign_dir" foreign 1.0 definitely_foreign default)
set +e
run "$project_dir/bin/pkin" "$foreign" >"$tmp/foreign.out" 2>"$tmp/foreign.err"
status=$?
set -e
[ "$status" -eq 4 ] || fail "foreign architecture returned $status instead of 4"
[ ! -e "$root/var/lib/foreign/data" ] || fail 'foreign architecture payload was installed'

printf '%s\n' 'test_release: ok'
