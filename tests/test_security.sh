#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1

fail()
{
    printf 'test_security: %s\n' "$*" >&2
    exit 1
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

expect_status()
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

fresh_root()
{
    test_number=$((test_number + 1))
    root=$tmp/root-$test_number
    db=$tmp/db-$test_number
    cache=$tmp/cache-$test_number
    build=$tmp/build-$test_number
    mkdir -p "$root" "$cache" "$build"
}

make_basic()
{
    package_name=$1
    package_version=$2
    package_path=${3:-usr/bin/$package_name}
    package_stage=$tmp/stage-$package_name-$package_version
    package_archive=$tmp/$package_name-$package_version.pkg.tar
    rm -rf "$package_stage"
    mkdir -p "$package_stage/.SPS" "$package_stage/$(dirname "$package_path")"
    printf '%s\n' "$package_name $package_version payload" >"$package_stage/$package_path"
    {
        printf 'format\t1\n'
        printf 'name\t%s\n' "$package_name"
        printf 'version\t%s\n' "$package_version"
        printf 'release\t1\n'
        printf 'arch\tany\n'
    } >"$package_stage/.SPS/meta"
    : >"$package_stage/.SPS/files.tmp"
    (CDPATH= cd "$package_stage" && find . ! -name . ! -path './.SPS' ! -path './.SPS/*' -print) |
    sed 's#^\./##' | while IFS= read -r package_entry; do
        if [ -d "$package_stage/$package_entry" ] && [ ! -L "$package_stage/$package_entry" ]; then
            printf '%s/\n' "$package_entry"
        else
            printf '%s\n' "$package_entry"
        fi
    done >"$package_stage/.SPS/files.tmp"
    LC_ALL=C sort "$package_stage/.SPS/files.tmp" >"$package_stage/.SPS/files"
    rm -f "$package_stage/.SPS/files.tmp"
    package_hash=$(sha256sum "$package_stage/$package_path" | awk '{ print $1 }')
    printf 'sha256\t%s\t%s\n' "$package_hash" "$package_path" >"$package_stage/.SPS/hashes"
    tar -C "$package_stage" -cf "$package_archive" .
    printf '%s\n' "$package_archive"
}

repack()
{
    repack_stage=$1
    repack_archive=$2
    tar -C "$repack_stage" -cf "$repack_archive" .
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-security.XXXXXX") ||
    fail 'cannot create temporary directory'
trap 'rm -rf "$tmp"' 0 HUP INT TERM
test_number=0

# Reject traversal in the manifest before touching the root or database.
fresh_root
archive=$(make_basic traversal 1.0)
stage=$tmp/stage-traversal-1.0
printf '%s\n' '../escape' >"$stage/.SPS/files"
: >"$stage/.SPS/hashes"
repack "$stage" "$archive"
expect_status 4 "$project_dir/bin/pkin" "$archive"
[ ! -f "$tmp/escape" ] || fail 'manifest traversal escaped the fake root'
[ ! -d "$db/installed/traversal" ] || fail 'unsafe manifest was recorded as installed'

# Build a real ../ archive member. Most tar tools refuse to create one, so make
# a normal header, patch the pathname in place, and recompute the ustar checksum.
# This keeps the fixture portable across tar implementations.
fresh_root
mkdir -p "$tmp/raw-traversal/aa"
printf '%s\n' sentinel >"$tmp/raw-traversal/aa/escape"
tar -C "$tmp/raw-traversal" -cf "$tmp/raw-traversal.pkg.tar" aa/escape ||
    fail 'test tar could not construct base traversal fixture'
printf '%s' '../escape' | dd of="$tmp/raw-traversal.pkg.tar" bs=1 seek=0 conv=notrunc 2>/dev/null ||
    fail 'cannot patch traversal archive member'
printf '        ' | dd of="$tmp/raw-traversal.pkg.tar" bs=1 seek=148 conv=notrunc 2>/dev/null ||
    fail 'cannot clear traversal header checksum'
header_sum=$(od -An -tu1 -N512 "$tmp/raw-traversal.pkg.tar" |
    awk '{ for (i = 1; i <= NF; i++) sum += $i } END { print sum + 0 }')
# ustar checksum field: six octal digits, NUL, space.
printf '%06o\0 ' "$header_sum" |
    dd of="$tmp/raw-traversal.pkg.tar" bs=1 seek=148 conv=notrunc 2>/dev/null ||
    fail 'cannot write traversal header checksum'
[ "$(dd if="$tmp/raw-traversal.pkg.tar" bs=1 count=9 2>/dev/null)" = '../escape' ] ||
    fail 'constructed traversal archive header is incorrect'
expect_status 4 "$project_dir/bin/pkin" "$tmp/raw-traversal.pkg.tar"
[ "$(cat "$tmp/raw-traversal/aa/escape")" = sentinel ] || fail 'archive traversal changed its source sentinel'

# Required identity fields must be valid.
fresh_root
archive=$(make_basic badmeta 1.0)
stage=$tmp/stage-badmeta-1.0
awk '$1 != "version"' "$stage/.SPS/meta" >"$stage/.SPS/meta.new"
mv "$stage/.SPS/meta.new" "$stage/.SPS/meta"
repack "$stage" "$archive"
expect_status 4 "$project_dir/bin/pkin" "$archive"

# A well-formed but wrong digest is a checksum failure, not a format failure.
fresh_root
archive=$(make_basic badsum 1.0)
stage=$tmp/stage-badsum-1.0
printf 'sha256\t%s\tusr/bin/badsum\n' \
    0000000000000000000000000000000000000000000000000000000000000000 \
    >"$stage/.SPS/hashes"
repack "$stage" "$archive"
expect_status 6 "$project_dir/bin/pkin" "$archive"
[ ! -f "$root/usr/bin/badsum" ] || fail 'checksum failure installed payload'

# Old-style executable control members are not part of the package format.
fresh_root
archive=$(make_basic hook 1.0)
stage=$tmp/stage-hook-1.0
printf '%s\n' 'exit 0' >"$stage/.SPS/install"
repack "$stage" "$archive"
expect_status 4 "$project_dir/bin/pkin" "$archive"
grep -q 'unsupported package control member' "$tmp/stderr" ||
    fail 'hook rejection diagnostic is unclear'

# Unowned existing files and symlink ancestors are conflicts.
fresh_root
archive=$(make_basic occupied 1.0)
mkdir -p "$root/usr/bin"
printf '%s\n' administrator >"$root/usr/bin/occupied"
expect_status 7 "$project_dir/bin/pkin" "$archive"
[ "$(cat "$root/usr/bin/occupied")" = administrator ] || fail 'unowned collision was overwritten'

# Identical unowned bytes are adopted. Live /bin -> usr/bin must not block
# filesystem, but a different symlink target is still a conflict.
fresh_root
stage=$tmp/stage-identical-link
mkdir -p "$stage/.SPS" "$stage/usr/bin" "$root/usr/bin"
ln -s usr/bin "$stage/bin"
ln -s usr/bin "$root/bin"
printf '%s\n' same >"$stage/usr/bin/tool"
printf '%s\n' same >"$root/usr/bin/tool"
{
    printf 'format\t1\n'
    printf 'name\tidenticallink\nversion\t1.0\nrelease\t1\narch\tany\n'
} >"$stage/.SPS/meta"
: >"$stage/.SPS/files.tmp"
(CDPATH= cd "$stage" && find . ! -name . ! -path './.SPS' ! -path './.SPS/*' -print) |
sed 's#^\./##' | while IFS= read -r package_entry; do
    if [ -d "$stage/$package_entry" ] && [ ! -L "$stage/$package_entry" ]; then
        printf '%s/\n' "$package_entry"
    else
        printf '%s\n' "$package_entry"
    fi
done >"$stage/.SPS/files.tmp"
LC_ALL=C sort "$stage/.SPS/files.tmp" >"$stage/.SPS/files"
rm -f "$stage/.SPS/files.tmp"
printf 'sha256\t%s\tusr/bin/tool\n' \
    "$(sha256sum "$stage/usr/bin/tool" | awk '{ print $1 }')" \
    >"$stage/.SPS/hashes"
tar -C "$stage" -cf "$tmp/identicallink.pkg.tar" .
run_sps "$project_dir/bin/pkin" "$tmp/identicallink.pkg.tar" >/dev/null ||
    fail 'identical unowned symlink/file should be adopted'
[ -L "$root/bin" ] || fail 'adopted usr-merge /bin was lost'
[ "$(readlink "$root/bin")" = usr/bin ] || fail 'adopted /bin target changed'

fresh_root
stage=$tmp/stage-different-link
mkdir -p "$stage/.SPS" "$stage/usr/bin" "$root/usr/sbin"
ln -s usr/bin "$stage/bin"
ln -s usr/sbin "$root/bin"
printf '%s\n' same >"$stage/usr/bin/tool"
{
    printf 'format\t1\n'
    printf 'name\tdifferentlink\nversion\t1.0\nrelease\t1\narch\tany\n'
} >"$stage/.SPS/meta"
: >"$stage/.SPS/files.tmp"
(CDPATH= cd "$stage" && find . ! -name . ! -path './.SPS' ! -path './.SPS/*' -print) |
sed 's#^\./##' | while IFS= read -r package_entry; do
    if [ -d "$stage/$package_entry" ] && [ ! -L "$stage/$package_entry" ]; then
        printf '%s/\n' "$package_entry"
    else
        printf '%s\n' "$package_entry"
    fi
done >"$stage/.SPS/files.tmp"
LC_ALL=C sort "$stage/.SPS/files.tmp" >"$stage/.SPS/files"
rm -f "$stage/.SPS/files.tmp"
printf 'sha256\t%s\tusr/bin/tool\n' \
    "$(sha256sum "$stage/usr/bin/tool" | awk '{ print $1 }')" \
    >"$stage/.SPS/hashes"
tar -C "$stage" -cf "$tmp/differentlink.pkg.tar" .
expect_status 7 "$project_dir/bin/pkin" "$tmp/differentlink.pkg.tar"
[ "$(readlink "$root/bin")" = usr/sbin ] || fail 'different symlink target was replaced'

fresh_root
archive=$(make_basic redirected 1.0)
outside=$tmp/outside-target
mkdir -p "$outside/bin"
ln -s "$outside" "$root/usr"
expect_status 7 "$project_dir/bin/pkin" "$archive"
[ ! -f "$outside/bin/redirected" ] || fail 'target symlink redirected package payload'

# Never follow a symlink where an installed database control file should be.
fresh_root
archive=$(make_basic dbtrap 1.0)
mkdir -p "$db/installed"
printf '%s\n' keep >"$tmp/db-victim"
ln -s "$tmp/db-victim" "$db/owners"
: >"$db/world"
: >"$db/history"
expect_status 11 "$project_dir/bin/pkin" "$archive"
[ "$(cat "$tmp/db-victim")" = keep ] || fail 'symlinked database control was modified'

# Package control metadata must be a regular file in the archive.
fresh_root
archive=$(make_basic controlink 1.0)
stage=$tmp/stage-controlink-1.0
cp "$stage/.SPS/meta" "$tmp/controlink-meta"
rm -f "$stage/.SPS/meta"
ln -s "$tmp/controlink-meta" "$stage/.SPS/meta"
repack "$stage" "$archive"
expect_status 4 "$project_dir/bin/pkin" "$archive"

# A bad installed manifest must stop an upgrade before payload replacement.
fresh_root
archive_v1=$(make_basic guarded 1.0)
run_sps "$project_dir/bin/pkin" "$archive_v1" >/dev/null
archive_v2=$(make_basic guarded 2.0)
printf '%s\n' '../../victim' >"$db/installed/guarded/files"
expect_status 11 "$project_dir/bin/pkin" "$archive_v2"
[ "$(cat "$root/usr/bin/guarded")" = 'guarded 1.0 payload' ] ||
    fail 'malformed old record allowed payload replacement'

# Payload symlinks are allowed, but no later payload entry may live below one.
# Some tar implementations catch this first; pkin must catch it either way.
fresh_root
stage=$tmp/stage-linkparent
archive=$tmp/linkparent.pkg.tar
outside=$tmp/linkparent-outside
mkdir -p "$stage/.SPS" "$outside"
printf '%s\n' sentinel >"$outside/pwn"
ln -s "$outside" "$stage/link"
{
    printf 'name\tlinkparent\nversion\t1.0\nrelease\t1\narch\tany\n'
} >"$stage/.SPS/meta"
printf 'link\nlink/pwn\n' >"$stage/.SPS/files"
pwn_hash=$(sha256sum "$outside/pwn" | awk '{ print $1 }')
printf 'sha256\t%s\tlink/pwn\n' "$pwn_hash" >"$stage/.SPS/hashes"
tar -C "$stage" -cf "$archive" .SPS link link/pwn
expect_status 4 "$project_dir/bin/pkin" "$archive"
[ "$(cat "$outside/pwn")" = sentinel ] || fail 'archive symlink parent escaped extraction staging'

printf '%s\n' 'test_security: ok'
