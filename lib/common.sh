#!/bin/sh
# Shared shell helpers used by the SPS commands.

SPS_EX_USAGE=2
SPS_EX_NOTFOUND=3
SPS_EX_PACKAGE=4
SPS_EX_DEPENDENCY=5
SPS_EX_CHECKSUM=6
SPS_EX_CONFLICT=7
SPS_EX_PERMISSION=8
SPS_EX_NETWORK=9
SPS_EX_BUILD=10
SPS_EX_DATABASE=11

sps_basename()
{
	case ${1-} in
		*/*) printf '%s\n' "${1##*/}" ;;
		*) printf '%s\n' "${1-}" ;;
	esac
}

sps_program=${sps_program:-${sps_prog:-$(sps_basename "$0")}}
[ -z "${SPS_LIBDIR+x}" ] || export SPS_LIBDIR

sps_die()
{
	case ${1-} in
		''|*[!0-9]*) sps_status=1 ;;
		*) sps_status=$1; shift ;;
	esac
	printf '%s: %s\n' "$sps_program" "$*" >&2
	exit "$sps_status"
}

sps_warn()
{
	printf '%s: %s\n' "$sps_program" "$*" >&2
}

sps_usage()
{
	printf 'usage: %s\n' "$*" >&2
	exit "$SPS_EX_USAGE"
}

sps_need_arg()
{
	[ "$#" -ge 2 ] && [ -n "${2-}" ] ||
		sps_die "$SPS_EX_USAGE" "option '$1' requires an argument"
}

sps_mkdir()
{
	[ -d "$1" ] || mkdir -p "$1" ||
		sps_die "$SPS_EX_PERMISSION" "cannot create directory: $1"
}

sps_root_path()
{
	sps_path=$1
	case $sps_path in
		/*)
			if [ "${SPS_ROOT:-/}" = / ]; then
				printf '%s\n' "$sps_path"
			else
				printf '%s%s\n' "${SPS_ROOT%/}" "$sps_path"
			fi
			;;
		*) printf '%s/%s\n' "${SPS_ROOT:-/}" "$sps_path" ;;
	esac
}

sps_mktemp_dir()
{
	sps_tmp_parent=$1
	sps_tmp_tag=${2:-work}
	sps_mkdir "$sps_tmp_parent"
	sps_tmp=$(mktemp -d "$sps_tmp_parent/.sps-$sps_tmp_tag.XXXXXX") ||
		sps_die "$SPS_EX_PERMISSION" \
			"cannot create temporary directory in $sps_tmp_parent"
	printf '%s\n' "$sps_tmp"
}

sps_require_cmd()
{
	command -v "$1" >/dev/null 2>&1 ||
		sps_die "$SPS_EX_PACKAGE" "required command not found: $1"
}

# Print only the digest. Avoid an extra awk process here.
sps_sha256()
{
	if command -v sha256sum >/dev/null 2>&1; then
		sps_hash_line=$(sha256sum "$1") || return $?
		printf '%s\n' "${sps_hash_line%% *}"
	elif command -v sha256 >/dev/null 2>&1; then
		sha256 -q "$1"
	elif command -v shasum >/dev/null 2>&1; then
		sps_hash_line=$(shasum -a 256 "$1") || return $?
		printf '%s\n' "${sps_hash_line%% *}"
	elif command -v openssl >/dev/null 2>&1; then
		sps_hash_line=$(openssl dgst -sha256 "$1") || return $?
		printf '%s\n' "${sps_hash_line##* }"
	else
		sps_die "$SPS_EX_CHECKSUM" \
			"no SHA-256 utility found (tried sha256sum, sha256, shasum, openssl)"
	fi
}

sps_validate_package_name()
{
	case ${1-} in
		''|[!A-Za-z0-9]*|*/*|*[!A-Za-z0-9_+.-]*) return 1 ;;
		*) return 0 ;;
	esac
}

sps_tab_safe()
{
	case ${1-} in
		*"	"*|*"
"*) return 1 ;;
		*) return 0 ;;
	esac
}

# SPS_PRESERVE is a comma-separated list of package-relative prefixes. "etc"
# covers etc and everything below it; "none" turns the check off.
sps_is_preserved_path()
{
	sps_preserve_path=${1#/}
	[ "${SPS_PRESERVE:-etc}" != none ] || return 1
	sps_preserve_rest=${SPS_PRESERVE:-etc}
	while :; do
		case $sps_preserve_rest in
			*,*) sps_preserve_prefix=${sps_preserve_rest%%,*}; sps_preserve_rest=${sps_preserve_rest#*,} ;;
			*) sps_preserve_prefix=$sps_preserve_rest; sps_preserve_rest= ;;
		esac
		sps_preserve_prefix=${sps_preserve_prefix#/}
		sps_preserve_prefix=${sps_preserve_prefix%/}
		if [ -n "$sps_preserve_prefix" ]; then
			case $sps_preserve_path in
				"$sps_preserve_prefix"|"$sps_preserve_prefix"/*) return 0 ;;
			esac
		fi
		[ -n "$sps_preserve_rest" ] || break
	done
	return 1
}

# Cache the uid check. pkin calls this for many payload entries.
sps_is_root()
{
	if [ "${sps_uid_is_root+x}" != x ]; then
		sps_uid=$(id -u 2>/dev/null || printf '%s\n' 1)
		case $sps_uid in
			0) sps_uid_is_root=1 ;;
			*) sps_uid_is_root=0 ;;
		esac
	fi
	[ "$sps_uid_is_root" -eq 1 ]
}

# Turn the POSIX ls permission string into an octal mode. Keep the parsing in
# shell so mode lookup needs only the ls process.
sps_mode_of()
{
	sps_mode_line=$(LC_ALL=C ls -ld "$1" 2>/dev/null) || return 1
	sps_mode_text=${sps_mode_line%% *}
	# Some ls implementations append an ACL/xattr marker; ignore it.
	sps_mode_tail=${sps_mode_text#??????????}
	sps_mode_text=${sps_mode_text%"$sps_mode_tail"}
	case $sps_mode_text in ??????????) ;; *) return 1 ;; esac
	sps_mode_bits=${sps_mode_text#?}
	sps_mode_user=${sps_mode_bits%??????}
	sps_mode_rest=${sps_mode_bits#???}
	sps_mode_group=${sps_mode_rest%???}
	sps_mode_other=${sps_mode_rest#???}

	sps_mode_u=0; sps_mode_g=0; sps_mode_o=0; sps_mode_s=0
	case $sps_mode_user in r??) sps_mode_u=$((sps_mode_u + 4)) ;; esac
	case $sps_mode_user in ?w?) sps_mode_u=$((sps_mode_u + 2)) ;; esac
	case $sps_mode_user in ??[xst]) sps_mode_u=$((sps_mode_u + 1)) ;; esac
	case $sps_mode_group in r??) sps_mode_g=$((sps_mode_g + 4)) ;; esac
	case $sps_mode_group in ?w?) sps_mode_g=$((sps_mode_g + 2)) ;; esac
	case $sps_mode_group in ??[xst]) sps_mode_g=$((sps_mode_g + 1)) ;; esac
	case $sps_mode_other in r??) sps_mode_o=$((sps_mode_o + 4)) ;; esac
	case $sps_mode_other in ?w?) sps_mode_o=$((sps_mode_o + 2)) ;; esac
	case $sps_mode_other in ??[xst]) sps_mode_o=$((sps_mode_o + 1)) ;; esac
	case $sps_mode_user in ??[sS]) sps_mode_s=$((sps_mode_s + 4)) ;; esac
	case $sps_mode_group in ??[sS]) sps_mode_s=$((sps_mode_s + 2)) ;; esac
	case $sps_mode_other in ??[tT]) sps_mode_s=$((sps_mode_s + 1)) ;; esac
	printf '%d%d%d%d\n' "$sps_mode_s" "$sps_mode_u" "$sps_mode_g" "$sps_mode_o"
}

# Root installs normalize new payload ownership to root:root. Do not copy the
# builder's numeric uid/gid into the target system.
sps_normalize_owner()
{
	sps_is_root || return 0
	chown 0:0 "$1"
}

# mkdir gives us the lock atomically. Only remove a stale lock when its recorded
# numeric PID can be checked safely.
sps_lock_acquire()
{
	sps_lock_base=$1
	sps_lock_name=${2:-.lock}
	case $sps_lock_name in ''|*/*|.|..) return 1 ;; esac
	sps_lock=$sps_lock_base/$sps_lock_name
	sps_lock_owned=0
	if mkdir "$sps_lock" 2>/dev/null; then
		printf '%s\n' "$$" >"$sps_lock/pid" || {
			rmdir "$sps_lock" 2>/dev/null || :
			return 1
		}
		sps_lock_owned=1
		return 0
	fi

	[ -d "$sps_lock" ] && [ ! -L "$sps_lock" ] || return 1
	[ -f "$sps_lock/pid" ] && [ ! -L "$sps_lock/pid" ] || return 1
	sps_lock_pid=$(sed -n '1p' "$sps_lock/pid" 2>/dev/null) || return 1
	case $sps_lock_pid in ''|*[!0-9]*) return 1 ;; esac
	if kill -0 "$sps_lock_pid" 2>/dev/null; then
		return 1
	fi

	sps_warn "removing stale package database lock from pid $sps_lock_pid"
	rm -f "$sps_lock/pid" 2>/dev/null || return 1
	rmdir "$sps_lock" 2>/dev/null || return 1
	if mkdir "$sps_lock" 2>/dev/null; then
		printf '%s\n' "$$" >"$sps_lock/pid" || {
			rmdir "$sps_lock" 2>/dev/null || :
			return 1
		}
		sps_lock_owned=1
		return 0
	fi
	return 1
}

sps_lock_release()
{
	[ "${sps_lock_owned:-0}" -eq 1 ] || return 0
	rm -f "$sps_lock/pid" 2>/dev/null || :
	rmdir "$sps_lock" 2>/dev/null || :
	sps_lock_owned=0
}

# Print repo lines from the main config and repos.conf.
sps_repo_lines()
{
	for sps_repo_file in "$SPS_CONFIG" "$SPS_REPOS_CONFIG"; do
		[ -r "$sps_repo_file" ] || continue
		awk '
			/^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
			$1 == "repo" && NF >= 3 {
				printf "repo %s %s", $2, $3
				if (NF >= 4) printf " %s", $4
				printf "\n"
			}
		' "$sps_repo_file"
	done
}

sps_load_config()
{
	[ "${SPS_ROOT+x}" = x ] && sps_env_root=1 || sps_env_root=0
	[ "${SPS_DB+x}" = x ] && sps_env_db=1 || sps_env_db=0
	[ "${SPS_CACHE+x}" = x ] && sps_env_cache=1 || sps_env_cache=0
	[ "${SPS_BUILD+x}" = x ] && sps_env_build=1 || sps_env_build=0
	[ "${SPS_MAKEJOBS+x}" = x ] && sps_env_makejobs=1 || sps_env_makejobs=0
	[ "${SPS_COMPRESSION+x}" = x ] && sps_env_compression=1 || sps_env_compression=0
	[ "${SPS_ARCH+x}" = x ] && sps_env_arch=1 || sps_env_arch=0
	[ "${SPS_PRESERVE+x}" = x ] && sps_env_preserve=1 || sps_env_preserve=0

	SPS_ROOT=${SPS_ROOT:-/}
	case $SPS_ROOT in
		/*) ;;
		*) sps_die "$SPS_EX_USAGE" "SPS_ROOT must be an absolute path: $SPS_ROOT" ;;
	esac
	[ "$SPS_ROOT" = / ] || SPS_ROOT=${SPS_ROOT%/}

	if [ "${SPS_CONFIG+x}" != x ]; then
		SPS_CONFIG=$(sps_root_path /etc/sps/sps.conf)
	fi
	if [ "${SPS_REPOS_CONFIG+x}" != x ]; then
		SPS_REPOS_CONFIG=$(sps_root_path /etc/sps/repos.conf)
	fi

	sps_cfg_root=$SPS_ROOT
	sps_cfg_db=/var/lib/sps
	sps_cfg_cache=/var/cache/sps
	sps_cfg_build=/var/tmp/sps
	sps_cfg_makejobs=1
	sps_cfg_compression=auto
	sps_cfg_arch=$(uname -m 2>/dev/null || printf '%s' unknown)
	sps_cfg_preserve=etc

	if [ -r "$SPS_CONFIG" ]; then
		while IFS=' 	' read -r sps_key sps_value sps_extra; do
			case $sps_key in
				''|'#'*) continue ;;
				root) [ "$sps_env_root" -eq 1 ] || sps_cfg_root=$sps_value ;;
				db) sps_cfg_db=$sps_value ;;
				cache) sps_cfg_cache=$sps_value ;;
				build) sps_cfg_build=$sps_value ;;
				makejobs) sps_cfg_makejobs=$sps_value ;;
				compression) sps_cfg_compression=$sps_value ;;
				arch) sps_cfg_arch=$sps_value ;;
				preserve) sps_cfg_preserve=$sps_value ;;
				repo) : ;;
				*) sps_warn "ignoring unknown configuration key '$sps_key' in $SPS_CONFIG" ;;
			esac
		done < "$SPS_CONFIG"
	fi

	if [ "$sps_env_root" -eq 0 ]; then
		SPS_ROOT=$sps_cfg_root
		case $SPS_ROOT in /*) ;; *) sps_die "$SPS_EX_USAGE" "configured root must be absolute" ;; esac
		[ "$SPS_ROOT" = / ] || SPS_ROOT=${SPS_ROOT%/}
	fi
	[ "$sps_env_db" -eq 1 ] || SPS_DB=$(sps_root_path "$sps_cfg_db")
	[ "$sps_env_cache" -eq 1 ] || SPS_CACHE=$(sps_root_path "$sps_cfg_cache")
	[ "$sps_env_build" -eq 1 ] || SPS_BUILD=$(sps_root_path "$sps_cfg_build")
	[ "$sps_env_makejobs" -eq 1 ] || SPS_MAKEJOBS=$sps_cfg_makejobs
	[ "$sps_env_compression" -eq 1 ] || SPS_COMPRESSION=$sps_cfg_compression
	[ "$sps_env_arch" -eq 1 ] || SPS_ARCH=$sps_cfg_arch
	[ "$sps_env_preserve" -eq 1 ] || SPS_PRESERVE=$sps_cfg_preserve
	[ "$SPS_COMPRESSION" = zst ] && SPS_COMPRESSION=zstd

	case $SPS_MAKEJOBS in ''|*[!0-9]*|0) sps_die "$SPS_EX_USAGE" "makejobs must be a positive integer" ;; esac
	case $SPS_COMPRESSION in
		auto|none|gzip|xz|zstd) ;;
		*) sps_die "$SPS_EX_USAGE" "unsupported compression '$SPS_COMPRESSION'" ;;
	esac
	case $SPS_ARCH in
		''|*[!A-Za-z0-9._+-]*|[!A-Za-z0-9]*)
			sps_die "$SPS_EX_USAGE" "invalid architecture '$SPS_ARCH'" ;;
	esac
	case $SPS_PRESERVE in
		'') sps_die "$SPS_EX_USAGE" "preserve may not be empty" ;;
		*" "*|*"	"*|*"
"*) sps_die "$SPS_EX_USAGE" "preserve must be a comma-separated path-prefix list" ;;
	esac

	export SPS_ROOT SPS_DB SPS_CACHE SPS_BUILD SPS_CONFIG SPS_REPOS_CONFIG
	export SPS_MAKEJOBS SPS_COMPRESSION SPS_ARCH SPS_PRESERVE
}
