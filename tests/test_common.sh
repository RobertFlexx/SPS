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
