#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1

fail()
{
    printf 'test_install: %s\n' "$*" >&2
    exit 1
}

command -v make >/dev/null 2>&1 || {
    printf '%s\n' 'test_install: skipped (make unavailable)'
    exit 0
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-install.XXXXXX") ||
    fail 'cannot create temporary directory'
trap 'rm -rf "$tmp"' 0 HUP INT TERM
image=$tmp/image
root=$tmp/root
mkdir -p "$root/etc/sps"

# Test the public make install targets, including config examples and man5.
make -C "$project_dir" DESTDIR="$image" install install-config >/dev/null ||
    fail 'make install/install-config failed'
for required in \
    "$image/usr/bin/src" \
    "$image/usr/bin/sget" \
    "$image/usr/bin/mkpkg" \
    "$image/usr/bin/pkmark" \
    "$image/usr/lib/sps/common.sh" \
    "$image/usr/share/man/man1/sget.1" \
    "$image/usr/share/man/man1/pkmark.1" \
    "$image/usr/share/man/man5/sps.conf.5" \
    "$image/etc/sps/sps.conf" \
    "$image/etc/sps/repos.conf"
do
    [ -f "$required" ] || fail "installed file is missing: $required"
done
grep -F 'sps-community.git' "$image/etc/sps/repos.conf" >/dev/null ||
    fail 'install-config repos.conf must document opt-in community'
if grep -E '^[[:space:]]*git community ' "$image/etc/sps/repos.conf" >/dev/null
then
    fail 'install-config must not enable community'
fi

cp "$project_dir/examples/sps.conf" "$root/etc/sps/sps.conf"
printf 'repo examples %s 100\n' "$project_dir/examples" >"$root/etc/sps/repos.conf"

SPS_ROOT=$root
SPS_CONFIG=$root/etc/sps/sps.conf
SPS_REPOS_CONFIG=$root/etc/sps/repos.conf
SPS_COMPRESSION=none
PATH=$image/usr/bin:$PATH
export SPS_ROOT SPS_CONFIG SPS_REPOS_CONFIG SPS_COMPRESSION PATH
unset SPS_LIBDIR SPS_DB SPS_CACHE SPS_BUILD SPS_REPO_ROOT

"$image/usr/bin/src" update >/dev/null || fail 'installed src update failed'
plan=$("$image/usr/bin/sget" install --plan hello-sps) ||
    fail 'installed sget plan failed'
case $plan in
    *'  hello-sps'*) ;;
    *) fail 'installed sget plan omitted hello-sps' ;;
esac
"$image/usr/bin/sget" install hello-sps >/dev/null ||
    fail 'installed sget/mkpkg/pkin pipeline failed'
[ "$("$root/usr/bin/hello-sps")" = 'hello from SPS' ] ||
    fail 'installed pipeline produced a broken payload'
"$image/usr/bin/pkcheck" --all >/dev/null ||
    fail 'installed pkcheck rejected a fresh installation'
"$image/usr/bin/pkdel" hello-sps >/dev/null ||
    fail 'installed pkdel failed'
"$image/usr/bin/pkcheck" --database >/dev/null ||
    fail 'database did not validate after installed-layout removal'

printf '%s\n' 'test_install: ok'
