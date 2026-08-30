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

printf '%s\n' 'test_packages: ok'
