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

write_meta()
{
    write_meta_dir=$1
    write_meta_name=$2
    write_meta_version=${3:-1.0}
    mkdir -p "$write_meta_dir/.SPS"
    {
        printf 'format\t1\n'
        printf 'name\t%s\n' "$write_meta_name"
        printf 'version\t%s\n' "$write_meta_version"
        printf 'release\t1\n'
        printf 'arch\tany\n'
    } >"$write_meta_dir/.SPS/meta"
}

pack_stage()
{
    pack_dir=$1
    pack_archive=$2
    mkdir -p "$pack_dir/.SPS"
    : >"$pack_dir/.SPS/files.tmp"
    : >"$pack_dir/.SPS/hashes"
    (CDPATH= cd "$pack_dir" && find . ! -name . ! -path './.SPS' ! -path './.SPS/*' -print) |
    sed 's#^\./##' | while IFS= read -r package_entry; do
        if [ -d "$pack_dir/$package_entry" ] && [ ! -L "$pack_dir/$package_entry" ]; then
            printf '%s/\n' "$package_entry"
        else
            printf '%s\n' "$package_entry"
        fi
    done >"$pack_dir/.SPS/files.tmp"
    LC_ALL=C sort "$pack_dir/.SPS/files.tmp" >"$pack_dir/.SPS/files"
    rm -f "$pack_dir/.SPS/files.tmp"
    while IFS= read -r package_entry; do
        case $package_entry in */) continue ;; esac
        if [ -f "$pack_dir/$package_entry" ] && [ ! -L "$pack_dir/$package_entry" ]; then
            printf 'sha256\t%s\t%s\n' \
                "$(sha256sum "$pack_dir/$package_entry" | awk '{ print $1 }')" \
                "$package_entry" >>"$pack_dir/.SPS/hashes"
        fi
    done <"$pack_dir/.SPS/files"
    LC_ALL=C sort "$pack_dir/.SPS/hashes" -o "$pack_dir/.SPS/hashes"
    tar -C "$pack_dir" -cf "$pack_archive" .
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

# Usr-merge /lib -> usr/lib is a shared directory. Packages that install
# udev rules under lib/udev must land in usr/lib without replacing the link.
fresh_root
stage=$tmp/stage-udevlib
mkdir -p "$stage/lib/udev/rules.d" "$root/usr/lib"
ln -s usr/lib "$root/lib"
printf '%s\n' 'KERNEL=="test"' >"$stage/lib/udev/rules.d/99-test.rules"
write_meta "$stage" udevlib
pack_stage "$stage" "$tmp/udevlib.pkg.tar"
run_sps "$project_dir/bin/pkin" "$tmp/udevlib.pkg.tar" >/dev/null ||
    fail 'usr-merge /lib should accept package directory lib/'
[ -L "$root/lib" ] || fail 'usr-merge /lib was replaced'
[ "$(readlink "$root/lib")" = usr/lib ] || fail 'usr-merge /lib target changed'
[ -f "$root/usr/lib/udev/rules.d/99-test.rules" ] ||
    fail 'udev rule was not installed through usr-merge /lib'
[ "$(cat "$root/usr/lib/udev/rules.d/99-test.rules")" = 'KERNEL=="test"' ] ||
    fail 'udev rule payload is wrong'
grep -q 'lib/udev/rules.d/99-test.rules	udevlib' "$db/owners" ||
    fail 'udev rule owner was not recorded'
run_sps "$project_dir/bin/pkcheck" --all >/dev/null ||
    fail 'pkcheck should accept usr-merge /lib as a shared directory'
run_sps "$project_dir/bin/pkdel" udevlib >/dev/null ||
    fail 'pkdel should remove files below usr-merge /lib'
[ ! -e "$root/usr/lib/udev/rules.d/99-test.rules" ] ||
    fail 'pkdel left udev rule behind'
[ -L "$root/lib" ] || fail 'pkdel removed usr-merge /lib'

# filesystem compat /var/run -> ../run is a shared directory, like usr-merge.
fresh_root
stage=$tmp/stage-varrun
mkdir -p "$stage/var/run" "$root/run" "$root/var"
ln -s ../run "$root/var/run"
printf '%s\n' pid >"$stage/var/run/daemon.pid"
write_meta "$stage" varrun
pack_stage "$stage" "$tmp/varrun.pkg.tar"
run_sps "$project_dir/bin/pkin" "$tmp/varrun.pkg.tar" >/dev/null ||
    fail 'compat /var/run should accept package files'
[ -L "$root/var/run" ] || fail 'compat /var/run was replaced'
[ -f "$root/run/daemon.pid" ] || fail 'pid file was not installed through /var/run'
run_sps "$project_dir/bin/pkcheck" --all >/dev/null ||
    fail 'pkcheck should accept compat /var/run'
run_sps "$project_dir/bin/pkdel" varrun >/dev/null ||
    fail 'pkdel should remove files below /var/run'
[ ! -e "$root/run/daemon.pid" ] || fail 'pkdel left pid file behind'
[ -L "$root/var/run" ] || fail 'pkdel removed compat /var/run'

# A /lib symlink that is not usr-merge must still be refused.
fresh_root
stage=$tmp/stage-badlib
outside=$tmp/outside-lib
mkdir -p "$stage/lib/udev" "$outside"
ln -s "$outside" "$root/lib"
printf '%s\n' stolen >"$stage/lib/udev/x"
write_meta "$stage" badlib
pack_stage "$stage" "$tmp/badlib.pkg.tar"
expect_status 7 "$project_dir/bin/pkin" "$tmp/badlib.pkg.tar"
[ ! -f "$outside/udev/x" ] || fail 'non usr-merge /lib redirected payload'

# Live images may replace unowned seed files and busybox applets.
fresh_root
mkdir -p "$root/etc/sps" "$root/usr/bin"
printf '%s\n' live >"$root/etc/sps/live"
printf '%s\n' seed >"$root/usr/bin/openssl"
archive=$(make_basic openssl 1.0 usr/bin/openssl)
run_sps "$project_dir/bin/pkin" "$archive" >/dev/null 2>"$tmp/live-openssl.err" ||
    fail 'live unowned openssl should be replaced'
[ "$(cat "$root/usr/bin/openssl")" = 'openssl 1.0 payload' ] ||
    fail 'live openssl seed was not replaced'
grep -q 'replacing unowned live file /usr/bin/openssl' "$tmp/live-openssl.err" ||
    fail 'live replacement diagnostic is missing'
grep -qx 'usr/bin/openssl	openssl' "$db/owners" ||
    fail 'replaced live openssl was not owned'

# Without the live marker, a different unowned file is still a conflict.
fresh_root
archive=$(make_basic occupied 1.0)
mkdir -p "$root/usr/bin"
printf '%s\n' administrator >"$root/usr/bin/occupied"
expect_status 7 "$project_dir/bin/pkin" "$archive"
[ "$(cat "$root/usr/bin/occupied")" = administrator ] ||
    fail 'unowned collision was overwritten without a live marker'

# Busybox-style applet symlink is claimed by the real package on a live image.
fresh_root
mkdir -p "$root/etc/sps" "$root/usr/bin"
printf '%s\n' live >"$root/etc/sps/live"
ln -s busybox "$root/usr/bin/clear"
ln -s busybox "$root/usr/bin/tset"
archive=$(make_basic ncurses 1.0 usr/bin/clear)
run_sps "$project_dir/bin/pkin" "$archive" >/dev/null ||
    fail 'live busybox applet should be replaced'
[ -f "$root/usr/bin/clear" ] && [ ! -L "$root/usr/bin/clear" ] ||
    fail 'live busybox clear was not replaced with a file'
[ "$(cat "$root/usr/bin/clear")" = 'ncurses 1.0 payload' ] ||
    fail 'live clear payload is wrong'

# Unowned preserved etc/ files are kept on a live image; the package still
# takes ownership so openssl-style /etc/ssl can install.
fresh_root
mkdir -p "$root/etc/sps" "$root/etc"
printf '%s\n' live >"$root/etc/sps/live"
printf '%s\n' local >"$root/etc/foo"
archive=$(make_basic conffile 1.0 etc/foo)
run_sps "$project_dir/bin/pkin" "$archive" >/dev/null 2>"$tmp/live-etc.err" ||
    fail 'live unowned preserved etc/foo should install without replacing'
[ "$(cat "$root/etc/foo")" = local ] || fail 'live replace clobbered a preserved file'
[ -f "$root/etc/foo.sps-new" ] || fail 'live preserved install did not write .sps-new'
[ "$(cat "$root/etc/foo.sps-new")" = 'conffile 1.0 payload' ] ||
    fail 'live preserved .sps-new payload is wrong'
grep -qx 'etc/foo	conffile' "$db/owners" ||
    fail 'kept live preserved file was not owned'
grep -q 'keeping unowned live preserved file /etc/foo' "$tmp/live-etc.err" ||
    fail 'live preserved keep diagnostic is missing'

# Without the live marker, a different unowned etc/ file is still a conflict.
fresh_root
mkdir -p "$root/etc"
printf '%s\n' local >"$root/etc/foo"
archive=$(make_basic conffile 1.0 etc/foo)
expect_status 7 "$project_dir/bin/pkin" "$archive"
[ "$(cat "$root/etc/foo")" = local ] || fail 'unowned etc/ file was overwritten'

# A different usr-merge /bin target stays a conflict even on a live image.
fresh_root
mkdir -p "$root/etc/sps" "$root/usr/bin" "$root/usr/sbin" \
    "$tmp/stage-livebin/usr/bin"
printf '%s\n' live >"$root/etc/sps/live"
ln -s usr/bin "$tmp/stage-livebin/bin"
ln -s usr/sbin "$root/bin"
printf '%s\n' tool >"$tmp/stage-livebin/usr/bin/tool"
write_meta "$tmp/stage-livebin" livebin
pack_stage "$tmp/stage-livebin" "$tmp/livebin.pkg.tar"
expect_status 7 "$project_dir/bin/pkin" "$tmp/livebin.pkg.tar"
[ "$(readlink "$root/bin")" = usr/sbin ] || fail 'live replace changed usr-merge /bin'

# Live PID 1 and the shell are not claimed by an unowned replacement.
fresh_root
mkdir -p "$root/etc/sps" "$root/usr/bin"
printf '%s\n' live >"$root/etc/sps/live"
ln -s busybox "$root/usr/bin/sh"
archive=$(make_basic dash 1.0 usr/bin/sh)
expect_status 7 "$project_dir/bin/pkin" "$archive"
[ -L "$root/usr/bin/sh" ] || fail 'live replace claimed /usr/bin/sh'
[ "$(readlink "$root/usr/bin/sh")" = busybox ] || fail 'live /usr/bin/sh target changed'

printf '%s\n' 'test_security: ok'
