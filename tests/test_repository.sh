#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd)

fail()
{
    printf 'test_repository: %s\n' "$*" >&2
    exit 1
}

contains()
{
    case $1 in
        *"$2"*) return 0 ;;
        *) fail "expected output to contain: $2" ;;
    esac
}

expect_update_failure()
{
    expected=$1
    if "$src" update >"$tmp/failure.out" 2>"$tmp/failure.err"; then
        fail "repository update unexpectedly succeeded: $expected"
    fi
    contains "$(sed -n '1,30p' "$tmp/failure.err")" "$expected"
}

write_recipe()
{
    recipe_path=$1
    recipe_name=$2
    recipe_version=$3
    shift 3
    mkdir -p "${recipe_path%/*}"
    {
        printf 'name %s\n' "$recipe_name"
        printf 'version %s\n' "$recipe_version"
        printf '%s\n' 'release 1'
        printf 'description Repository test package %s\n' "$recipe_name"
        for recipe_field
        do
            printf '%s\n' "$recipe_field"
        done
        printf '%s\n' 'install true'
    } >"$recipe_path"
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-repository.XXXXXX")
trap 'rm -rf "$tmp"' 0 1 2 3 15

mkdir -p "$tmp/root" "$tmp/cache" "$tmp/db" "$tmp/build" \
    "$tmp/core/base" "$tmp/extra/apps" "$tmp/later/apps"
: >"$tmp/sps.conf"

write_recipe "$tmp/core/base/alpha/recipe" alpha 1.0 'depend tie'
write_recipe "$tmp/core/base/tie/recipe" tie 1.0
write_recipe "$tmp/extra/apps/alpha/recipe" alpha 2.0 \
    'optional unavailable-optional'
write_recipe "$tmp/later/apps/tie/recipe" tie 9.0

# Support trees may legitimately contain a file named recipe; they are data,
# not additional package definitions.
for support in files patches hooks .git; do
    mkdir -p "$tmp/core/base/alpha/$support/nested"
    printf '%s\n' 'this is not package metadata' \
        >"$tmp/core/base/alpha/$support/nested/recipe"
done

{
    printf 'dir core %s 10\n' "$tmp/core"
    printf 'dir extra %s 20\n' "$tmp/extra"
    printf 'repo later %s 10\n' "$tmp/later"
} >"$tmp/repos.conf"

SPS_ROOT=$tmp/root
SPS_DB=$tmp/db
SPS_CACHE=$tmp/cache
SPS_BUILD=$tmp/build
SPS_REPO_ROOT=$tmp/checkouts
SPS_CONFIG=$tmp/sps.conf
SPS_REPOS_CONFIG=$tmp/repos.conf
export SPS_ROOT SPS_DB SPS_CACHE SPS_BUILD SPS_REPO_ROOT SPS_CONFIG
export SPS_REPOS_CONFIG

src=$project_dir/bin/src
update_output=$("$src" update)
contains "$update_output" 'updated 3 repositories, 4 package records'

index=$tmp/cache/indexes/packages.index
[ -r "$index" ] || fail 'aggregate index was not created'
awk -F '\t' 'NF != 12 { bad = 1 }
             END { exit bad || NR != 4 }' "$index" ||
    fail 'aggregate index does not contain four valid records'

alpha_raw=$("$src" show alpha --raw)
[ "$(printf '%s\n' "$alpha_raw" | awk -F '\t' '{ print $8 }')" = extra ] ||
    fail 'higher-priority repository did not win'
[ "$(printf '%s\n' "$alpha_raw" | awk -F '\t' '{ print $2 "-" $3 }')" = 2.0-1 ] ||
    fail 'selected package version is wrong'

tie_raw=$("$src" show tie --raw)
[ "$(printf '%s\n' "$tie_raw" | awk -F '\t' '{ print $8 }')" = core ] ||
    fail 'configuration order did not break an equal-priority cross-repository tie'

search_output=$("$src" search 'REPOSITORY TEST')
contains "$search_output" 'alpha'
contains "$search_output" 'tie'

show_output=$("$src" show alpha)
contains "$show_output" 'repository: extra'
contains "$show_output" 'optional dependencies: unavailable-optional'

which_output=$("$src" which alpha)
contains "$which_output" 'selected: extra'
contains "$which_output" 'also available:'
contains "$which_output" 'core'

list_output=$("$src" list)
contains "$list_output" 'core'
contains "$list_output" 'dir'
contains "$list_output" 'priority 20'
list_raw=$("$src" list --raw)
[ "$(printf '%s\n' "$list_raw" | awk -F '\t' 'NR == 3 { print $1 }')" = dir ] ||
    fail 'repo compatibility alias was not normalized to dir'
status_output=$("$src" status)
contains "$status_output" 'core: 2 packages'
contains "$status_output" 'extra: 1 packages'

old_index=$(cksum "$index")
cp "$tmp/repos.conf" "$tmp/repos.good"

printf '%s\n' 'dir malformed' >>"$tmp/repos.conf"
expect_update_failure "expected 'git NAME SOURCE"
[ "$(cksum "$index")" = "$old_index" ] ||
    fail 'malformed configuration replaced the previous index'
cp "$tmp/repos.good" "$tmp/repos.conf"

printf 'dir too-many %s 1 trailing-field\n' "$tmp/core" >>"$tmp/repos.conf"
expect_update_failure "expected 'git NAME SOURCE"
cp "$tmp/repos.good" "$tmp/repos.conf"

printf '%s\n' 'dir relative relative/path 1' >>"$tmp/repos.conf"
expect_update_failure 'requires an absolute path'
cp "$tmp/repos.good" "$tmp/repos.conf"

printf 'dir bad-priority %s high\n' "$tmp/core" >>"$tmp/repos.conf"
expect_update_failure "invalid priority 'high'"
cp "$tmp/repos.good" "$tmp/repos.conf"

printf 'dir huge %s 2147483648\n' "$tmp/core" >>"$tmp/repos.conf"
expect_update_failure 'priority out of range'
cp "$tmp/repos.good" "$tmp/repos.conf"

printf 'dir core %s 30\n' "$tmp/core" >>"$tmp/repos.conf"
expect_update_failure "duplicate repository 'core'"
cp "$tmp/repos.good" "$tmp/repos.conf"

printf 'bogus bad %s 1\n' "$tmp/core" >>"$tmp/repos.conf"
expect_update_failure "expected 'git NAME SOURCE"
cp "$tmp/repos.good" "$tmp/repos.conf"

printf '%s\n' \
    'git credential https://reader:supersecret123@example.invalid/packages.git 1' \
    >>"$tmp/repos.conf"
expect_update_failure 'credential-bearing HTTP(S) Git source'
if grep -F 'supersecret123' "$tmp/failure.err" >/dev/null; then
    fail 'credential-bearing Git source was repeated in an error'
fi
cp "$tmp/repos.good" "$tmp/repos.conf"

write_recipe "$tmp/core/other/tie/recipe" tie 3.0
expect_update_failure "duplicate package 'tie' in repository 'core'"
[ "$(cksum "$index")" = "$old_index" ] ||
    fail 'duplicate package replaced the previous index'
rm -rf "$tmp/core/other"

write_recipe "$tmp/core/base/broken-runtime/recipe" broken-runtime 1.0 \
    'depend unavailable-runtime'
expect_update_failure "dependency 'unavailable-runtime'"
[ "$(cksum "$index")" = "$old_index" ] ||
    fail 'missing dependency replaced the previous index'
rm -rf "$tmp/core/base/broken-runtime"

write_recipe "$tmp/core/base/broken-build/recipe" broken-build 1.0 \
    'builddep unavailable-build'
expect_update_failure "dependency 'unavailable-build'"
rm -rf "$tmp/core/base/broken-build"

write_recipe "$tmp/core/base/cycle-a/recipe" cycle-a 1.0 'depend cycle-b'
write_recipe "$tmp/core/base/cycle-b/recipe" cycle-b 1.0 'depend cycle-a'
expect_update_failure 'dependency cycle:'
rm -rf "$tmp/core/base/cycle-a" "$tmp/core/base/cycle-b"

mkdir "$tmp/cache/.src-update"
printf '%s\n' $$ >"$tmp/cache/.src-update/pid"
expect_update_failure 'another repository update is active'
rm -rf "$tmp/cache/.src-update"

"$src" update >/dev/null || fail 'repository did not recover after failed updates'
printf '%s\n' 'repository and query tests passed'
