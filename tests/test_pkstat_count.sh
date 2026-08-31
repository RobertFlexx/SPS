#!/bin/sh
# pkstat --count: integer of installed records with a regular meta file.

set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1

fail()
{
	printf 'test_pkstat_count: %s\n' "$*" >&2
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

install_named()
{
	package_name=$1
	stage=$tmp/stage-$package_name
	rm -rf "$stage"
	mkdir -p "$stage/.SPS" "$stage/usr/share/$package_name"
	printf '%s\n' "$package_name" >"$stage/usr/share/$package_name/id"
	{
		printf 'format\t1\n'
		printf 'name\t%s\n' "$package_name"
		printf 'version\t1.0\n'
		printf 'release\t1\n'
		printf 'arch\tany\n'
		printf 'description\tcount fixture %s\n' "$package_name"
	} >"$stage/.SPS/meta"
	: >"$stage/.SPS/files.unsorted"
	(CDPATH= cd "$stage" && find . ! -name . ! -path './.SPS' ! -path './.SPS/*' -print) |
		sed 's#^\./##' | while IFS= read -r package_entry; do
			if [ -d "$stage/$package_entry" ] && [ ! -L "$stage/$package_entry" ]; then
				printf '%s/\n' "$package_entry"
			else
				printf '%s\n' "$package_entry"
			fi
		done >"$stage/.SPS/files.unsorted"
	LC_ALL=C sort "$stage/.SPS/files.unsorted" >"$stage/.SPS/files"
	rm -f "$stage/.SPS/files.unsorted"
	: >"$stage/.SPS/hashes"
	printf 'sha256\t%s\t%s\n' \
		"$(sha256sum "$stage/usr/share/$package_name/id" | awk '{ print $1 }')" \
		"usr/share/$package_name/id" >>"$stage/.SPS/hashes"
	tar -C "$stage" -cf "$tmp/$package_name.pkg.tar" .
	run_sps "$project_dir/bin/pkin" --dependency "$tmp/$package_name.pkg.tar" \
		>/dev/null
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-pkstat-count.XXXXXX") || fail mktemp
trap 'rm -rf "$tmp"' 0 HUP INT TERM
root=$tmp/root
db=$tmp/db
cache=$tmp/cache
build=$tmp/build
mkdir -p "$root" "$cache" "$build"

[ "$(run_sps "$project_dir/bin/pkstat" --count)" = 0 ] ||
	fail 'empty database must print 0'

install_named one
[ "$(run_sps "$project_dir/bin/pkstat" --count)" = 1 ] ||
	fail 'one installed package must print 1'

install_named two
install_named three
[ "$(run_sps "$project_dir/bin/pkstat" --count)" = 3 ] ||
	fail 'three installed packages must print 3'

# Junk next to real records is not a package.
printf 'not a record\n' >"$db/installed/readme.txt"
mkdir -p "$db/installed/empty-dir"
ln -s one "$db/installed/alias"
ln -s /tmp "$db/installed/outside"
[ "$(run_sps "$project_dir/bin/pkstat" --count)" = 3 ] ||
	fail 'files, empty dirs, and symlinks must not count'

run_sps "$project_dir/bin/pkstat" --count >/dev/null
run_sps "$project_dir/bin/pkstat" --count | grep -qx '3' ||
	fail 'count must be a single integer line'

printf '%s\n' 'test_pkstat_count: ok'
