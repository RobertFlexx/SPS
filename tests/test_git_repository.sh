#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd)

if ! command -v git >/dev/null 2>&1; then
    printf '%s\n' 'git repository tests skipped: git is unavailable'
    exit 0
fi

fail()
{
    printf 'test_git_repository: %s\n' "$*" >&2
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
        fail "Git update unexpectedly succeeded: $expected"
    fi
    contains "$(sed -n '1,40p' "$tmp/failure.err")" "$expected"
}

write_seed_recipe()
{
    seed_version=$1
    mkdir -p "$seed/base/alpha"
    {
        printf '%s\n' 'name alpha'
        printf 'version %s\n' "$seed_version"
        printf '%s\n' 'release 1'
        printf 'description Git repository alpha %s\n' "$seed_version"
        printf '%s\n' 'install true'
    } >"$seed/base/alpha/recipe"
}

push_seed_version()
{
    pushed_version=$1
    write_seed_recipe "$pushed_version"
    git -C "$seed" add base/alpha/recipe
    git -C "$seed" commit -m "alpha $pushed_version" >/dev/null
    git -C "$seed" push origin main >/dev/null 2>&1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-git-repository.XXXXXX")
trap 'rm -rf "$tmp"' 0 1 2 3 15

origin=$tmp/core.git
seed=$tmp/seed
checkout=$tmp/checkouts/core
mkdir -p "$tmp/root" "$tmp/cache" "$tmp/db" "$tmp/build"
: >"$tmp/sps.conf"

git init --bare "$origin" >/dev/null 2>&1
git init "$seed" >/dev/null 2>&1
git -C "$seed" config user.name 'SPS Test'
git -C "$seed" config user.email 'sps-test@example.invalid'
git -C "$seed" config commit.gpgsign false
write_seed_recipe 1.0
git -C "$seed" add base/alpha/recipe
git -C "$seed" commit -m 'initial alpha' >/dev/null
git -C "$seed" branch -M main
git -C "$seed" remote add origin "$origin"
git -C "$seed" push -u origin main >/dev/null 2>&1
git -C "$origin" symbolic-ref HEAD refs/heads/main

printf 'git core %s 100\n' "$origin" >"$tmp/repos.conf"
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
first_update=$("$src" update 2>"$tmp/clone.err")
contains "$first_update" 'updated 1 repositories, 1 package records'
contains "$(cat "$tmp/clone.err")" "cloned repository 'core'"
[ -d "$checkout/.git" ] || fail 'Git checkout was not created below SPS_REPO_ROOT'
[ "$("$src" show alpha --raw | awk -F '\t' '{ print $2 }')" = 1.0 ] ||
    fail 'initial Git package was not indexed'
normalized=$("$src" list --raw)
printf '%s\n' "$normalized" | awk -F '\t' \
    -v source="$origin" -v checkout="$checkout" '
    NF == 6 && $1 == "git" && $2 == "core" && $3 == source &&
    $4 == checkout && $5 == 100 && $6 == 1 { found = 1 }
    END { exit !found }
' || fail 'Git repository did not produce the canonical normalized record'
contains "$("$src" status)" "$checkout"

push_seed_version 2.0
remote_v2=$(git -C "$seed" rev-parse HEAD)
"$src" update >/dev/null 2>"$tmp/ff.err"
[ "$(git -C "$checkout" rev-parse HEAD)" = "$remote_v2" ] ||
    fail 'clean Git checkout was not fast-forwarded'
[ "$("$src" show alpha --raw | awk -F '\t' '{ print $2 }')" = 2.0 ] ||
    fail 'fast-forwarded recipe was not indexed'

# Dirty worktrees fail before fetch, leaving HEAD, remote-tracking refs, content,
# and the previous package index untouched.
printf '%s\n' '# local tracked change' >>"$checkout/base/alpha/recipe"
push_seed_version 3.0
dirty_head=$(git -C "$checkout" rev-parse HEAD)
dirty_remote=$(git -C "$checkout" rev-parse refs/remotes/origin/main)
index=$tmp/cache/indexes/packages.index
dirty_index=$(cksum "$index")
expect_update_failure 'has local modifications'
[ "$(git -C "$checkout" rev-parse HEAD)" = "$dirty_head" ] ||
    fail 'dirty update moved HEAD'
[ "$(git -C "$checkout" rev-parse refs/remotes/origin/main)" = "$dirty_remote" ] ||
    fail 'dirty update fetched before refusing the worktree'
grep -q 'local tracked change' "$checkout/base/alpha/recipe" ||
    fail 'dirty update discarded tracked content'
[ "$(cksum "$index")" = "$dirty_index" ] ||
    fail 'dirty update replaced the previous index'

git -C "$checkout" checkout -- base/alpha/recipe
"$src" update >/dev/null 2>"$tmp/ff3.err"
[ "$("$src" show alpha --raw | awk -F '\t' '{ print $2 }')" = 3.0 ] ||
    fail 'checkout did not recover after tracked dirt was removed'

printf '%s\n' untracked >"$checkout/untracked"
untracked_index=$(cksum "$index")
expect_update_failure 'has local modifications'
[ -f "$checkout/untracked" ] || fail 'dirty update discarded an untracked file'
[ "$(cksum "$index")" = "$untracked_index" ] ||
    fail 'untracked update replaced the previous index'
rm -f "$checkout/untracked"

wrong_origin=https://reader:originsecret456@example.invalid/private.git
git -C "$checkout" remote set-url origin "$wrong_origin"
origin_head=$(git -C "$checkout" rev-parse HEAD)
expect_update_failure 'origin does not match its configured source'
if grep -F 'originsecret456' "$tmp/failure.err" >/dev/null ||
   grep -F "$origin" "$tmp/failure.err" >/dev/null; then
    fail 'origin mismatch error repeated a configured or actual origin'
fi
[ "$(git -C "$checkout" rev-parse HEAD)" = "$origin_head" ] ||
    fail 'origin mismatch moved HEAD'
git -C "$checkout" remote set-url origin "$origin"

# Detached HEAD is a commit pin: fetch updates remote refs but does not move it.
git -C "$checkout" checkout --detach HEAD >/dev/null 2>&1
detached_head=$(git -C "$checkout" rev-parse HEAD)
push_seed_version 4.0
remote_v4=$(git -C "$seed" rev-parse HEAD)
"$src" update >/dev/null 2>"$tmp/detached.err"
contains "$(cat "$tmp/detached.err")" 'is detached and remains pinned'
[ "$(git -C "$checkout" rev-parse HEAD)" = "$detached_head" ] ||
    fail 'detached Git pin moved'
[ "$(git -C "$checkout" rev-parse refs/remotes/origin/main)" = "$remote_v4" ] ||
    fail 'detached Git pin did not fetch origin'
[ "$("$src" show alpha --raw | awk -F '\t' '{ print $2 }')" = 3.0 ] ||
    fail 'detached checkout did not index its pinned recipe'

git -C "$checkout" checkout main >/dev/null 2>&1
"$src" update >/dev/null 2>"$tmp/ff4.err"
[ "$(git -C "$checkout" rev-parse HEAD)" = "$remote_v4" ] ||
    fail 'main did not fast-forward after leaving detached state'

# A branch without an upstream is also an explicit pin.
git -C "$checkout" checkout -b pinned >/dev/null 2>&1
git -C "$checkout" branch --unset-upstream >/dev/null 2>&1 || :
no_upstream_head=$(git -C "$checkout" rev-parse HEAD)
push_seed_version 5.0
"$src" update >/dev/null 2>"$tmp/no-upstream.err"
contains "$(cat "$tmp/no-upstream.err")" 'has no upstream and remains pinned'
[ "$(git -C "$checkout" rev-parse HEAD)" = "$no_upstream_head" ] ||
    fail 'branch without an upstream moved'
[ "$("$src" show alpha --raw | awk -F '\t' '{ print $2 }')" = 4.0 ] ||
    fail 'no-upstream branch did not index its pinned recipe'

git -C "$checkout" checkout main >/dev/null 2>&1
"$src" update >/dev/null 2>"$tmp/ff5.err"
[ "$("$src" show alpha --raw | awk -F '\t' '{ print $2 }')" = 5.0 ] ||
    fail 'main did not fast-forward after leaving no-upstream branch'

# Clean local commits are preserved. Once origin independently advances, the
# histories diverge and src must refuse rather than reset either side.
printf '%s\n' '# local committed policy' >>"$checkout/base/alpha/recipe"
git -C "$checkout" add base/alpha/recipe
git -C "$checkout" -c user.name='SPS Test' \
    -c user.email='sps-test@example.invalid' commit -m 'local policy' >/dev/null
local_ahead_head=$(git -C "$checkout" rev-parse HEAD)
"$src" update >/dev/null 2>"$tmp/ahead.err"
contains "$(cat "$tmp/ahead.err")" 'is ahead of origin/main and was left unchanged'
[ "$(git -C "$checkout" rev-parse HEAD)" = "$local_ahead_head" ] ||
    fail 'locally ahead branch moved'

push_seed_version 6.0
diverged_index=$(cksum "$index")
expect_update_failure 'has diverged from origin/main'
[ "$(git -C "$checkout" rev-parse HEAD)" = "$local_ahead_head" ] ||
    fail 'diverged update moved local HEAD'
grep -q 'local committed policy' "$checkout/base/alpha/recipe" ||
    fail 'diverged update discarded local commit content'
[ "$(cksum "$index")" = "$diverged_index" ] ||
    fail 'diverged update replaced the previous index'

printf '%s\n' 'Git repository synchronization tests passed'
