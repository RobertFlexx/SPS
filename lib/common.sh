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

# Same digest as sps_sha256, from stdin. Used for the recipe-only definition
# manifest so src update does not create a throwaway directory per package.
sps_sha256_stream()
{
	if command -v sha256sum >/dev/null 2>&1; then
		sps_hash_line=$(sha256sum) || return $?
		printf '%s\n' "${sps_hash_line%% *}"
	elif command -v sha256 >/dev/null 2>&1; then
		sha256 -q
	elif command -v shasum >/dev/null 2>&1; then
		sps_hash_line=$(shasum -a 256) || return $?
		printf '%s\n' "${sps_hash_line%% *}"
	elif command -v openssl >/dev/null 2>&1; then
		sps_hash_line=$(openssl dgst -sha256) || return $?
		printf '%s\n' "${sps_hash_line##* }"
	else
		sps_die "$SPS_EX_CHECKSUM" \
			"no SHA-256 utility found (tried sha256sum, sha256, shasum, openssl)"
	fi
}

# Hash every input which makes up one package definition.  The manifest uses
# only fixed, package-relative names, so moving an unchanged package directory
# does not change its digest.  files/ and patches/ are copied recursively by
# mkpkg, making their directory and file modes observable build inputs too.
sps_definition_sha256()
(
	sps_definition_input=${1-}
	case $sps_definition_input in
		'') sps_warn 'package definition recipe is missing'; return 1 ;;
		*/*)
			sps_definition_parent=${sps_definition_input%/*}
			sps_definition_leaf=${sps_definition_input##*/}
			;;
		*)
			sps_definition_parent=.
			sps_definition_leaf=$sps_definition_input
			;;
	esac
	case $sps_definition_parent in
		-*) sps_definition_parent=./$sps_definition_parent ;;
	esac
	sps_definition_dir=$(CDPATH= cd -P "$sps_definition_parent" 2>/dev/null &&
		pwd -P) || {
		sps_warn 'cannot enter package definition directory'
		return 1
	}
	sps_definition_recipe=$sps_definition_dir/$sps_definition_leaf
	if [ ! -f "$sps_definition_recipe" ] ||
	   [ -L "$sps_definition_recipe" ] ||
	   [ ! -r "$sps_definition_recipe" ]; then
		sps_warn 'package definition recipe must be a readable regular file'
		return 1
	fi

	# Recipe-only packages produce a two-line manifest. Hash that without a
	# workspace directory; src update indexes hundreds of these.
	sps_definition_need_support=0
	for sps_definition_support in files patches hooks; do
		if [ -e "$sps_definition_dir/$sps_definition_support" ] ||
		   [ -L "$sps_definition_dir/$sps_definition_support" ]; then
			sps_definition_need_support=1
			break
		fi
	done
	if [ "$sps_definition_need_support" -eq 0 ]; then
		sps_definition_hash=$(sps_sha256 "$sps_definition_recipe") || {
			sps_warn 'cannot hash package definition recipe'
			return 1
		}
		sps_definition_hash=$(printf '%s\n' "$sps_definition_hash" |
			LC_ALL=C tr 'ABCDEF' 'abcdef') || return 1
		case $sps_definition_hash in
			''|*[!0123456789abcdef]*) return 1 ;;
		esac
		[ "${#sps_definition_hash}" -eq 64 ] || return 1
		sps_definition_out=$(printf 'sps-package-definition\t1\nfile\t-\t%s\trecipe\n' \
			"$sps_definition_hash" | sps_sha256_stream) || {
			sps_warn 'cannot hash package definition manifest'
			return 1
		}
		sps_definition_out=$(printf '%s\n' "$sps_definition_out" |
			LC_ALL=C tr 'ABCDEF' 'abcdef') || return 1
		case $sps_definition_out in
			''|*[!0123456789abcdef]*) return 1 ;;
		esac
		[ "${#sps_definition_out}" -eq 64 ] || return 1
		printf '%s\n' "$sps_definition_out"
		return 0
	fi

	sps_definition_tmp=$(mktemp -d \
		"${TMPDIR:-/tmp}/.sps-definition.XXXXXX" 2>/dev/null) || {
		sps_warn 'cannot create package definition hash workspace'
		return 1
	}
	sps_definition_cleanup()
	{
		rm -f "$sps_definition_tmp/manifest" \
			"$sps_definition_tmp/paths.raw" \
			"$sps_definition_tmp/paths" \
			"$sps_definition_tmp/unsafe-path" \
			"$sps_definition_tmp/unsafe-type"
		rmdir "$sps_definition_tmp" 2>/dev/null || :
	}
	trap 'sps_definition_cleanup' 0
	trap 'exit 1' 1 2 3 15

	sps_definition_hash_file()
	{
		sps_definition_value=$(sps_sha256 "$1") || return $?
		sps_definition_value=$(printf '%s\n' "$sps_definition_value" |
			LC_ALL=C tr 'ABCDEF' 'abcdef') || return $?
		case $sps_definition_value in
			''|*[!0123456789abcdef]*) return 1 ;;
		esac
		[ "${#sps_definition_value}" -eq 64 ] || return 1
		printf '%s\n' "$sps_definition_value"
	}

	sps_definition_manifest=$sps_definition_tmp/manifest
	printf 'sps-package-definition\t1\n' >"$sps_definition_manifest" ||
		return 1
	sps_definition_hash=$(sps_definition_hash_file \
		"$sps_definition_recipe") || {
		sps_warn 'cannot hash package definition recipe'
		return 1
	}
	printf 'file\t-\t%s\trecipe\n' "$sps_definition_hash" \
		>>"$sps_definition_manifest" || return 1

	cd "$sps_definition_dir" || return 1
	for sps_definition_support in files patches hooks; do
		if [ ! -e "$sps_definition_support" ] &&
		   [ ! -L "$sps_definition_support" ]; then
			continue
		fi
		if [ ! -d "$sps_definition_support" ] ||
		   [ -L "$sps_definition_support" ]; then
			sps_warn "recipe $sps_definition_support must be a real directory"
			return 1
		fi

		rm -f "$sps_definition_tmp/unsafe-path" \
			"$sps_definition_tmp/unsafe-type"
		if ! find "$sps_definition_support" -exec sh -c '
			marker=$1
			shift
			for path do
				case $path in
					*"	"*|*"
"*) : >"$marker"; exit 0 ;;
				esac
			done
		' sh "$sps_definition_tmp/unsafe-path" {} +; then
			sps_warn "cannot inspect package definition $sps_definition_support"
			return 1
		fi
		if [ -e "$sps_definition_tmp/unsafe-path" ]; then
			sps_warn "package definition $sps_definition_support contains a tab or newline in a path"
			return 1
		fi
		if ! find "$sps_definition_support" ! -type d ! -type f \
			-exec sh -c ': >"$1"' sh \
			"$sps_definition_tmp/unsafe-type" {} +; then
			sps_warn "cannot inspect package definition $sps_definition_support"
			return 1
		fi
		if [ -e "$sps_definition_tmp/unsafe-type" ]; then
			sps_warn "package definition $sps_definition_support contains a symlink or special file"
			return 1
		fi
		if ! find "$sps_definition_support" -print \
			>"$sps_definition_tmp/paths.raw"; then
			sps_warn "cannot list package definition $sps_definition_support"
			return 1
		fi
		if ! LC_ALL=C sort "$sps_definition_tmp/paths.raw" \
			>"$sps_definition_tmp/paths"; then
			sps_warn "cannot sort package definition $sps_definition_support"
			return 1
		fi

		while IFS= read -r sps_definition_path ||
		      [ -n "$sps_definition_path" ]; do
			[ -n "$sps_definition_path" ] || continue
			if [ -d "$sps_definition_path" ] &&
			   [ ! -L "$sps_definition_path" ]; then
				sps_definition_mode=$(sps_mode_of \
					"$sps_definition_path") || {
					sps_warn "cannot read a $sps_definition_support directory mode"
					return 1
				}
				printf 'directory\t%s\t-\t%s\n' \
					"$sps_definition_mode" "$sps_definition_path" \
					>>"$sps_definition_manifest" || return 1
			elif [ -f "$sps_definition_path" ] &&
			     [ ! -L "$sps_definition_path" ]; then
				sps_definition_mode=$(sps_mode_of \
					"$sps_definition_path") || {
					sps_warn "cannot read a $sps_definition_support file mode"
					return 1
				}
				sps_definition_hash=$(sps_definition_hash_file \
					"$sps_definition_path") || {
					sps_warn "cannot hash a $sps_definition_support file"
					return 1
				}
				printf 'file\t%s\t%s\t%s\n' "$sps_definition_mode" \
					"$sps_definition_hash" "$sps_definition_path" \
					>>"$sps_definition_manifest" || return 1
			else
				sps_warn "package definition $sps_definition_support changed while hashing"
				return 1
			fi
		done <"$sps_definition_tmp/paths"
	done

	sps_definition_hash_file "$sps_definition_manifest"
)

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
	sps_lock_label=${3:-package database}
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

	sps_warn "removing stale $sps_lock_label lock '$sps_lock' from pid $sps_lock_pid"
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

# Print repository declarations without normalizing or truncating them. General
# settings in sps.conf are ignored here; repos.conf is repository-only, so an
# unknown declaration there is preserved for repository.awk to reject.
sps_repo_lines()
{
	sps_repo_previous=
	for sps_repo_file in "$SPS_CONFIG" "$SPS_REPOS_CONFIG"; do
		[ -r "$sps_repo_file" ] || continue
		[ "$sps_repo_file" != "$sps_repo_previous" ] || continue
		if [ "$sps_repo_file" = "$SPS_CONFIG" ]; then
			sps_repo_main=1
		else
			sps_repo_main=0
		fi
		awk -v main_config="$sps_repo_main" '
			{
				line = $0
				sub(/\r$/, "", line)
				probe = line
				sub(/^[ \t]+/, "", probe)
				if (probe == "" || probe ~ /^#/)
					next
				split(probe, field, /[ \t]+/)
				if (!main_config || field[1] == "git" ||
				    field[1] == "dir" || field[1] == "repo")
					print line
			}
		' "$sps_repo_file" || return $?
		sps_repo_previous=$sps_repo_file
	done
}

sps_load_config()
{
	[ "${SPS_ROOT+x}" = x ] && sps_env_root=1 || sps_env_root=0
	[ "${SPS_DB+x}" = x ] && sps_env_db=1 || sps_env_db=0
	[ "${SPS_CACHE+x}" = x ] && sps_env_cache=1 || sps_env_cache=0
	[ "${SPS_BUILD+x}" = x ] && sps_env_build=1 || sps_env_build=0
	[ "${SPS_REPO_ROOT+x}" = x ] && sps_env_repo_root=1 || sps_env_repo_root=0
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
	sps_cfg_repo_root=/usr/src/sps
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
				repo_root) sps_cfg_repo_root=$sps_value ;;
				makejobs) sps_cfg_makejobs=$sps_value ;;
				compression) sps_cfg_compression=$sps_value ;;
				arch) sps_cfg_arch=$sps_value ;;
				preserve) sps_cfg_preserve=$sps_value ;;
				repo|git|dir) : ;;
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
	[ "$sps_env_repo_root" -eq 1 ] || SPS_REPO_ROOT=$(sps_root_path "$sps_cfg_repo_root")
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
	case $SPS_REPO_ROOT in
		/*) ;;
		*) sps_die "$SPS_EX_USAGE" "SPS_REPO_ROOT must be an absolute path: $SPS_REPO_ROOT" ;;
	esac
	[ "$SPS_REPO_ROOT" = / ] || SPS_REPO_ROOT=${SPS_REPO_ROOT%/}
	case $SPS_PRESERVE in
		'') sps_die "$SPS_EX_USAGE" "preserve may not be empty" ;;
		*" "*|*"	"*|*"
"*) sps_die "$SPS_EX_USAGE" "preserve must be a comma-separated path-prefix list" ;;
	esac

	export SPS_ROOT SPS_DB SPS_CACHE SPS_BUILD SPS_REPO_ROOT SPS_CONFIG SPS_REPOS_CONFIG
	export SPS_MAKEJOBS SPS_COMPRESSION SPS_ARCH SPS_PRESERVE
}
