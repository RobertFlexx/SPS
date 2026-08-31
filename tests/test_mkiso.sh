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
