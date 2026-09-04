#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd -- "$test_dir/.." 2>/dev/null && pwd)
. "$project_dir/lib/common.sh"

tmp=${TMPDIR:-/tmp}/sps-common.$$
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/root/etc/sps"

test_root=$tmp/root
config_file=$test_root/etc/sps/sps.conf
repos_file=$test_root/etc/sps/repos.conf
{
	printf '%s\n' 'db /state/db'
	printf '%s\n' 'cache /state/cache'
	printf '%s\n' 'build /state/build'
	printf '%s\n' 'makejobs 3'
	printf '%s\n' 'arch test-arch'
	printf '%s\n' 'preserve etc,usr/local/etc'
	printf '%s\n' "repo local $tmp/repo 90"
} > "$config_file"
printf '%s\n' "repo extra $tmp/extra 10" > "$repos_file"

SPS_ROOT=$test_root
SPS_CONFIG=$config_file
SPS_REPOS_CONFIG=$repos_file
export SPS_ROOT SPS_CONFIG SPS_REPOS_CONFIG
unset SPS_DB SPS_CACHE SPS_BUILD SPS_MAKEJOBS SPS_COMPRESSION
sps_load_config

[ "$SPS_DB" = "$test_root/state/db" ]
[ "$SPS_CACHE" = "$test_root/state/cache" ]
[ "$SPS_BUILD" = "$test_root/state/build" ]
[ "$SPS_REPO_ROOT" = "$test_root/usr/src/sps" ]
[ "$SPS_MAKEJOBS" = 3 ]
[ "$SPS_ARCH" = test-arch ]
[ "$SPS_PRESERVE" = etc,usr/local/etc ]
[ "$(sps_repo_lines | wc -l | awk '{ print $1 }')" = 2 ]
sps_validate_package_name 'libc++'
sps_validate_package_name 'compat..name'
! sps_validate_package_name '../bad'
sps_tab_safe 'ordinary value'
! sps_tab_safe "bad	value"

created=$(sps_mktemp_dir "$tmp" common)
[ -d "$created" ]

printf '%s\n' 'common configuration tests passed'

# Rest-of-line compiler flags, march none, and makejobs auto.
{
	printf '%s\n' 'makejobs auto'
	printf '%s\n' 'cflags -O2 -pipe -fno-lto'
	printf '%s\n' 'cxxflags -O2 -pipe -fno-lto'
	printf '%s\n' 'march none'
} > "$config_file"
unset SPS_MAKEJOBS SPS_CFLAGS SPS_CXXFLAGS SPS_MARCH CFLAGS CXXFLAGS
SPS_ROOT=$test_root
SPS_CONFIG=$config_file
SPS_REPOS_CONFIG=$repos_file
export SPS_ROOT SPS_CONFIG SPS_REPOS_CONFIG
sps_load_config
case $SPS_MAKEJOBS in
	''|*[!0-9]*|0) printf '%s\n' "makejobs auto produced '$SPS_MAKEJOBS'" >&2; exit 1 ;;
esac
[ "$CFLAGS" = '-O2 -pipe -fno-lto' ] || {
	printf '%s\n' "cflags rest-of-line failed: '$CFLAGS'" >&2
	exit 1
}
[ "$CXXFLAGS" = '-O2 -pipe -fno-lto' ] || {
	printf '%s\n' "cxxflags rest-of-line failed: '$CXXFLAGS'" >&2
	exit 1
}
case $CFLAGS in
	*-march=*) printf '%s\n' "march none still added -march: '$CFLAGS'" >&2; exit 1 ;;
esac

printf '%s\n' 'compiler flag configuration tests passed'

mkdir -p "$test_root/usr/bin" "$test_root/usr/lib" "$test_root/run" "$test_root/var"
ln -sf usr/lib "$test_root/lib"
ln -sf usr/bin "$test_root/bin"
ln -s ../run "$test_root/var/run"
sps_is_usr_merge_dir lib
sps_is_usr_merge_dir bin
sps_is_shared_dir_link lib
sps_is_shared_dir_link var/run
! sps_is_usr_merge_dir var/run
! sps_is_usr_merge_dir usr/lib
! sps_is_usr_merge_dir lib64
ln -sf /tmp "$test_root/sbin"
! sps_is_usr_merge_dir sbin
! sps_is_shared_dir_link sbin
rm -f "$test_root/sbin"
printf '%s\n' live >"$test_root/etc/sps/live"
sps_is_live_bootstrap
rm -f "$test_root/etc/sps/live"
! sps_is_live_bootstrap
sps_is_live_critical_path usr/bin/sh
! sps_is_live_critical_path usr/bin/openssl

printf '%s\n' 'usr-merge and live helper tests passed'

sps_print_community_repos_hint >"$tmp/community-hint"
grep -qx '# Community recipes are not enabled by default.' \
	"$tmp/community-hint" || {
	printf '%s\n' 'community hint missing explanation' >&2
	exit 1
}
grep -qx '# git community https://github.com/RobertFlexx/sps-community.git 50' \
	"$tmp/community-hint" || {
	printf '%s\n' 'community hint missing commented git line' >&2
	exit 1
}
if grep -E '^[[:space:]]*git community ' "$tmp/community-hint" >/dev/null
then
	printf '%s\n' 'community hint must not be an active git line' >&2
	exit 1
fi
printf '%s\n' 'community repository hint tests passed'
