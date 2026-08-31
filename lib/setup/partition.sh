# Disk helpers for the SPS Linux (Splux) installer.
#
# This is sourced, not executed. Guided layouts run sfdisk(8) and mkfs only
# after the administrator has confirmed twice. setup never calls grub-install
# from here; bootloader install is a separate, explicit step.
#
# PATH on a live image often omits /sbin. Look there first.

setup_part_path()
{
	setup_old_path=$PATH
	PATH=/sbin:/usr/sbin:/bin:/usr/bin:$PATH
	export PATH
	command -v "$1" 2>/dev/null || {
		PATH=$setup_old_path
		return 1
	}
}

setup_partname()
{
	# nvme0n1 -> nvme0n1p1; sda -> sda1
	setup_disk=$1
	setup_n=$2
	case $setup_disk in
		*[0-9]) printf '%sp%s\n' "$setup_disk" "$setup_n" ;;
		*) printf '%s%s\n' "$setup_disk" "$setup_n" ;;
	esac
}

setup_lsblk()
{
	setup_part_path lsblk >/dev/null || return 1
	lsblk "$@"
}

setup_disk_menu_lines()
{
	# NAME SIZE MODEL TRAN, one disk per line. Skip loop/rom.
	setup_lsblk -dn -p -o NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null |
		awk '$3 == "disk" { print }'
}

setup_partition_tool_ok()
{
	setup_part_path sfdisk >/dev/null || return 1
	setup_part_path mkfs.ext4 >/dev/null || return 1
	setup_part_path mkfs.vfat >/dev/null || return 1
	setup_part_path mkswap >/dev/null || return 1
	return 0
}

setup_wipe_disk()
{
	setup_d=$1
	if setup_part_path wipefs >/dev/null; then
		wipefs -a "$setup_d" >/dev/null 2>&1 || :
	fi
}

setup_sfdisk_apply()
{
	setup_d=$1
	setup_script=$2
	setup_part_path sfdisk >/dev/null || return 1
	sfdisk --wipe always --wipe-partitions always "$setup_d" <"$setup_script"
}

setup_write_guided_script()
{
	# $1 = dest file, $2 = layout, $3 = swap size (sfdisk size token, e.g. 8GiB)
	setup_out=$1
	setup_layout=$2
	setup_swap=${3:-8GiB}
	case $setup_layout in
		efi-root)
			cat >"$setup_out" <<'EOF'
label: gpt
size=512MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=EFI
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=root
EOF
			;;
		efi-swap-root)
			cat >"$setup_out" <<EOF
label: gpt
size=512MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=EFI
size=$setup_swap, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name=swap
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=root
EOF
			;;
		efi-swap-root-home)
			cat >"$setup_out" <<EOF
label: gpt
size=512MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=EFI
size=$setup_swap, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name=swap
size=48GiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=root
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=home
EOF
			;;
		bios-root)
			cat >"$setup_out" <<'EOF'
label: gpt
size=1MiB, type=21686148-6449-6E6F-744E-656564454649, name=BIOS
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=root
EOF
			;;
		*)
			return 1
			;;
	esac
}

setup_assign_guided_parts()
{
	setup_d=$1
	setup_layout=$2
	setup_part_efi=
	setup_part_swap=
	setup_part_root=
	setup_part_home=
	setup_part_bios=
	case $setup_layout in
		efi-root)
			setup_part_efi=$(setup_partname "$setup_d" 1)
			setup_part_root=$(setup_partname "$setup_d" 2)
			;;
		efi-swap-root)
			setup_part_efi=$(setup_partname "$setup_d" 1)
			setup_part_swap=$(setup_partname "$setup_d" 2)
			setup_part_root=$(setup_partname "$setup_d" 3)
			;;
		efi-swap-root-home)
			setup_part_efi=$(setup_partname "$setup_d" 1)
			setup_part_swap=$(setup_partname "$setup_d" 2)
			setup_part_root=$(setup_partname "$setup_d" 3)
			setup_part_home=$(setup_partname "$setup_d" 4)
			;;
		bios-root)
			setup_part_bios=$(setup_partname "$setup_d" 1)
			setup_part_root=$(setup_partname "$setup_d" 2)
			;;
		*)
			return 1
			;;
	esac
}

setup_mount_prepared()
{
	setup_tgt=${1%/}
	[ -n "$setup_part_root" ] || return 1
	mkdir -p "$setup_tgt" || return 1
	mount "$setup_part_root" "$setup_tgt" || return 1
	if [ -n "$setup_part_efi" ]; then
		mkdir -p "$setup_tgt/boot/efi"
		mount "$setup_part_efi" "$setup_tgt/boot/efi" || return 1
	fi
	if [ -n "$setup_part_home" ]; then
		mkdir -p "$setup_tgt/home"
		mount "$setup_part_home" "$setup_tgt/home" || return 1
	fi
	if [ -n "$setup_part_swap" ]; then
		swapon "$setup_part_swap" 2>/dev/null || :
	fi
	return 0
}

setup_format_and_mount()
{
	setup_tgt=${1%/}
	[ -n "$setup_part_root" ] || return 1
	mkdir -p "$setup_tgt" || return 1

	if [ -n "$setup_part_efi" ]; then
		mkfs.vfat -F 32 -n SPS_EFI "$setup_part_efi" || return 1
	fi
	if [ -n "$setup_part_swap" ]; then
		mkswap -L sps-swap "$setup_part_swap" || return 1
	fi
	mkfs.ext4 -F -L sps-root "$setup_part_root" || return 1
	if [ -n "$setup_part_home" ]; then
		mkfs.ext4 -F -L sps-home "$setup_part_home" || return 1
	fi

	mount "$setup_part_root" "$setup_tgt" || return 1
	if [ -n "$setup_part_efi" ]; then
		mkdir -p "$setup_tgt/boot/efi"
		mount "$setup_part_efi" "$setup_tgt/boot/efi" || return 1
	fi
	if [ -n "$setup_part_home" ]; then
		mkdir -p "$setup_tgt/home"
		mount "$setup_part_home" "$setup_tgt/home" || return 1
	fi
	if [ -n "$setup_part_swap" ]; then
		swapon "$setup_part_swap" 2>/dev/null || :
	fi
	return 0
}

setup_uuid_of()
{
	setup_p=$1
	[ -n "$setup_p" ] || return 0
	if setup_part_path blkid >/dev/null; then
		blkid -s UUID -o value "$setup_p" 2>/dev/null || :
	fi
}

setup_write_fstab()
{
	setup_tgt=${1%/}
	setup_fstab=$setup_tgt/etc/fstab
	mkdir -p "$setup_tgt/etc" || return 1
	{
		printf '%s\n' '# /etc/fstab written by SPS setup. Review before the first boot.'
		setup_u=$(setup_uuid_of "$setup_part_root")
		if [ -n "$setup_u" ]; then
			printf 'UUID=%s / ext4 defaults 1 1\n' "$setup_u"
		elif [ -n "$setup_part_root" ]; then
			printf '%s / ext4 defaults 1 1\n' "$setup_part_root"
		fi
		setup_u=$(setup_uuid_of "$setup_part_efi")
		if [ -n "$setup_u" ]; then
			printf 'UUID=%s /boot/efi vfat umask=0077 0 2\n' "$setup_u"
		elif [ -n "$setup_part_efi" ]; then
			printf '%s /boot/efi vfat umask=0077 0 2\n' "$setup_part_efi"
		fi
		setup_u=$(setup_uuid_of "$setup_part_home")
		if [ -n "$setup_u" ]; then
			printf 'UUID=%s /home ext4 defaults 1 2\n' "$setup_u"
		elif [ -n "$setup_part_home" ]; then
			printf '%s /home ext4 defaults 1 2\n' "$setup_part_home"
		fi
		setup_u=$(setup_uuid_of "$setup_part_swap")
		if [ -n "$setup_u" ]; then
			printf 'UUID=%s none swap defaults 0 0\n' "$setup_u"
		elif [ -n "$setup_part_swap" ]; then
			printf '%s none swap defaults 0 0\n' "$setup_part_swap"
		fi
	} >"$setup_fstab"
}

setup_apply_partition()
{
	# Destructive. Caller already confirmed.
	setup_tgt=$1
	case $setup_partition in
		none|existing|'')
			return 0
			;;
	esac
	[ -n "$setup_disk" ] || return 1
	setup_partition_tool_ok || return 1
	case $setup_partition in
		efi-root|efi-swap-root|efi-swap-root-home|bios-root)
			setup_script=$setup_work/sfdisk.script
			setup_write_guided_script "$setup_script" "$setup_partition" \
				"${setup_swap_size:-8GiB}" || return 1
			setup_wipe_disk "$setup_disk"
			setup_sfdisk_apply "$setup_disk" "$setup_script" || return 1
			# Let the kernel reread the partition table.
			if setup_part_path partprobe >/dev/null; then
				partprobe "$setup_disk" 2>/dev/null || :
			fi
			sleep 1
			setup_assign_guided_parts "$setup_disk" "$setup_partition" || return 1
			setup_format_and_mount "$setup_tgt" || return 1
			;;
		manage)
			[ -n "$setup_part_root" ] || return 1
			if [ "${setup_format:-no}" = yes ]; then
				setup_format_and_mount "$setup_tgt" || return 1
			else
				setup_mount_prepared "$setup_tgt" || return 1
			fi
			;;
		*)
			return 1
			;;
	esac
	return 0
}
