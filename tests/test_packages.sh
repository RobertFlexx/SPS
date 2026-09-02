#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1

fail()
{
    printf 'test_packages: %s\n' "$*" >&2
    exit 1
}

assert_status()
{
    expected_status=$1
    shift
    set +e
    run_sps "$@" >"$tmp/stdout" 2>"$tmp/stderr"
    actual_status=$?
    set -e
    [ "$actual_status" -eq "$expected_status" ] || {
        sed 's/^/stdout: /' "$tmp/stdout" >&2
        sed 's/^/stderr: /' "$tmp/stderr" >&2
        fail "expected status $expected_status, got $actual_status from $*"
    }
}

run_sps()
{
    SPS_ROOT=$root \
    SPS_DB=$db \
    SPS_CACHE=$cache \
    SPS_BUILD=$build \
    SPS_CONFIG=/dev/null \
    SPS_REPOS_CONFIG=/dev/null \
    SPS_LIBDIR=$project_dir/lib \
    "$@"
}

make_package()
{
    package_name=$1
    package_version=$2
    package_path=$3
    package_content=$4
    package_depend=${5-}
    package_extra_path=${6-}
    package_extra_content=${7-}
    package_stage=$tmp/stage-$package_name-$package_version
    package_archive=$tmp/$package_name-$package_version.pkg.tar
    rm -rf "$package_stage"
    mkdir -p "$package_stage/.SPS" "$package_stage/$(dirname "$package_path")"
    printf '%s\n' "$package_content" >"$package_stage/$package_path"
    if [ -n "$package_extra_path" ]; then
        mkdir -p "$package_stage/$(dirname "$package_extra_path")"
        printf '%s\n' "$package_extra_content" >"$package_stage/$package_extra_path"
    fi
    {
        printf 'format\t1\n'
        printf 'name\t%s\n' "$package_name"
        printf 'version\t%s\n' "$package_version"
        printf 'release\t1\n'
        printf 'arch\tany\n'
        printf 'description\ttest package %s\n' "$package_name"
        [ -z "$package_depend" ] || printf 'depend\t%s\n' "$package_depend"
    } >"$package_stage/.SPS/meta"
    : >"$package_stage/.SPS/files.unsorted"
    (CDPATH= cd "$package_stage" && find . ! -name . ! -path './.SPS' ! -path './.SPS/*' -print) |
    sed 's#^\./##' | while IFS= read -r package_entry; do
        if [ -d "$package_stage/$package_entry" ] && [ ! -L "$package_stage/$package_entry" ]; then
            printf '%s/\n' "$package_entry"
        else
            printf '%s\n' "$package_entry"
        fi
    done >"$package_stage/.SPS/files.unsorted"
    LC_ALL=C sort "$package_stage/.SPS/files.unsorted" >"$package_stage/.SPS/files"
    rm -f "$package_stage/.SPS/files.unsorted"
    : >"$package_stage/.SPS/hashes"
    while IFS= read -r package_entry || [ -n "$package_entry" ]; do
        case $package_entry in */) continue ;; esac
        if [ -f "$package_stage/$package_entry" ] && [ ! -L "$package_stage/$package_entry" ]; then
            package_hash=$(sha256sum "$package_stage/$package_entry" | awk '{ print $1 }')
            printf 'sha256\t%s\t%s\n' "$package_hash" "$package_entry" >>"$package_stage/.SPS/hashes"
        fi
    done <"$package_stage/.SPS/files"
    tar -C "$package_stage" -cf "$package_archive" .
    printf '%s\n' "$package_archive"
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-packages.XXXXXX") ||
    fail 'cannot create temporary directory'
trap 'rm -rf "$tmp"' 0 HUP INT TERM
root=$tmp/root
db=$tmp/db
cache=$tmp/cache
build=$tmp/build
mkdir -p "$root" "$cache" "$build"

lib_archive=$(make_package libfoo 1.0 usr/lib/libfoo.so 'library version one')
demo_v1=$(make_package demo 1.0 usr/bin/demo 'demo version one' libfoo \
    usr/share/demo/obsolete 'remove on upgrade')

run_sps "$project_dir/bin/pkin" --dependency "$lib_archive" >"$tmp/install-lib.out"
run_sps "$project_dir/bin/pkin" "$demo_v1" >"$tmp/install-demo.out"
[ "$(cat "$root/usr/bin/demo")" = 'demo version one' ] || fail 'initial payload was not installed'
[ -f "$root/usr/share/demo/obsolete" ] || fail 'initial secondary payload is missing'
grep -qx demo "$db/world" || fail 'explicit package was not added to world'
! grep -qx libfoo "$db/world" || fail 'dependency package was added to world'
grep -qx 'usr/bin/demo	demo' "$db/owners" || fail 'file owner was not recorded'

owner_output=$(run_sps "$project_dir/bin/pkstat" --owns /usr/bin/demo)
case $owner_output in 'demo 1.0-1 any') ;; *) fail "unexpected owner output: $owner_output" ;; esac
run_sps "$project_dir/bin/pkstat" --files demo | grep -qx '/usr/bin/demo' ||
    fail 'pkstat --files omitted the payload'
run_sps "$project_dir/bin/pkstat" --explicit | grep -q '^demo ' ||
    fail 'pkstat --explicit omitted demo'
orphans=$(run_sps "$project_dir/bin/pkstat" --orphans)
[ -z "$orphans" ] || fail "dependency in use was reported as orphan: $orphans"
run_sps "$project_dir/bin/pkstat" --size demo | grep -q '^demo [1-9][0-9]*$' ||
    fail 'pkstat --size did not report bytes'
run_sps "$project_dir/bin/pkcheck" --all >"$tmp/check-clean.out" ||
    fail 'freshly installed packages did not verify'

rival_archive=$(make_package rival 1.0 usr/bin/demo 'collision')
assert_status 7 "$project_dir/bin/pkin" "$rival_archive"
[ "$(cat "$root/usr/bin/demo")" = 'demo version one' ] ||
    fail 'conflict attempt changed the installed file'
[ ! -d "$db/installed/rival" ] || fail 'conflicting package received a database record'

demo_v2=$(make_package demo 2.0 usr/bin/demo 'demo version two' libfoo)
run_sps "$project_dir/bin/pkin" "$demo_v2" >"$tmp/upgrade.out"
[ "$(cat "$root/usr/bin/demo")" = 'demo version two' ] || fail 'upgrade did not replace payload'
[ ! -e "$root/usr/share/demo/obsolete" ] || fail 'upgrade did not remove obsolete payload'
grep -q 'upgrade demo 1.0 2.0' "$db/history" || fail 'upgrade was not recorded in history'
for db_temporary in "$db"/.*-base.* "$db"/.*-new.*; do
    if [ -f "$db_temporary" ] || [ -d "$db_temporary" ] || [ -L "$db_temporary" ]; then
        fail "successful install left database temporary file ${db_temporary##*/}"
    fi
done

printf '%s\n' 'locally modified' >"$root/usr/bin/demo"
assert_status 1 "$project_dir/bin/pkcheck" --modified demo
grep -q '^modified /usr/bin/demo demo' "$tmp/stdout" || fail 'modified-file diagnostic is unclear'
rm -f "$root/usr/bin/demo"
assert_status 1 "$project_dir/bin/pkcheck" --missing demo
grep -q '^missing /usr/bin/demo demo' "$tmp/stdout" || fail 'missing-file diagnostic is unclear'
run_sps "$project_dir/bin/pkin" "$demo_v2" >/dev/null

run_sps "$project_dir/bin/pkdel" --plan demo >"$tmp/remove-plan"
[ -f "$root/usr/bin/demo" ] || fail 'remove plan changed the target root'
grep -q '^remove: /usr/bin/demo$' "$tmp/remove-plan" || fail 'remove plan omitted payload'
run_sps "$project_dir/bin/pkdel" demo >"$tmp/remove.out"
[ ! -e "$root/usr/bin/demo" ] || fail 'pkdel left package payload behind'
[ ! -d "$db/installed/demo" ] || fail 'pkdel left installed metadata behind'
! grep -q 'demo$' "$db/owners" || fail 'pkdel left owner records behind'
orphans=$(run_sps "$project_dir/bin/pkstat" --orphans)
[ "$orphans" = libfoo ] || fail "expected libfoo orphan, got '$orphans'"

run_sps "$project_dir/bin/pkdel" libfoo >/dev/null
run_sps "$project_dir/bin/pkcheck" --database | grep -qx 'database: ok' ||
    fail 'empty package database did not validate'

# Removing one package must never delete a directory that a remaining package
# still claims in its manifest. A fonts-like package shares /usr/share with a
# filesystem-like base package; only the fonts subdirectories are exclusive.
shared_root=$tmp/shared-root
shared_db=$tmp/shared-db
shared_cache=$tmp/shared-cache
shared_build=$tmp/shared-build
mkdir -p "$shared_root" "$shared_cache" "$shared_build" \
    "$tmp/shared-stage-base/.SPS" "$tmp/shared-stage-base/usr/share" \
    "$tmp/shared-stage-base/etc" \
    "$tmp/shared-stage-fonts/.SPS" \
    "$tmp/shared-stage-fonts/usr/share/fonts/dejavu" \
    "$tmp/shared-stage-fonts/usr/share/licenses/dejavu-fonts"
{
    printf 'format\t1\n'
    printf 'name\tbasefs\nversion\t1\nrelease\t1\narch\tany\ndescription\tbase hierarchy\n'
} >"$tmp/shared-stage-base/.SPS/meta"
printf '%s\n' 'NAME="SPS"' >"$tmp/shared-stage-base/etc/os-release"
printf '%s\n' 'fontdata' >"$tmp/shared-stage-fonts/usr/share/fonts/dejavu/font.ttf"
printf '%s\n' 'license' >"$tmp/shared-stage-fonts/usr/share/licenses/dejavu-fonts/LICENSE"
{
    printf 'format\t1\n'
    printf 'name\tsharedfonts\nversion\t1\nrelease\t1\narch\tany\ndescription\tfont payload\n'
} >"$tmp/shared-stage-fonts/.SPS/meta"
for shared_stage in "$tmp/shared-stage-base" "$tmp/shared-stage-fonts"; do
    (
        CDPATH= cd "$shared_stage" &&
        find . -type d -print | awk '
            $0 != "." && $0 !~ /^\.\/\.SPS($|\/)/ { sub(/^\.\//, ""); print $0 "/" }'
        find . ! -type d -print | awk '
            $0 !~ /^\.\/\.SPS($|\/)/ { sub(/^\.\//, ""); print }'
    ) | LC_ALL=C sort >"$shared_stage/.SPS/files"
    : >"$shared_stage/.SPS/hashes"
    while IFS= read -r shared_entry || [ -n "$shared_entry" ]; do
        case $shared_entry in */) continue ;; esac
        [ -f "$shared_stage/$shared_entry" ] &&
            printf 'sha256\t%s\t%s\n' \
                "$(sha256sum "$shared_stage/$shared_entry" | awk '{ print $1 }')" \
                "$shared_entry" >>"$shared_stage/.SPS/hashes"
    done <"$shared_stage/.SPS/files"
done
tar -C "$tmp/shared-stage-base" -cf "$tmp/shared-base.pkg.tar" .
tar -C "$tmp/shared-stage-fonts" -cf "$tmp/shared-fonts.pkg.tar" .
SPS_ROOT=$shared_root SPS_DB=$shared_db SPS_CACHE=$shared_cache \
SPS_BUILD=$shared_build SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null \
SPS_LIBDIR=$project_dir/lib \
    "$project_dir/bin/pkin" --dependency "$tmp/shared-base.pkg.tar" >/dev/null ||
    fail 'shared base package failed to install'
SPS_ROOT=$shared_root SPS_DB=$shared_db SPS_CACHE=$shared_cache \
SPS_BUILD=$shared_build SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null \
SPS_LIBDIR=$project_dir/lib \
    "$project_dir/bin/pkin" "$tmp/shared-fonts.pkg.tar" >/dev/null ||
    fail 'shared fonts package failed to install'
[ -d "$shared_root/usr/share/fonts/dejavu" ] ||
    fail 'shared fonts payload was not installed'
SPS_ROOT=$shared_root SPS_DB=$shared_db SPS_CACHE=$shared_cache \
SPS_BUILD=$shared_build SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null \
SPS_LIBDIR=$project_dir/lib \
    "$project_dir/bin/pkdel" sharedfonts >/dev/null ||
    fail 'shared fonts package failed to remove'
[ ! -e "$shared_root/usr/share/fonts" ] &&
[ ! -e "$shared_root/usr/share/licenses" ] ||
    fail 'font-only directories were not pruned on removal'
[ -d "$shared_root/usr/share" ] ||
    fail 'removal deleted a shared directory still claimed by another package'
[ -d "$shared_root/usr" ] ||
    fail 'removal deleted a base directory still claimed by another package'
SPS_ROOT=$shared_root SPS_DB=$shared_db SPS_CACHE=$shared_cache \
SPS_BUILD=$shared_build SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null \
SPS_LIBDIR=$project_dir/lib \
    "$project_dir/bin/pkcheck" --database | grep -qx 'database: ok' ||
    fail 'database did not validate after shared-directory removal'

# Upgrading a package that drops a shared directory must not rmdir it when
# another installed package still lists that directory in its manifest.
up_root=$tmp/upgrade-root
up_db=$tmp/upgrade-db
up_cache=$tmp/upgrade-cache
up_build=$tmp/upgrade-build
mkdir -p "$up_root" "$up_cache" "$up_build" \
    "$tmp/up-stage-base/.SPS" "$tmp/up-stage-base/usr/share" \
    "$tmp/up-stage-base/etc" \
    "$tmp/up-stage-app1/.SPS" "$tmp/up-stage-app1/usr/share/app" \
    "$tmp/up-stage-app2/.SPS" "$tmp/up-stage-app2/usr/bin"
printf '%s\n' 'NAME="SPS"' >"$tmp/up-stage-base/etc/os-release"
printf '%s\n' 'payload' >"$tmp/up-stage-app1/usr/share/app/data"
printf '%s\n' 'tool' >"$tmp/up-stage-app2/usr/bin/shareapp"
{
    printf 'format\t1\n'
    printf 'name\tsharebase\nversion\t1\nrelease\t1\narch\tany\ndescription\tbase hierarchy\n'
} >"$tmp/up-stage-base/.SPS/meta"
{
    printf 'format\t1\n'
    printf 'name\tshareapp\nversion\t1\nrelease\t1\narch\tany\ndescription\tapp v1\n'
} >"$tmp/up-stage-app1/.SPS/meta"
{
    printf 'format\t1\n'
    printf 'name\tshareapp\nversion\t2\nrelease\t1\narch\tany\ndescription\tapp v2\n'
} >"$tmp/up-stage-app2/.SPS/meta"
for up_stage in "$tmp/up-stage-base" "$tmp/up-stage-app1" "$tmp/up-stage-app2"; do
    (
        CDPATH= cd "$up_stage" &&
        find . -type d -print | awk '
            $0 != "." && $0 !~ /^\.\/\.SPS($|\/)/ { sub(/^\.\//, ""); print $0 "/" }'
        find . ! -type d -print | awk '
            $0 !~ /^\.\/\.SPS($|\/)/ { sub(/^\.\//, ""); print }'
    ) | LC_ALL=C sort >"$up_stage/.SPS/files"
    : >"$up_stage/.SPS/hashes"
    while IFS= read -r up_entry || [ -n "$up_entry" ]; do
        case $up_entry in */) continue ;; esac
        [ -f "$up_stage/$up_entry" ] &&
            printf 'sha256\t%s\t%s\n' \
                "$(sha256sum "$up_stage/$up_entry" | awk '{ print $1 }')" \
                "$up_entry" >>"$up_stage/.SPS/hashes"
    done <"$up_stage/.SPS/files"
done
tar -C "$tmp/up-stage-base" -cf "$tmp/up-base.pkg.tar" .
tar -C "$tmp/up-stage-app1" -cf "$tmp/up-app1.pkg.tar" .
tar -C "$tmp/up-stage-app2" -cf "$tmp/up-app2.pkg.tar" .
SPS_ROOT=$up_root SPS_DB=$up_db SPS_CACHE=$up_cache \
SPS_BUILD=$up_build SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null \
SPS_LIBDIR=$project_dir/lib \
    "$project_dir/bin/pkin" --dependency "$tmp/up-base.pkg.tar" >/dev/null ||
    fail 'upgrade-shared base package failed to install'
SPS_ROOT=$up_root SPS_DB=$up_db SPS_CACHE=$up_cache \
SPS_BUILD=$up_build SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null \
SPS_LIBDIR=$project_dir/lib \
    "$project_dir/bin/pkin" "$tmp/up-app1.pkg.tar" >/dev/null ||
    fail 'upgrade-shared app v1 failed to install'
SPS_ROOT=$up_root SPS_DB=$up_db SPS_CACHE=$up_cache \
SPS_BUILD=$up_build SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null \
SPS_LIBDIR=$project_dir/lib \
    "$project_dir/bin/pkin" "$tmp/up-app2.pkg.tar" >/dev/null ||
    fail 'upgrade-shared app v2 failed to install'
[ -f "$up_root/usr/bin/shareapp" ] ||
    fail 'upgraded app payload was not installed'
[ ! -e "$up_root/usr/share/app" ] ||
    fail 'exclusive app directory was not pruned on upgrade'
[ -d "$up_root/usr/share" ] ||
    fail 'upgrade deleted a shared directory still claimed by another package'
[ -d "$up_root/usr" ] ||
    fail 'upgrade deleted a base directory still claimed by another package'
SPS_ROOT=$up_root SPS_DB=$up_db SPS_CACHE=$up_cache \
SPS_BUILD=$up_build SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null \
SPS_LIBDIR=$project_dir/lib \
    "$project_dir/bin/pkcheck" --database | grep -qx 'database: ok' ||
    fail 'database did not validate after shared-directory upgrade'

printf '%s\n' 'test_packages: ok'
