#!/bin/sh
# setup extras/sets/profiles must name real, unique, sorted packages.

set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
fail() { printf 'test_setup_catalog: %s\n' "$*" >&2; exit 1; }

setup_dir=$project_dir/lib/setup
extras=$setup_dir/extras
[ -f "$extras" ] || fail 'lib/setup/extras is missing'

# Unique, tab-separated, LC_ALL=C sorted. Duplicate htop/btop rows and
# unpackaged names such as mpv are how the extras checklist lied to setup.
LC_ALL=C awk '
	BEGIN { bad = 0; count = 0 }
	/^[[:space:]]*$/ || /^#/ { next }
	{
		tab = index($0, "\t")
		if (tab == 0) {
			print "extras line has no tab: " $0
			bad = 1
			next
		}
		name = substr($0, 1, tab - 1)
		if (name !~ /^[A-Za-z0-9][A-Za-z0-9+_.-]*$/) {
			print "extras bad name: " name
			bad = 1
		}
		if (name in seen) {
			print "extras duplicate: " name
			bad = 1
		}
		seen[name] = 1
		count++
		names[count] = name
	}
	END {
		for (i = 1; i < count; i++)
			if (names[i] > names[i + 1]) {
				print "extras not sorted: " names[i] " before " names[i + 1]
				bad = 1
			}
		if (count < 2) {
			print "extras is empty"
			bad = 1
		}
		exit bad
	}
' "$extras" || fail 'extras must be unique, tab-separated, and sorted'

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-catalog.XXXXXX") || fail mktemp
trap 'rm -rf "$tmp"' 0 HUP INT TERM

awk -F '\t' '/^[[:space:]]*$/ || /^#/ { next } { print $1 }' "$extras" \
	>"$tmp/wanted"
for f in "$setup_dir"/sets/*.set "$setup_dir"/profiles/*.profile
do
	[ -f "$f" ] || continue
	awk '/^package[[:space:]]/ { print $2 }' "$f" >>"$tmp/wanted"
done
	if [ -f "$setup_dir/hwdetect.sh" ]; then
		awk '
			/printf '\''%s\\n'\'' [a-z]/ && $0 !~ /\$/ && $0 !~ /\|/ {
				for (i = 3; i <= NF; i++) {
					gsub(/;/, "", $i)
					if ($i ~ /^[a-z][a-z0-9+-]*$/)
						print $i
				}
			}
		' "$setup_dir/hwdetect.sh" >>"$tmp/wanted"
	fi
LC_ALL=C sort -u "$tmp/wanted" -o "$tmp/wanted"

# Recipe trees are optional for a tools-only checkout. When they are
# present, every setup name must exist so live setup cannot offer mpv.
catalog_trees=
for d in \
	${SPS_CORE:-} ${SPS_EXTRA:-} \
	${ISO_CORE:-} ${ISO_EXTRA:-} \
	/tmp/sps-core /tmp/sps-extra \
	/usr/src/sps/core /usr/src/sps/extra
do
	[ -n "$d" ] || continue
	[ -d "$d" ] || continue
	case " $catalog_trees " in *" $d "*) continue ;; esac
	catalog_trees="$catalog_trees $d"
done

if [ -z "$catalog_trees" ]; then
	printf '%s\n' \
		'test_setup_catalog: no recipe trees; skipped existence check'
	printf '%s\n' 'test_setup_catalog: ok'
	exit 0
fi

: >"$tmp/recipes"
for tree in $catalog_trees
do
	find "$tree" \( -type d \( -name .git -o -name files -o \
		-name patches -o -name hooks \) -prune \) -o \
		-type f -name recipe -print
done | while IFS= read -r recipe || [ -n "$recipe" ]
do
	[ -n "$recipe" ] || continue
	awk '/^name[[:space:]]/ { print $2; exit }' "$recipe"
done | LC_ALL=C sort -u >"$tmp/recipes"
[ -s "$tmp/recipes" ] || fail 'recipe trees contained no name records'

miss=
while IFS= read -r pkg || [ -n "$pkg" ]
do
	[ -n "$pkg" ] || continue
	grep -qx "$pkg" "$tmp/recipes" && continue
	miss="$miss $pkg"
done <"$tmp/wanted"
[ -z "$miss" ] || fail "setup names packages with no recipe:$miss"

printf '%s\n' 'test_setup_catalog: ok'
