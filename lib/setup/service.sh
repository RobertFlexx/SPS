# Init-aware service enablement for the SPS Linux installer.
#
# Sourced, not executed. setup(1) and package post-install hooks call these
# helpers. They never invent an init; they read /etc/sps/init (or the
# hook environment) and only enable units/scripts that already exist in
# the target. Enablement is on-boot; start happens only when the target
# is the running system and PID 1 matches.

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

setup_service_init_of()
{
	setup_svc_root=$(setup_service_root "$1")
	if [ -z "$setup_svc_root" ]; then
		setup_svc_initf=/etc/sps/init
	else
		setup_svc_initf=$setup_svc_root/etc/sps/init
	fi
	if [ -f "$setup_svc_initf" ]; then
		sed -n '1p' "$setup_svc_initf"
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
	set -- $setup_svc_fields
	setup_svc_unit=$1
	setup_svc_wanted=$2
	setup_svc_rc=$3
	setup_svc_level=$4
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
	# Enable every mapped service whose unit/script is already in $1.
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
	# Called from package post-install hooks. SPS_PACKAGE and SPS_ROOT
	# are set by pkin(1). A missing map or unknown package is not an error.
	setup_svc_pkg=${SPS_PACKAGE-}
	[ -n "$setup_svc_pkg" ] || return 0
	setup_svc_root=${SPS_ROOT:-/}
	setup_svc_init=$(setup_service_init_of "$setup_svc_root")
	case $setup_svc_init in
		systemd|openrc) ;;
		*) return 0 ;;
	esac
	setup_service_enable_one "$setup_svc_root" "$setup_svc_init" \
		"$setup_svc_pkg" >/dev/null || :
	return 0
}
