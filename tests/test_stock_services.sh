#!/bin/sh
# Every mapped daemon must have stock scripts for all supported inits.

set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
fail() { printf 'test_stock_services: %s\n' "$*" >&2; exit 1; }

map=$project_dir/lib/setup/services
sv=$project_dir/lib/setup/sv
[ -f "$map" ] || fail "missing $map"

count=0
while read -r pkg unit _wanted rc _level; do
	case $pkg in
		''|\#*) continue ;;
	esac
	[ -n "$unit" ] && [ -n "$rc" ] || fail "bad map row for $pkg"
	[ -f "$sv/systemd/$unit" ] || fail "missing systemd stock $unit ($pkg)"
	[ -f "$sv/openrc/$rc" ] || fail "missing openrc stock $rc ($pkg)"
	[ -f "$sv/runit/$rc/run" ] || fail "missing runit stock $rc/run ($pkg)"
	[ -f "$sv/s6/$rc/run" ] || fail "missing s6 stock $rc/run ($pkg)"
	[ -f "$sv/dinit/$rc" ] || fail "missing dinit stock $rc ($pkg)"
	[ -f "$sv/shepherd/$rc.scm" ] || fail "missing shepherd stock $rc.scm ($pkg)"
	count=$((count + 1))
done <"$map"

[ "$count" -ge 20 ] || fail "expected at least 20 mapped services, got $count"
printf '%s\n' "stock service files present for $count map rows"
