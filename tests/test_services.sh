#!/bin/sh
# setup service map: enable systemd, OpenRC, and supervision inits in a fake root.

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

# Stock scripts are copied when the package did not ship this init's file.
root2=$tmp/stock
mkdir -p "$root2/etc/sps"
printf '%s\n' runit >"$root2/etc/sps/init"
enabled=$(setup_service_enable_one "$root2" runit sddm) ||
	fail 'runit enable of sddm from stock scripts failed'
[ -f "$root2/etc/sv/sddm/run" ] || fail 'stock runit sddm/run was not copied'
[ -L "$root2/etc/runit/runsvdir/default/sddm" ] ||
	fail 'runit sddm was not linked into runsvdir/default'

enabled=$(setup_service_enable_one "$root2" s6 dbus) ||
	fail 's6 enable of dbus from stock scripts failed'
[ -f "$root2/etc/s6/sv/dbus/run" ] || fail 'stock s6 dbus/run was not copied'
[ -L "$root2/etc/s6/enabled/dbus" ] || fail 's6 dbus was not linked into enabled'

enabled=$(setup_service_enable_one "$root2" dinit NetworkManager) ||
	fail 'dinit enable of NetworkManager from stock scripts failed'
[ -f "$root2/etc/dinit.d/NetworkManager" ] ||
	fail 'stock dinit NetworkManager was not copied'
[ -L "$root2/etc/dinit.d/boot.d/NetworkManager" ] ||
	fail 'dinit NetworkManager was not linked into boot.d'

enabled=$(setup_service_enable_one "$root2" shepherd sshd) ||
	fail 'shepherd enable of sshd from stock scripts failed'
[ -f "$root2/etc/shepherd.d/sshd.scm" ] ||
	fail 'stock shepherd sshd.scm was not copied'

enabled=$(setup_service_enable_one "$root2" runit postgresql) ||
	fail 'runit enable of postgresql from stock scripts failed'
[ -f "$root2/etc/sv/postgresql/run" ] ||
	fail 'stock runit postgresql/run was not copied'
[ -L "$root2/etc/runit/runsvdir/default/postgresql" ] ||
	fail 'runit postgresql was not linked into runsvdir/default'

enabled=$(setup_service_enable_one "$root2" dinit unbound) ||
	fail 'dinit enable of unbound from stock scripts failed'
[ -f "$root2/etc/dinit.d/unbound" ] ||
	fail 'stock dinit unbound was not copied'

# Do not overwrite a package-shipped run script.
mkdir -p "$root2/etc/sv/sshd"
printf '%s\n' '#!/bin/sh' 'exec /opt/custom/sshd' >"$root2/etc/sv/sshd/run"
chmod 755 "$root2/etc/sv/sshd/run"
setup_service_enable_one "$root2" runit openssh >/dev/null ||
	fail 'runit enable of shipped sshd failed'
grep -q '/opt/custom/sshd' "$root2/etc/sv/sshd/run" ||
	fail 'stock runit script overwrote a package-shipped run file'

if grep -q '^package[[:space:]]*elogind' "$project_dir/lib/setup/sets/power.set"
then
	fail 'power set must not pull elogind (conflicts with systemd)'
fi

printf '%s\n' 'service tests passed'
