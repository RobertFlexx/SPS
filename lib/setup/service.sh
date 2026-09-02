# Init-aware service enablement for the SPS Linux installer.
#
# Sourced, not executed. setup(1) and pkin(1) call these helpers. They
# never invent an init; they read /etc/sps/init (or the hook environment)
# and enable units/scripts for that init. When a package did not ship a
# file for the chosen init, a stock script from $SPS_LIBDIR/setup/sv is
# copied into the target and then enabled. Enablement is on-boot; start
# happens only when the target is the running system and PID 1 matches.

setup_service_known_inits()
{
	printf '%s\n' systemd openrc s6 runit dinit shepherd sysvinit
}

setup_service_is_known_init()
{
	case $1 in
		systemd|openrc|s6|runit|dinit|shepherd|sysvinit) return 0 ;;
	esac
	return 1
}

setup_service_map_file()
{
	if [ -n "${setup_dir-}" ] && [ -f "$setup_dir/services" ]; then
		printf '%s\n' "$setup_dir/services"
		return 0
	fi
	if [ -n "${SPS_LIBDIR-}" ] && [ -f "$SPS_LIBDIR/setup/services" ]; then
		printf '%s\n' "$SPS_LIBDIR/setup/services"
		return 0
	fi
	return 1
}

setup_service_stock_dir()
{
	setup_svc_init=$1
	[ -n "$setup_svc_init" ] || return 1
	if [ -n "${setup_dir-}" ] && [ -d "$setup_dir/sv/$setup_svc_init" ]; then
		printf '%s\n' "$setup_dir/sv/$setup_svc_init"
		return 0
	fi
	if [ -n "${SPS_LIBDIR-}" ] &&
	   [ -d "$SPS_LIBDIR/setup/sv/$setup_svc_init" ]
	then
		printf '%s\n' "$SPS_LIBDIR/setup/sv/$setup_svc_init"
		return 0
	fi
	return 1
}

setup_service_lookup()
{
	# $1 = package name. Prints: unit wanted_by rc_name rc_level
	setup_svc_pkg=$1
	setup_svc_map=$(setup_service_map_file) || return 1
	awk -v pkg="$setup_svc_pkg" '
		BEGIN { found = 0 }
		$1 == "#" || $1 == "" { next }
		$1 == pkg {
			unit = $2
			wanted = $3
			rc = $4
			level = $5
			if (unit == "-" || unit == ".") unit = ""
			if (wanted == "-" || wanted == ".") wanted = ""
			if (rc == "-" || rc == ".") rc = ""
			if (level == "-" || level == ".") level = "default"
			print unit, wanted, rc, level
			found = 1
			exit
		}
		END { exit !found }
	' "$setup_svc_map"
}

setup_service_root()
{
	setup_svc_root=${1:-${SPS_ROOT:-/}}
	[ -n "$setup_svc_root" ] || setup_svc_root=/
	[ "$setup_svc_root" = / ] && return 0
	printf '%s\n' "${setup_svc_root%/}"
}

setup_service_abs()
{
	# $1 root  $2 absolute path in the target
	setup_svc_root=$(setup_service_root "$1")
	setup_svc_rel=$2
	if [ -z "$setup_svc_root" ]; then
		printf '%s\n' "$setup_svc_rel"
	else
		printf '%s%s\n' "$setup_svc_root" "$setup_svc_rel"
	fi
}

setup_service_set_init()
{
	# Init name from a landed init-* metapackage in the target.
	setup_svc_root=$(setup_service_root "$1")
	if [ -z "$setup_svc_root" ]; then
		setup_svc_setdir=/usr/share/sps/sets
	else
		setup_svc_setdir=$setup_svc_root/usr/share/sps/sets
	fi
	[ -d "$setup_svc_setdir" ] || return 1
	setup_svc_found=
	setup_svc_n=0
	for setup_svc_name in systemd openrc s6 runit dinit shepherd sysvinit
	do
		[ -f "$setup_svc_setdir/init-$setup_svc_name" ] || continue
		setup_svc_n=$((setup_svc_n + 1))
		setup_svc_found=$setup_svc_name
	done
	[ "$setup_svc_n" -eq 1 ] || return 1
	printf '%s\n' "$setup_svc_found"
}

setup_service_init_from_sbin()
{
	# Target /sbin/init only. Busybox live PID 1 is not a choice.
	setup_svc_initbin=$(setup_service_abs "$1" /sbin/init)
	[ -e "$setup_svc_initbin" ] || return 1
	setup_svc_real=$(readlink -f "$setup_svc_initbin" 2>/dev/null) ||
		setup_svc_real=$setup_svc_initbin
	case $setup_svc_real in
		*systemd*) printf '%s\n' systemd; return 0 ;;
		*openrc*) printf '%s\n' openrc; return 0 ;;
		*runit*) printf '%s\n' runit; return 0 ;;
		*s6*) printf '%s\n' s6; return 0 ;;
		*dinit*) printf '%s\n' dinit; return 0 ;;
		*shepherd*) printf '%s\n' shepherd; return 0 ;;
		*busybox*) return 1 ;;
	esac
	printf '%s\n' sysvinit
	return 0
}

setup_service_init_of()
{
	# Target init. Never use host PID 1 when SPS_ROOT is a disk.
	setup_svc_pkg_init=$(setup_service_set_init "$1") || setup_svc_pkg_init=
	if [ -n "$setup_svc_pkg_init" ]; then
		printf '%s\n' "$setup_svc_pkg_init"
		return 0
	fi
	setup_svc_initf=$(setup_service_abs "$1" /etc/sps/init)
	setup_svc_file_init=
	if [ -f "$setup_svc_initf" ]; then
		setup_svc_file_init=$(sed -n '1p' "$setup_svc_initf")
	fi
	if setup_service_is_known_init "$setup_svc_file_init"; then
		printf '%s\n' "$setup_svc_file_init"
		return 0
	fi
	setup_svc_bin_init=$(setup_service_init_from_sbin "$1") ||
		setup_svc_bin_init=
	if [ -n "$setup_svc_bin_init" ]; then
		printf '%s\n' "$setup_svc_bin_init"
		return 0
	fi
	printf '%s\n' none
}

setup_service_unit_path()
{
	setup_svc_root=$(setup_service_root "$1")
	setup_svc_unit=$2
	[ -n "$setup_svc_unit" ] || return 1
	for setup_svc_p in \
		"$setup_svc_root/usr/lib/systemd/system/$setup_svc_unit" \
		"$setup_svc_root/lib/systemd/system/$setup_svc_unit" \
		"$setup_svc_root/etc/systemd/system/$setup_svc_unit"
	do
		[ -f "$setup_svc_p" ] || continue
		printf '%s\n' "$setup_svc_p"
		return 0
	done
	return 1
}

setup_service_rc_path()
{
	setup_svc_root=$(setup_service_root "$1")
	setup_svc_rc=$2
	[ -n "$setup_svc_rc" ] || return 1
	if [ -z "$setup_svc_root" ]; then
		setup_svc_p=/etc/init.d/$setup_svc_rc
	else
		setup_svc_p=$setup_svc_root/etc/init.d/$setup_svc_rc
	fi
	[ -f "$setup_svc_p" ] || [ -x "$setup_svc_p" ] || return 1
	printf '%s\n' "$setup_svc_p"
}

setup_service_copy_file()
{
	# $1 dest  $2 mode  $3 src. No-op if dest already exists.
	setup_svc_dest=$1
	setup_svc_mode=$2
	setup_svc_src=$3
	[ -f "$setup_svc_src" ] || return 1
	[ -e "$setup_svc_dest" ] && return 0
	mkdir -p "${setup_svc_dest%/*}" || return 1
	cp "$setup_svc_src" "$setup_svc_dest" || return 1
	chmod "$setup_svc_mode" "$setup_svc_dest"
}

setup_service_copy_supervised()
{
	# $1 srcdir  $2 dstdir. Copy run/finish if dest has no run yet.
	setup_svc_src=$1
	setup_svc_dst=$2
	[ -d "$setup_svc_src" ] || return 1
	[ -f "$setup_svc_src/run" ] || return 1
	if [ -f "$setup_svc_dst/run" ]; then
		return 0
	fi
	mkdir -p "$setup_svc_dst" || return 1
	for setup_svc_f in "$setup_svc_src"/*; do
		[ -f "$setup_svc_f" ] || continue
		setup_svc_b=${setup_svc_f##*/}
		cp "$setup_svc_f" "$setup_svc_dst/$setup_svc_b" || return 1
		case $setup_svc_b in
			run|finish) chmod 755 "$setup_svc_dst/$setup_svc_b" ;;
		esac
	done
	return 0
}

setup_service_ensure_scripts()
{
	# $1 root  $2 init  $3 unit  $4 rc_name
	# Install stock scripts when the package did not ship this init's file.
	setup_svc_root=$1
	setup_svc_init=$2
	setup_svc_unit=$3
	setup_svc_rc=$4
	setup_svc_name=$setup_svc_rc
	if [ -z "$setup_svc_name" ]; then
		setup_svc_name=${setup_svc_unit%.service}
	fi
	[ -n "$setup_svc_name" ] || return 0
	setup_svc_stock=$(setup_service_stock_dir "$setup_svc_init") ||
		return 0
	case $setup_svc_init in
		systemd)
			[ -n "$setup_svc_unit" ] || return 0
			setup_service_copy_file \
				"$(setup_service_abs "$setup_svc_root" \
					"/usr/lib/systemd/system/$setup_svc_unit")" \
				644 "$setup_svc_stock/$setup_svc_unit" || :
			;;
		openrc)
			setup_service_copy_file \
				"$(setup_service_abs "$setup_svc_root" \
					"/etc/init.d/$setup_svc_name")" \
				755 "$setup_svc_stock/$setup_svc_name" || :
			;;
		runit)
			setup_service_copy_supervised \
				"$setup_svc_stock/$setup_svc_name" \
				"$(setup_service_abs "$setup_svc_root" \
					"/etc/sv/$setup_svc_name")" || :
			;;
		s6)
			setup_service_copy_supervised \
				"$setup_svc_stock/$setup_svc_name" \
				"$(setup_service_abs "$setup_svc_root" \
					"/etc/s6/sv/$setup_svc_name")" || :
			;;
		dinit)
			setup_service_copy_file \
				"$(setup_service_abs "$setup_svc_root" \
					"/etc/dinit.d/$setup_svc_name")" \
				644 "$setup_svc_stock/$setup_svc_name" || :
			;;
		shepherd)
			setup_service_copy_file \
				"$(setup_service_abs "$setup_svc_root" \
					"/etc/shepherd.d/$setup_svc_name.scm")" \
				644 "$setup_svc_stock/$setup_svc_name.scm" || :
			;;
		sysvinit)
			setup_service_copy_file \
				"$(setup_service_abs "$setup_svc_root" \
					"/etc/rc.d/init.d/$setup_svc_name")" \
				755 "$setup_svc_stock/$setup_svc_name" || :
			;;
	esac
	return 0
}

setup_service_enable_systemd()
{
	setup_svc_root=$(setup_service_root "$1")
	setup_svc_unit=$2
	setup_svc_wanted=${3:-multi-user.target}
	setup_svc_path=$(setup_service_unit_path "$1" "$setup_svc_unit") ||
		return 1
	setup_svc_wdir=
	if [ -z "$setup_svc_root" ]; then
		setup_svc_wdir=/etc/systemd/system/${setup_svc_wanted}.wants
		setup_svc_link=/usr/lib/systemd/system/$setup_svc_unit
		[ -f "$setup_svc_path" ] &&
			case $setup_svc_path in
				/etc/*) setup_svc_link=$setup_svc_path ;;
				/lib/*) setup_svc_link=$setup_svc_path ;;
				/usr/*) setup_svc_link=$setup_svc_path ;;
			esac
	else
		setup_svc_wdir=$setup_svc_root/etc/systemd/system/${setup_svc_wanted}.wants
		case $setup_svc_path in
			"$setup_svc_root"/*)
				setup_svc_link=${setup_svc_path#"$setup_svc_root"}
				;;
			*)
				setup_svc_link=/usr/lib/systemd/system/$setup_svc_unit
				;;
		esac
	fi
	mkdir -p "$setup_svc_wdir" || return 1
	ln -sf "$setup_svc_link" "$setup_svc_wdir/$setup_svc_unit" || return 1
	if [ "$setup_svc_wanted" = graphical.target ]; then
		if [ -z "$setup_svc_root" ]; then
			setup_svc_def=/etc/systemd/system/default.target
		else
			setup_svc_def=$setup_svc_root/etc/systemd/system/default.target
		fi
		if [ ! -e "$setup_svc_def" ]; then
			ln -sf /usr/lib/systemd/system/graphical.target \
				"$setup_svc_def" || :
		fi
	fi
	return 0
}

setup_service_enable_openrc()
{
	setup_svc_root=$(setup_service_root "$1")
	setup_svc_rc=$2
	setup_svc_level=${3:-default}
	setup_service_rc_path "$1" "$setup_svc_rc" >/dev/null || return 1
	if [ -z "$setup_svc_root" ]; then
		setup_svc_rdir=/etc/runlevels/$setup_svc_level
	else
		setup_svc_rdir=$setup_svc_root/etc/runlevels/$setup_svc_level
	fi
	mkdir -p "$setup_svc_rdir" || return 1
	ln -sf "/etc/init.d/$setup_svc_rc" "$setup_svc_rdir/$setup_svc_rc"
}

setup_service_enable_runit()
{
	setup_svc_root=$(setup_service_root "$1")
	setup_svc_rc=$2
	[ -n "$setup_svc_rc" ] || return 1
	setup_svc_sv=$(setup_service_abs "$1" "/etc/sv/$setup_svc_rc")
	[ -f "$setup_svc_sv/run" ] || return 1
	setup_svc_dir=$(setup_service_abs "$1" /etc/runit/runsvdir/default)
	mkdir -p "$setup_svc_dir" || return 1
	ln -sf "/etc/sv/$setup_svc_rc" "$setup_svc_dir/$setup_svc_rc"
}

setup_service_enable_s6()
{
	setup_svc_root=$(setup_service_root "$1")
	setup_svc_rc=$2
	[ -n "$setup_svc_rc" ] || return 1
	setup_svc_sv=$(setup_service_abs "$1" "/etc/s6/sv/$setup_svc_rc")
	[ -f "$setup_svc_sv/run" ] || return 1
	setup_svc_en=$(setup_service_abs "$1" /etc/s6/enabled)
	mkdir -p "$setup_svc_en" || return 1
	ln -sf "/etc/s6/sv/$setup_svc_rc" "$setup_svc_en/$setup_svc_rc"
}

setup_service_enable_dinit()
{
	setup_svc_root=$(setup_service_root "$1")
	setup_svc_rc=$2
	[ -n "$setup_svc_rc" ] || return 1
	setup_svc_file=$(setup_service_abs "$1" "/etc/dinit.d/$setup_svc_rc")
	[ -f "$setup_svc_file" ] || return 1
	setup_svc_boot=$(setup_service_abs "$1" /etc/dinit.d/boot.d)
	mkdir -p "$setup_svc_boot" || return 1
	ln -sf "../$setup_svc_rc" "$setup_svc_boot/$setup_svc_rc"
}

setup_service_enable_shepherd()
{
	setup_svc_root=$(setup_service_root "$1")
	setup_svc_rc=$2
	[ -n "$setup_svc_rc" ] || return 1
	setup_svc_file=$(setup_service_abs "$1" \
		"/etc/shepherd.d/$setup_svc_rc.scm")
	[ -f "$setup_svc_file" ] || return 1
	return 0
}

setup_service_enable_sysvinit()
{
	setup_svc_rc=$2
	setup_svc_level=${3:-default}
	[ -n "$setup_svc_rc" ] || return 1
	setup_svc_script=$(setup_service_abs "$1" \
		"/etc/rc.d/init.d/$setup_svc_rc")
	setup_svc_rel=/etc/rc.d/init.d/$setup_svc_rc
	if [ ! -f "$setup_svc_script" ]; then
		setup_svc_script=$(setup_service_abs "$1" \
			"/etc/init.d/$setup_svc_rc")
		setup_svc_rel=/etc/init.d/$setup_svc_rc
	fi
	[ -f "$setup_svc_script" ] || return 1
	setup_svc_prio=50
	if [ "$setup_svc_rc" = sddm ]; then
		setup_svc_prio=80
	fi
	if [ "$setup_svc_level" = sysinit ]; then
		setup_svc_d=$(setup_service_abs "$1" /etc/rc.d/rcS.d)
		mkdir -p "$setup_svc_d" || return 1
		ln -sf "$setup_svc_rel" "$setup_svc_d/S20$setup_svc_rc"
		return 0
	fi
	for setup_svc_rl in 2 3 4 5; do
		setup_svc_d=$(setup_service_abs "$1" /etc/rc.d/rc${setup_svc_rl}.d)
		mkdir -p "$setup_svc_d" || return 1
		ln -sf "$setup_svc_rel" \
			"$setup_svc_d/S${setup_svc_prio}$setup_svc_rc"
	done
	for setup_svc_rl in 0 1 6; do
		setup_svc_d=$(setup_service_abs "$1" /etc/rc.d/rc${setup_svc_rl}.d)
		mkdir -p "$setup_svc_d" || return 1
		ln -sf "$setup_svc_rel" \
			"$setup_svc_d/K${setup_svc_prio}$setup_svc_rc"
	done
	return 0
}

setup_service_is_live_root()
{
	setup_svc_root=$(setup_service_root "$1")
	[ -z "$setup_svc_root" ]
}

setup_service_pid1()
{
	if [ -d /run/systemd/system ]; then
		printf '%s\n' systemd
		return 0
	fi
	if [ -d /run/openrc ]; then
		printf '%s\n' openrc
		return 0
	fi
	setup_svc_comm=
	if [ -r /proc/1/comm ]; then
		setup_svc_comm=$(tr -d '\0\n' </proc/1/comm 2>/dev/null) ||
			setup_svc_comm=
	fi
	setup_svc_cmd=
	if [ -r /proc/1/cmdline ]; then
		setup_svc_cmd=$(tr '\0' ' ' </proc/1/cmdline 2>/dev/null) ||
			setup_svc_cmd=
	fi
	case $setup_svc_comm in
		systemd) printf '%s\n' systemd; return 0 ;;
		openrc-init) printf '%s\n' openrc; return 0 ;;
		runit|runit-init) printf '%s\n' runit; return 0 ;;
		s6-svscan|s6-linux-init*) printf '%s\n' s6; return 0 ;;
		dinit) printf '%s\n' dinit; return 0 ;;
		shepherd) printf '%s\n' shepherd; return 0 ;;
		init)
			if [ -r /proc/1/exe ]; then
				setup_svc_exe=$(readlink -f /proc/1/exe 2>/dev/null) ||
					setup_svc_exe=
				case $setup_svc_exe in
					*systemd*) printf '%s\n' systemd; return 0 ;;
					*busybox*) ;;
					*)
						if [ -e /run/initctl ] || [ -p /dev/initctl ]
						then
							printf '%s\n' sysvinit
							return 0
						fi
						;;
				esac
			fi
			;;
	esac
	case $setup_svc_cmd in
		*systemd*) printf '%s\n' systemd; return 0 ;;
		*openrc*) printf '%s\n' openrc; return 0 ;;
		*runit*) printf '%s\n' runit; return 0 ;;
		*s6-svscan*|*s6-linux-init*) printf '%s\n' s6; return 0 ;;
		*dinit*) printf '%s\n' dinit; return 0 ;;
		*shepherd*) printf '%s\n' shepherd; return 0 ;;
	esac
	if [ -e /run/initctl ] || [ -p /dev/initctl ]; then
		printf '%s\n' sysvinit
		return 0
	fi
	if [ -d /run/runit ]; then
		printf '%s\n' runit
		return 0
	fi
	if [ -d /run/s6 ] || [ -d /run/s6-linux-init ]; then
		printf '%s\n' s6
		return 0
	fi
	if [ -d /run/dinit ] || [ -S /run/dinitctl ]; then
		printf '%s\n' dinit
		return 0
	fi
	if [ -d /run/shepherd ] || [ -S /run/shepherd/socket ]; then
		printf '%s\n' shepherd
		return 0
	fi
	printf '%s\n' none
}

setup_service_maybe_start()
{
	# Only start when installing onto the running machine.
	setup_service_is_live_root "$1" || return 0
	setup_svc_init=$2
	setup_svc_unit=$3
	setup_svc_rc=$4
	setup_svc_pid1=$(setup_service_pid1)
	[ "$setup_svc_pid1" = "$setup_svc_init" ] || return 0
	case $setup_svc_init in
		systemd)
			[ -n "$setup_svc_unit" ] || return 0
			command -v systemctl >/dev/null 2>&1 || return 0
			systemctl start "${setup_svc_unit%.service}" 2>/dev/null ||
				systemctl start "$setup_svc_unit" 2>/dev/null || :
			;;
		openrc)
			[ -n "$setup_svc_rc" ] || return 0
			if command -v rc-service >/dev/null 2>&1; then
				rc-service "$setup_svc_rc" start 2>/dev/null || :
			fi
			;;
		runit)
			[ -n "$setup_svc_rc" ] || return 0
			if command -v sv >/dev/null 2>&1; then
				sv start "$setup_svc_rc" 2>/dev/null || :
			fi
			;;
		s6)
			[ -n "$setup_svc_rc" ] || return 0
			if command -v s6-svc >/dev/null 2>&1 &&
			   [ -d /run/service/"$setup_svc_rc" ]
			then
				s6-svc -u /run/service/"$setup_svc_rc" 2>/dev/null || :
			fi
			;;
		dinit)
			[ -n "$setup_svc_rc" ] || return 0
			if command -v dinitctl >/dev/null 2>&1; then
				dinitctl start "$setup_svc_rc" 2>/dev/null || :
			fi
			;;
		shepherd)
			[ -n "$setup_svc_rc" ] || return 0
			if command -v herd >/dev/null 2>&1; then
				herd start "$setup_svc_rc" 2>/dev/null || :
			fi
			;;
		sysvinit)
			[ -n "$setup_svc_rc" ] || return 0
			if [ -x /etc/rc.d/init.d/"$setup_svc_rc" ]; then
				/etc/rc.d/init.d/"$setup_svc_rc" start 2>/dev/null || :
			elif [ -x /etc/init.d/"$setup_svc_rc" ]; then
				/etc/init.d/"$setup_svc_rc" start 2>/dev/null || :
			fi
			;;
	esac
	return 0
}

setup_service_enable_one()
{
	# $1 root  $2 init  $3 package
	setup_svc_root=$1
	setup_svc_init=$2
	setup_svc_pkg=$3
	setup_svc_fields=$(setup_service_lookup "$setup_svc_pkg") || return 1
	# shellcheck disable=SC2086
	set -- $setup_svc_fields
	setup_svc_unit=$1
	setup_svc_wanted=$2
	setup_svc_rc=$3
	setup_svc_level=$4
	setup_service_ensure_scripts "$setup_svc_root" "$setup_svc_init" \
		"$setup_svc_unit" "$setup_svc_rc"
	if [ -z "$setup_svc_rc" ]; then
		setup_svc_rc=${setup_svc_unit%.service}
	fi
	setup_svc_did=0
	case $setup_svc_init in
		systemd)
			if [ -n "$setup_svc_unit" ] &&
			   setup_service_enable_systemd "$setup_svc_root" \
				"$setup_svc_unit" "$setup_svc_wanted"
			then
				setup_svc_did=1
			fi
			;;
		openrc)
			if [ -n "$setup_svc_rc" ] &&
			   setup_service_enable_openrc "$setup_svc_root" \
				"$setup_svc_rc" "$setup_svc_level"
			then
				setup_svc_did=1
			fi
			;;
		runit)
			if [ -n "$setup_svc_rc" ] &&
			   setup_service_enable_runit "$setup_svc_root" \
				"$setup_svc_rc"
			then
				setup_svc_did=1
			fi
			;;
		s6)
			if [ -n "$setup_svc_rc" ] &&
			   setup_service_enable_s6 "$setup_svc_root" \
				"$setup_svc_rc"
			then
				setup_svc_did=1
			fi
			;;
		dinit)
			if [ -n "$setup_svc_rc" ] &&
			   setup_service_enable_dinit "$setup_svc_root" \
				"$setup_svc_rc"
			then
				setup_svc_did=1
			fi
			;;
		shepherd)
			if [ -n "$setup_svc_rc" ] &&
			   setup_service_enable_shepherd "$setup_svc_root" \
				"$setup_svc_rc"
			then
				setup_svc_did=1
			fi
			;;
		sysvinit)
			if [ -n "$setup_svc_rc" ] &&
			   setup_service_enable_sysvinit "$setup_svc_root" \
				"$setup_svc_rc" "$setup_svc_level"
			then
				setup_svc_did=1
			fi
			;;
		*)
			return 1
			;;
	esac
	[ "$setup_svc_did" -eq 1 ] || return 1
	setup_service_maybe_start "$setup_svc_root" "$setup_svc_init" \
		"$setup_svc_unit" "$setup_svc_rc"
	printf '%s\n' "$setup_svc_pkg"
	return 0
}

setup_service_enable_present()
{
	# Enable every mapped service whose unit/script is already in $1,
	# installing stock scripts first when the chosen init needs them.
	setup_svc_root=$1
	setup_svc_init=$2
	setup_svc_map=$(setup_service_map_file) || return 0
	while IFS= read -r setup_svc_line || [ -n "$setup_svc_line" ]; do
		case $setup_svc_line in
			''|\#*) continue ;;
		esac
		setup_svc_pkg=${setup_svc_line%%[[:space:]]*}
		[ -n "$setup_svc_pkg" ] || continue
		if setup_service_enable_one "$setup_svc_root" "$setup_svc_init" \
			"$setup_svc_pkg" >/dev/null
		then
			printf '%s\n' "$setup_svc_pkg"
		fi
	done <"$setup_svc_map"
	return 0
}

setup_service_hook_enable()
{
	# Called from pkin(1) after every post-install, and from package
	# hooks. SPS_PACKAGE and SPS_ROOT are set by pkin. A missing map
	# or unknown package is not an error.
	setup_svc_pkg=${SPS_PACKAGE-}
	[ -n "$setup_svc_pkg" ] || return 0
	setup_svc_root=${SPS_ROOT:-/}
	setup_svc_init=$(setup_service_init_of "$setup_svc_root")
	case $setup_svc_init in
		systemd|openrc|s6|runit|dinit|shepherd|sysvinit) ;;
		*) return 0 ;;
	esac
	setup_service_enable_one "$setup_svc_root" "$setup_svc_init" \
		"$setup_svc_pkg" >/dev/null || :
	return 0
}
