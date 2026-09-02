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
[ -L "$layout/bin" ] || fail 'live /bin must be a usr-merge symlink'
[ "$(readlink "$layout/bin")" = usr/bin ] ||
	fail 'live /bin must point at usr/bin'
[ -d "$layout/var/lib/sps/installed/filesystem" ] ||
	fail 'live image must record filesystem as installed'
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
grep -qx 'HOME_URL="https://splux.robertflexx.dev"' "$layout/etc/os-release" ||
	fail 'os-release HOME_URL is not the Splux site'
grep -q mkiso_stamp_distro_branding "$mkiso" ||
	fail 'mkiso must overlay Distro PNG branding from extra'

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
grep -q 'Engine=none' "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must disable KSplash so plasma_waitforname cannot hang'
grep -q LockOnStart "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must disable kscreenlocker LockOnStart'
grep -q 'kwin_wayland --drm' "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must drive kwin_wayland --drm'
[ -x "$layout/etc/sps/live-plasma-session" ] ||
	fail 'live-plasma-session missing from layout'
grep -q LIBSEAT_BACKEND=seatd "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must set LIBSEAT_BACKEND=seatd'
welcome=$layout/usr/share/plasma/plasma-welcome/intro-customization.desktop
[ -f "$welcome" ] || fail 'plasma-welcome intro-customization missing'
grep -qx 'Name=Welcome to the SPS Linux operating system running KDE Plasma' \
	"$welcome" || fail 'plasma-welcome Name must be the SPS Linux sentence'
name_line=$(grep '^Name=' "$welcome")
case $name_line in
	*[Ss]plux*) fail 'plasma-welcome Name must not fall back to os-release Splux' ;;
esac
grep -q plasma-welcome "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include plasma-welcome'
grep -q openssl "$project_dir/lib/mkiso/live-bins" ||
	fail 'live-bins must include openssl for setup password hashes'
grep -q virtio_gpu "$project_dir/lib/mkiso/initrd-init" ||
	fail 'initrd must load virtio_gpu so Plasma has DRM before switch_root'
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
# simpledrm only after a wait; loading it beside virtio_gpu blacks KWin.
live_rc=$layout/etc/sps/live-rc
wait_line=$(grep -n 'sleep 1' "$live_rc" | head -1 | cut -d: -f1)
sdrm_line=$(grep -n 'modprobe simpledrm' "$live_rc" | head -1 | cut -d: -f1)
[ -n "$wait_line" ] && [ -n "$sdrm_line" ] &&
	[ "$wait_line" -lt "$sdrm_line" ] ||
	fail 'live-rc must wait for a DRM node before simpledrm'
grep -q /dev/dri/card0 "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must wait for a DRM node'
grep -q /usr/share/kwin "$project_dir/lib/mkiso/plasma-trees" ||
	fail 'plasma-trees must include /usr/share/kwin'
grep -q /etc/fonts "$project_dir/lib/mkiso/plasma-trees" ||
	fail 'plasma-trees must include fontconfig'
grep -q /usr/share/xkeyboard-config-2 "$project_dir/lib/mkiso/plasma-trees" ||
	fail 'plasma-trees must include the real XKB rules behind /usr/share/X11/xkb'
grep -q /usr/share/libinput "$project_dir/lib/mkiso/plasma-trees" ||
	fail 'plasma-trees must include libinput device quirks'
grep -q kglobalacceld "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include kglobalacceld'
grep -q xdg-desktop-portal-kde "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include xdg-desktop-portal-kde'
grep -q libgallium "$mkiso" ||
	fail 'plasma ISO must copy Mesa libgallium'
grep -q 'video:x:18:root' "$layout/etc/group" ||
	fail 'live group must include video for seatd/DRM'
grep -q 'hosts: files dns' "$layout/etc/nsswitch.conf" ||
	fail 'live nsswitch must use files+dns (not host mdns)'
grep -q 'nameserver 1.1.1.1' "$layout/etc/resolv.conf" ||
	fail 'live resolv.conf must ship a fallback nameserver'
grep -q localhost "$layout/etc/hosts" || fail 'live /etc/hosts missing localhost'
grep -q dhcpcd "$project_dir/lib/mkiso/live-bins" ||
	fail 'live-bins must include dhcpcd so slim images get a DHCP client'
[ -x "$layout/etc/sps/udhcpc-script" ] ||
	fail 'live udhcpc-script missing'
grep -q 'udevd --daemon' "$layout/etc/sps/live-rc" ||
	fail 'live-rc must start udev'
# DHCP must not run before udev; virtio_net has no name yet.
live_rc=$layout/etc/sps/live-rc
udev_line=$(grep -n 'udevd --daemon' "$live_rc" | head -1 | cut -d: -f1)
dhcp_line=$(grep -n 'dhcpcd -b' "$live_rc" | head -1 | cut -d: -f1)
[ -n "$udev_line" ] && [ -n "$dhcp_line" ] &&
	[ "$udev_line" -lt "$dhcp_line" ] ||
	fail 'live-rc must start udev before dhcpcd'
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
grep -q 'copying glibc startfiles' "$mkiso" ||
	fail 'seeded ISO must copy glibc crt1.o for gcc'
grep -q crt1.o "$mkiso" ||
	fail 'mkiso must copy crt1.o with the seed compiler'
grep -q /usr/lib64/libpthread.a "$mkiso" ||
	fail 'seeded ISO must copy the glibc -lpthread compatibility archive'
grep -q 'resolving gcc cc1 libraries' "$mkiso" ||
	fail 'seeded ISO must ldd cc1 so libmpc/libisl land on the disc'
grep -q 'resolving Mesa DRI/GBM libraries' "$mkiso" ||
	fail 'plasma ISO must ldd Mesa DRI/GBM so libSPIRV-Tools lands on the disc'
grep -q libSPIRV-Tools "$mkiso" ||
	fail 'plasma ISO must copy libSPIRV-Tools for Mesa GBM'
grep -q nvidia-drm_gbm "$mkiso" ||
	fail 'plasma ISO must drop the nvidia GBM backend'
grep -q Xwayland "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include Xwayland'
grep -q xkbcomp "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include xkbcomp for Xwayland keyboard setup'
grep -q xdg-document-portal "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include xdg-document-portal'
grep -q /usr/share/color-schemes "$project_dir/lib/mkiso/plasma-trees" ||
	fail 'plasma-trees must include Breeze color schemes'
grep -q '/tmp/.X11-unix' "$layout/etc/sps/live-rc" ||
	fail 'live-rc must create /tmp/.X11-unix for Xwayland'
grep -q '/tmp/.X11-unix' "$layout/etc/sps/live-plasma" ||
	fail 'live-plasma must create /tmp/.X11-unix for Xwayland'
grep -q 'live gcc cannot create executables' "$project_dir/bin/setup" ||
	fail 'setup must probe live gcc before the first package build'
grep -q 'live meson cannot run' "$project_dir/bin/setup" ||
	fail 'setup must probe live meson before the first meson package'
grep -q 'copying disk tools for setup' "$mkiso" ||
	fail 'mkiso must copy partition tools by command name'
grep -q grub-install "$mkiso" ||
	fail 'mkiso must copy grub-install by command name for setup'
grep -q efibootmgr "$mkiso" ||
	fail 'mkiso must copy efibootmgr by command name for EFI NVRAM'
grep -q /usr/sbin/efibootmgr "$project_dir/lib/mkiso/seed-bins" ||
	fail 'seed-bins must list efibootmgr'
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
grep -q 'copying file(1) magic database' "$mkiso" ||
	fail 'seeded ISO must copy file(1) magic for autoconf'
grep -q /usr/bin/msgfmt "$project_dir/lib/mkiso/seed-bins" ||
	fail 'seeded ISO must include msgfmt for alsa-utils translations'
grep -q /usr/bin/xgettext "$project_dir/lib/mkiso/seed-bins" ||
	fail 'seeded ISO must include xgettext with the gettext tools'
grep -q /usr/bin/pod2man "$project_dir/lib/mkiso/seed-bins" ||
	fail 'seeded ISO must include pod2man for OpenSSL and Perl docs'
grep -q 'seeded live gcc is missing pod2man' "$mkiso" ||
	fail 'mkiso must refuse a disc whose host has pod2man but the image does not'
grep -q sps_print_default_conf "$mkiso" ||
	fail 'mkiso must write a default sps.conf with compiler flags'
grep -q mkiso_install_meson "$mkiso" ||
	fail 'seeded ISO must install mesonbuild next to meson.py'
grep -q mkiso_copy_python_stdlib "$mkiso" ||
	fail 'seeded ISO must copy the Python stdlib without host site-packages'
grep -q 'seeded meson is missing mesonbuild' "$mkiso" ||
	fail 'mkiso must refuse a disc whose meson cannot import mesonbuild'
grep -q encodings "$mkiso" ||
	fail 'mkiso must verify the Python encodings module landed'
grep -q mkiso_copy_cmake_data "$mkiso" ||
	fail 'seeded ISO must copy CMake modules'
grep -q mkiso_copy_perl_lib "$mkiso" ||
	fail 'seeded ISO must copy the Perl library for autoconf'
grep -q mkiso_prune_seed_headers "$mkiso" ||
	fail 'mkiso must drop host samplerate.h and libxml2 headers'
grep -q samplerate.h "$mkiso" ||
	fail 'mkiso must prune host samplerate.h from seeded includes'
grep -q '/etc/file' "$mkiso" ||
	fail 'mkiso must copy /etc/file magic used by this host file(1)'
grep -q kactivitymanagerd "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include kactivitymanagerd'
grep -q kscreenlocker_greet "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include kscreenlocker_greet'
grep -q kscreenlockerrc "$mkiso" ||
	fail 'mkiso must bake kscreenlockerrc so live Plasma does not autolock'
grep -q Liberation "$mkiso" ||
	fail 'plasma ISO must copy Liberation fonts matching host fontconfig'
grep -q XDG_CURRENT_DESKTOP "$project_dir/lib/mkiso/live-plasma" ||
	fail 'live-plasma must set XDG_CURRENT_DESKTOP=KDE'
grep -q mkiso_copy_plasma_runtime_deps "$mkiso" ||
	fail 'plasma ISO must ldd session helpers (kactivitymanagerd, greeter)'
grep -q libKirigamiplugin "$mkiso" ||
	fail 'plasma ISO must ldd the Kirigami QML plugin closure'
grep -q libqsqlite "$mkiso" ||
	fail 'plasma ISO must ldd the Qt SQLite driver used by kactivitymanagerd'
grep -q 'qt6/qml/org/kde' "$mkiso" ||
	fail 'plasma ISO must close the Plasma QML plugin dependency graph'
grep -q 'qt6/plugins/plasma' "$mkiso" ||
	fail 'plasma ISO must close the Plasma applet plugin dependency graph'
grep -q 'qt6/plugins/kwin' "$mkiso" ||
	fail 'plasma ISO must close the KWin plugin dependency graph'
grep -q /usr/share/systemsettings "$project_dir/lib/mkiso/plasma-trees" ||
	fail 'plasma-trees must include System Settings categories'
grep -q /usr/bin/firefox "$project_dir/lib/mkiso/plasma-bins" ||
	fail 'plasma-bins must include firefox'
grep -q /usr/lib64/firefox "$project_dir/lib/mkiso/plasma-trees" ||
	fail 'plasma-trees must include the Firefox runtime tree'
grep -q pipewire "$project_dir/lib/mkiso/live-plasma-session" ||
	fail 'live Plasma session must start pipewire'
grep -q polkitd "$project_dir/lib/mkiso/live-rc" ||
	fail 'live-rc must start polkitd'
grep -q polkit-kde-authentication-agent \
	"$project_dir/lib/mkiso/live-plasma-session" ||
	fail 'live Plasma session must start the KDE polkit agent'
grep -q qt6/plugins/kf6 "$mkiso" ||
	fail 'plasma ISO must close KF6 plugin libraries'
grep -q mkiso_install_base_filesystem "$mkiso" ||
	fail 'mkiso must install filesystem so live sget can own /bin'
grep -q 'xkeyboard-config-2/rules/evdev' "$mkiso" ||
	fail 'plasma ISO must verify the XKB evdev rules used by KWin'
grep -q XCURSOR_THEME "$project_dir/lib/mkiso/live-plasma" ||
	fail 'live-plasma must select a cursor theme that exists on the image'
grep -q 'using .* for headers, libraries, and pkg-config' "$project_dir/bin/mkpkg" ||
	fail 'mkpkg must compile against SPS_ROOT so setup can link target libs'
grep -q write_cc_wrapper "$project_dir/bin/mkpkg" ||
	fail 'mkpkg must wrap gcc so autoconf finds libraries in SPS_ROOT'
grep -q SPS_HOST_LD_LIBRARY_PATH "$project_dir/bin/mkpkg" ||
	fail 'mkpkg must keep host gcc from loading SPS_ROOT via LD_LIBRARY_PATH'
grep -q SPS_TARGET_LIBRARY_PATH "$project_dir/bin/mkpkg" ||
	fail 'mkpkg must put SPS_ROOT on LD_LIBRARY_PATH for just-built test programs'
grep -q OPENSSL_MODULES "$project_dir/bin/mkpkg" ||
	fail 'mkpkg must point OpenSSL at SPS_ROOT providers during target builds'
grep -q CONFIG_SITE "$project_dir/bin/mkpkg" ||
	fail 'mkpkg must export CONFIG_SITE so autoconf sees SPS_ROOT LDFLAGS'
grep -q 'sps_say "unpacking' "$project_dir/bin/pkin" ||
	fail 'pkin must log unpacking'
grep -q sps_verbose_say "$project_dir/bin/pkin" ||
	fail 'pkin must have a verbose file-install path'
grep -q mkiso_verify_setup_catalog "$mkiso" ||
	fail 'mkiso must refuse extras/sets that name unpackaged recipes'
if grep -E '^(htop|btop|tmux)[[:space:]]' "$project_dir/lib/setup/extras" |
	awk '{c[$1]++} END { for (n in c) if (c[n] > 1) exit 1 }'
then
	:
else
	fail 'extras must not list htop, btop, or tmux more than once'
fi
if grep -E '^(gimp|libreoffice|qemu)[[:space:]]' \
	"$project_dir/lib/setup/extras"
then
	fail 'extras must not offer unpackaged names such as GIMP or LibreOffice'
fi
