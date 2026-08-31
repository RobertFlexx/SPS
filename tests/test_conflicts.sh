#!/bin/sh
# sget refuses systemd/OpenRC-style recipe conflicts.

set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
fail() { printf 'test_conflicts: %s\n' "$*" >&2; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-conflicts.XXXXXX") || fail mktemp
trap 'rm -rf "$tmp"' 0 HUP INT TERM

mkdir -p "$tmp/root" "$tmp/cache" "$tmp/db" "$tmp/build" \
	"$tmp/repo/alpha" "$tmp/repo/beta" "$tmp/repo/ok"
: >"$tmp/sps.conf"
printf 'dir test %s 10\n' "$tmp/repo" >"$tmp/repos.conf"

write_recipe()
{
	dir=$1
	name=$2
	shift 2
	{
		printf 'name %s\n' "$name"
		printf '%s\n' 'version 1.0' 'release 1' "description $name"
		for rec
		do
			printf '%s\n' "$rec"
		done
		printf '%s\n' 'install mkdir -p "$PKG/usr/share/sps-test"'
		printf 'install printf %%s\\n %s >"$PKG/usr/share/sps-test/%s"\n' \
			"$name" "$name"
	} >"$dir/recipe"
}

write_recipe "$tmp/repo/alpha" alpha 'conflict beta'
write_recipe "$tmp/repo/beta" beta 'conflict alpha'
write_recipe "$tmp/repo/ok" ok

SPS_ROOT=$tmp/root
SPS_DB=$tmp/db
SPS_CACHE=$tmp/cache
SPS_BUILD=$tmp/build
SPS_CONFIG=$tmp/sps.conf
SPS_REPOS_CONFIG=$tmp/repos.conf
export SPS_ROOT SPS_DB SPS_CACHE SPS_BUILD SPS_CONFIG SPS_REPOS_CONFIG
export SPS_LIBDIR=$project_dir/lib
export PATH=$project_dir/bin:$PATH

src update >/dev/null

show=$(src show alpha)
case $show in
	*'conflicts: beta'*) ;;
	*) fail "src show did not list conflict: $show" ;;
esac

set +e
sget install --plan alpha beta >/dev/null 2>"$tmp/err"
st=$?
set -e
[ "$st" -ne 0 ] || fail 'sget install --plan alpha beta should fail'
grep -q conflict "$tmp/err" || fail "error did not mention conflict: $(cat "$tmp/err")"

sget install --plan alpha ok >/dev/null || fail 'alpha+ok should resolve'
sget install --plan ok >/dev/null || fail 'ok should resolve'
