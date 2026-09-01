#!/bin/sh
# mkiso --help and --layout

set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
fail() { printf 'test_mkiso: %s\n' "$*" >&2; exit 1; }

mkiso=$project_dir/bin/mkiso
export SPS_LIBDIR=$project_dir/lib
export PATH=$project_dir/bin:$PATH

help=$("$mkiso" --help)
case $help in
	*'--output'*) ;;
	*) fail 'help missing --output' ;;
esac
case $help in
	*'--with-firmware'*) ;;
	*) fail 'help missing --with-firmware' ;;
esac
case $help in
	*'--init'*) ;;
	*) fail 'help missing --init' ;;
esac
case $help in
	*'--session'*) ;;
	*) fail 'help missing --session' ;;
esac

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-mkiso.XXXXXX") || fail mktemp
trap 'rm -rf "$tmp"' 0 HUP INT TERM

layout=$tmp/live
bb=
if [ -x /tmp/sps-wave/busybox.static ]; then
	bb=/tmp/sps-wave/busybox.static
fi

if [ -n "$bb" ]; then
	"$mkiso" --layout "$layout" --no-seed --no-modules --busybox "$bb" \
		>/dev/null
else
	"$mkiso" --layout "$layout" --no-seed --no-modules >/dev/null
fi

[ -f "$layout/etc/sps/live" ] || fail 'live marker missing'
[ -f "$layout/etc/motd" ] || fail 'motd missing'
[ -x "$layout/sbin/init" ] || fail 'live init missing'
[ -x "$layout/etc/sps/live-rc" ] || fail 'live-rc missing'
[ -f "$layout/etc/inittab" ] || fail 'inittab missing'
[ "$(cat "$layout/etc/sps/init")" = systemd ] || fail 'live default init is not systemd'
[ -x "$layout/usr/bin/setup" ] || fail 'setup not installed into layout'
grep -q 'setup' "$layout/etc/motd" || fail 'motd does not mention setup'
# PID 1 must not be the old script that execs a console (exit 127 panic).
if [ -f "$layout/sbin/init" ]; then
	init_head=$(head -c 2 "$layout/sbin/init" 2>/dev/null || :)
	if [ "$init_head" = '#!' ] && grep -q 'exec setsid' "$layout/sbin/init"
	then
		fail 'PID 1 still execs a console as init'
	fi
fi
[ -f "$layout/etc/sps/repos.conf" ] || fail 'repos.conf missing'
if [ -x "$layout/bin/busybox" ] && [ -L "$layout/bin/mkdir" ]; then
	target=$(readlink "$layout/bin/mkdir")
	case $target in
		busybox|./busybox) ;;
		*) fail "busybox applet mkdir should be a relative link, got $target" ;;
	esac
fi

[ -f "$layout/etc/os-release" ] || fail 'os-release missing'
grep -qx 'ID=splux' "$layout/etc/os-release" || fail 'os-release is not Splux'
grep -qx 'NAME="Splux"' "$layout/etc/os-release" || fail 'os-release NAME is not Splux'

# Host /bin/sh is bash. Getty runs /bin/sh. A bash symlink without libtinfo
# is the Plasma ISO boot loop.
if [ -L "$layout/bin/sh" ]; then
	sh_target=$(readlink "$layout/bin/sh")
	case $sh_target in
		busybox|./busybox|/bin/busybox) ;;
		*) fail "live /bin/sh must be busybox, got $sh_target" ;;
	esac
else
	fail 'live /bin/sh is not a symlink to busybox'
fi
if grep -q 'ln -sf bash .*/bin/sh' "$mkiso"; then
	fail 'mkiso must not point /bin/sh at bash'
fi
grep -q dbus-run-session "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must start Plasma under a session bus'
grep -q C.UTF-8 "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must set a UTF-8 locale'
grep -q kdedefaults "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must seed kdedefaults for KSplash'
if grep -q 'export QT_QPA_PLATFORM=wayland' "$layout/etc/sps/live-plasma"
then
	fail 'live-plasma must not force QT_QPA_PLATFORM=wayland on KWin'
fi
grep -q FONTCONFIG_PATH "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must set FONTCONFIG_PATH'
grep -q virtio_gpu "$layout/etc/sps/live-rc" ||
	fail 'live-rc must load virtio_gpu for QEMU/virt-manager'
grep -q cirrus_qemu "$layout/etc/sps/live-rc" ||
	fail 'live-rc must load cirrus_qemu for QEMU stdvga fallbacks'
grep -q /dev/dri/card0 "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must wait for a DRM node'
grep -q /usr/share/kwin "$project_dir/lib/mkiso/plasma-trees" ||
	fail 'plasma-trees must include /usr/share/kwin'
grep -q /etc/fonts "$project_dir/lib/mkiso/plasma-trees" ||
	fail 'plasma-trees must include fontconfig'
grep -q kglobalacceld "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include kglobalacceld'
grep -q xdg-desktop-portal-kde "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include xdg-desktop-portal-kde'
grep -q libgallium "$mkiso" ||
	fail 'plasma ISO must copy Mesa libgallium'
grep -q 'video:x:18:root' "$layout/etc/group" ||
	fail 'live group must include video for seatd/DRM'
grep -q kwin_wayland_wrapper "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include kwin_wayland_wrapper'
grep -q xdg-permission-store "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include xdg-permission-store'
grep -q libxcb-cursor "$mkiso" ||
	fail 'plasma ISO must copy libxcb-cursor for the xcb QPA plugin'
grep -q plasma_waitforname "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'org.kde.KSplash.service Exec is plasma_waitforname'
grep -q -- '-comp zstd' "$mkiso" || fail 'mkiso must write a zstd squashfs'
grep -q -- '-Xcompression-level 3' "$mkiso" ||
	fail 'mkiso squashfs compression should stay fast to build'
grep -q 'Qt/KF shared libraries' "$mkiso" ||
	fail 'plasma ISO must copy Qt/KF libraries without per-file ldd'
grep -q 'found live image' "$project_dir/lib/mkiso/initrd-init" ||
	fail 'initrd must say when the ISO is found'
grep -q 'mounting live filesystem' "$project_dir/lib/mkiso/initrd-init" ||
	fail 'initrd must print before squashfs mount'
if [ -x /usr/bin/dialog ]; then
	[ -e "$layout/usr/bin/dialog" ] || fail 'dialog missing from slim layout'
fi
if command -v lsblk >/dev/null 2>&1; then
	if [ ! -e "$layout/bin/lsblk" ] && [ ! -e "$layout/usr/bin/lsblk" ] &&
	   [ ! -e "$layout/sbin/lsblk" ] && [ ! -e "$layout/usr/sbin/lsblk" ]
	then
		fail 'lsblk missing from live layout (setup disk menu needs it)'
	fi
fi
grep -q 'copying disk tools for setup' "$mkiso" ||
	fail 'mkiso must copy partition tools by command name'
grep -q grub-install "$mkiso" ||
	fail 'mkiso must copy grub-install by command name for setup'
grep -q 'system-local.conf' "$mkiso" ||
	fail 'mkiso must bake a live D-Bus system-local.conf'
grep -q '<user>root</user>' "$project_dir/lib/mkiso/live-plasma" ||
	fail 'live-plasma must run the system bus as root'
if grep -q 'if \[ ! -f /etc/dbus-1/system-local.conf \]' \
	"$project_dir/lib/mkiso/live-plasma"
then
	fail 'live-plasma must overwrite host system-local.conf, not skip it'
fi
grep -q 'dbus-daemon --system --nofork --nopidfile --nosyslog' \
	"$project_dir/lib/mkiso/live-rc" ||
	fail 'live-rc must start a system bus before Plasma'
grep -q dbus-send "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include dbus-send'
grep -q dbus-daemon-launch-helper "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include dbus-daemon-launch-helper'
if [ -e "$layout/lib64/libtinfo.so.6" ] || [ -e "$layout/usr/lib64/libtinfo.so.6" ]
then
	for tinfo in "$layout/lib64/libtinfo.so.6" "$layout/usr/lib64/libtinfo.so.6"
	do
		[ -e "$tinfo" ] || continue
		if [ -L "$tinfo" ]; then
			tinfo_real=$(readlink -f "$tinfo")
			[ -f "$tinfo_real" ] || fail "libtinfo.so.6 is a dangling symlink"
			case $tinfo_real in
				"$layout"/*) ;;
				*) fail "libtinfo real file is outside the live root" ;;
			esac
		fi
	done
fi
