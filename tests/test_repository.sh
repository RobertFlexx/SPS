#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd)
if [ ! -r "$project_dir/lib/common.sh" ]; then
    printf '%s\n' 'repository tests skipped: lib/common.sh is not integrated'
    exit 0
fi

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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-repository.XXXXXX")
trap 'rm -rf "$tmp"' 0 1 2 3 15

mkdir -p "$tmp/root" "$tmp/cache" "$tmp/db" "$tmp/build" \
    "$tmp/core/base/alpha" "$tmp/core/base/tie" "$tmp/core/z/tie" \
    "$tmp/extra/apps/alpha" "$tmp/later/apps/tie"
: > "$tmp/sps.conf"

{
    printf '%s\n' 'name alpha'
    printf '%s\n' 'version 1.0'
    printf '%s\n' 'release 1'
    printf '%s\n' 'description Core alpha'
    printf '%s\n' 'depend tie'
    printf '%s\n' 'install true'
} > "$tmp/core/base/alpha/recipe"
{
    printf '%s\n' 'name tie'
    printf '%s\n' 'version 1.0'
    printf '%s\n' 'release 1'
    printf '%s\n' 'description First configured tie'
    printf '%s\n' 'install true'
} > "$tmp/core/base/tie/recipe"
{
    printf '%s\n' 'name tie'
    printf '%s\n' 'version 8.0'
    printf '%s\n' 'release 1'
    printf '%s\n' 'description Later path in the same repository'
    printf '%s\n' 'install true'
} > "$tmp/core/z/tie/recipe"
{
    printf '%s\n' 'name alpha'
    printf '%s\n' 'version 2.0'
    printf '%s\n' 'release 3'
    printf '%s\n' 'description Alpha override \'
    printf '%s\n' '  from the local repository'
    printf '%s\n' 'install true'
} > "$tmp/extra/apps/alpha/recipe"
{
    printf '%s\n' 'name tie'
    printf '%s\n' 'version 9.0'
    printf '%s\n' 'release 1'
    printf '%s\n' 'description Later configured tie'
    printf '%s\n' 'install true'
} > "$tmp/later/apps/tie/recipe"

{
    printf 'repo core %s 10\n' "$tmp/core"
    printf 'repo extra %s 20\n' "$tmp/extra"
    printf 'repo later %s 10\n' "$tmp/later"
} > "$tmp/repos.conf"

SPS_ROOT=$tmp/root
SPS_DB=$tmp/db
SPS_CACHE=$tmp/cache
SPS_BUILD=$tmp/build
SPS_CONFIG=$tmp/sps.conf
SPS_REPOS_CONFIG=$tmp/repos.conf
export SPS_ROOT SPS_DB SPS_CACHE SPS_BUILD SPS_CONFIG SPS_REPOS_CONFIG

src=$project_dir/bin/src
update_output=$("$src" update)
contains "$update_output" 'updated 3 repositories, 5 package records'

index=$tmp/cache/indexes/packages.index
[ -r "$index" ] || fail 'aggregate index was not created'
awk -F '	' 'NF != 12 { bad = 1 }
             END { exit bad || NR != 5 }' "$index" ||
    fail 'aggregate index does not contain five valid 12-field records'

alpha_raw=$("$src" show alpha --raw)
[ "$(printf '%s\n' "$alpha_raw" | awk -F '	' '{ print $8 }')" = extra ] ||
    fail 'higher-priority repository did not win'
[ "$(printf '%s\n' "$alpha_raw" | awk -F '	' '{ print $2 "-" $3 }')" = 2.0-3 ] ||
    fail 'selected package version is wrong'

tie_raw=$("$src" show tie --raw)
[ "$(printf '%s\n' "$tie_raw" | awk -F '	' '{ print $8 }')" = core ] ||
    fail 'repository configuration order did not break an equal-priority tie'
[ "$(printf '%s\n' "$tie_raw" | awk -F '	' '{ print $10 }')" = \
   "$tmp/core/base/tie/recipe" ] ||
    fail 'recipe path order did not break an equal-priority intra-repository tie'

search_output=$("$src" search 'LOCAL REPOSITORY')
contains "$search_output" 'alpha'
contains "$search_output" 'extra'

show_output=$("$src" show alpha)
contains "$show_output" 'description: Alpha override'
contains "$show_output" 'repository: extra'

which_output=$("$src" which alpha)
contains "$which_output" 'selected: extra'
contains "$which_output" 'also available:'
contains "$which_output" 'core'

list_output=$("$src" list)
contains "$list_output" 'core'
contains "$list_output" 'priority 20'
status_output=$("$src" status)
contains "$status_output" 'core: 3 packages'
contains "$status_output" 'extra: 1 packages'

old_index=$(cksum "$index")
printf 'repo remote https://example.invalid/sps 100\n' >> "$tmp/repos.conf"
if "$src" update > "$tmp/remote.out" 2> "$tmp/remote.err"; then
    fail 'remote repository unexpectedly succeeded in SPS 1.0'
fi
contains "$(sed -n '1,20p' "$tmp/remote.err")" 'unsupported remote location'
[ "$(cksum "$index")" = "$old_index" ] ||
    fail 'a failed update replaced the previous aggregate index'

printf '%s\n' 'repository and query tests passed'
