#!/bin/sh
# setup service map: enable systemd units and OpenRC scripts in a fake root.

set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
fail() { printf 'test_services: %s\n' "$*" >&2; exit 1; }

export SPS_LIBDIR=$project_dir/lib
# shellcheck disable=SC1091
. "$project_dir/lib/setup/service.sh"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-services.XXXXXX") || fail mktemp
trap 'rm -rf "$tmp"' 0 HUP INT TERM

map=$(setup_service_map_file) || fail 'service map missing'
[ -f "$map" ] || fail "service map is not a file: $map"

fields=$(setup_service_lookup sddm) || fail 'sddm is not in the service map'
case $fields in
	'sddm.service graphical.target sddm default') ;;
	*) fail "unexpected sddm map fields: $fields" ;;
esac

root=$tmp/root
mkdir -p "$root/usr/lib/systemd/system" "$root/etc/init.d" "$root/etc/sps" \
	"$root/root"
printf '%s\n' systemd >"$root/etc/sps/init"
printf '%s\n' '[Unit]' >"$root/usr/lib/systemd/system/sddm.service"
printf '%s\n' '[Unit]' >"$root/usr/lib/systemd/system/dbus.service"
printf '%s\n' '#!/bin/sh' >"$root/etc/init.d/sddm"
printf '%s\n' '#!/bin/sh' >"$root/etc/init.d/dbus"
chmod 755 "$root/etc/init.d/sddm" "$root/etc/init.d/dbus"

enabled=$(setup_service_enable_one "$root" systemd sddm) ||
	fail 'systemd enable of sddm failed'
[ "$enabled" = sddm ] || fail "enable_one printed '$enabled'"
[ -L "$root/etc/systemd/system/graphical.target.wants/sddm.service" ] ||
	fail 'sddm.service was not linked into graphical.target.wants'
[ -L "$root/etc/systemd/system/default.target" ] ||
	fail 'sddm should set default.target to graphical.target'

enabled=$(setup_service_enable_one "$root" openrc sddm) ||
	fail 'openrc enable of sddm failed'
[ -L "$root/etc/runlevels/default/sddm" ] ||
	fail 'OpenRC sddm was not linked into runlevels/default'

present=$(setup_service_enable_present "$root" systemd) ||
	fail 'enable_present failed'
case $present in
	*sddm*) ;;
	*) fail "enable_present missed sddm: $present" ;;
esac
case $present in
	*dbus*) ;;
	*) fail "enable_present missed dbus: $present" ;;
esac

# Hooks no-op when init is none, and enable when init is recorded.
printf '%s\n' none >"$root/etc/sps/init"
rm -f "$root/etc/runlevels/default/sshd"
export SPS_ROOT=$root SPS_PACKAGE=openssh
setup_service_hook_enable || fail 'hook_enable with init none failed'

printf '%s\n' openrc >"$root/etc/sps/init"
printf '%s\n' '#!/bin/sh' >"$root/etc/init.d/sshd"
chmod 755 "$root/etc/init.d/sshd"
setup_service_hook_enable || fail 'hook_enable with openrc failed'
[ -L "$root/etc/runlevels/default/sshd" ] ||
	fail 'openssh hook did not enable sshd for OpenRC'

if grep -q '^package[[:space:]]*elogind' "$project_dir/lib/setup/sets/power.set"
then
	fail 'power set must not pull elogind (conflicts with systemd)'
fi

printf '%s\n' 'service tests passed'
