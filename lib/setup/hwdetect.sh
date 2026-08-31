# Hardware -> package mapping for the SPS Linux installer.
#
# Sourced, not executed. Reads lspci -nn and /proc/cpuinfo. The live ISO and
# an installed system both have pciutils in the usual place; if lspci is
# missing we just print nothing and the installer leaves drivers off.

setup_hw_lspci()
{
	PATH=/sbin:/usr/sbin:/bin:/usr/bin:$PATH
	export PATH
	if command -v lspci >/dev/null 2>&1; then
		lspci -nn 2>/dev/null || :
	fi
}

setup_hw_cpu_vendor()
{
	awk -F: '
		tolower($1) ~ /vendor_id/ {
			gsub(/^[ \t]+|[ \t]+$/, "", $2)
			print $2
			exit
		}
	' /proc/cpuinfo 2>/dev/null || :
}

# Print package names, one per line. Idempotent; caller dedupes.
setup_hw_packages()
{
	setup_pci=$(setup_hw_lspci)
	setup_cpu=$(setup_hw_cpu_vendor)

	# CPU microcode. Intel and AMD both want the matching early-load blob.
	case $setup_cpu in
		GenuineIntel) printf '%s\n' intel-ucode ;;
		AuthenticAMD) printf '%s\n' amd-ucode ;;
	esac

	# Always useful on real hardware; cheap no-op on a VM without blobs.
	printf '%s\n' linux-firmware mesa

	# GPUs. Nouveau is the live/install default for NVIDIA. The proprietary
	# stack is a separate yes/no in setup; we do not pull it in from here.
	if printf '%s\n' "$setup_pci" | grep -q 'VGA compatible controller.*\[10de:'; then
		printf '%s\n' nouveau
	fi
	if printf '%s\n' "$setup_pci" | grep -q '3D controller.*\[10de:'; then
		printf '%s\n' nouveau
	fi
	if printf '%s\n' "$setup_pci" | grep -q 'VGA compatible controller.*\[8086:'; then
		printf '%s\n' mesa
	fi
	if printf '%s\n' "$setup_pci" | grep -q 'VGA compatible controller.*\[1002:'; then
		printf '%s\n' mesa amd-ucode
	fi

	# Intel wireless (CNVi and the usual Wi-Fi class).
	if printf '%s\n' "$setup_pci" | grep -q 'Network controller.*\[8086:'; then
		printf '%s\n' iwd linux-firmware
	fi
	if printf '%s\n' "$setup_pci" | grep -q '\[0280\].*\[8086:'; then
		printf '%s\n' iwd linux-firmware
	fi

	# Broadcom / Realtek wireless: firmware plus iwd is enough to associate.
	if printf '%s\n' "$setup_pci" | grep -q 'Network controller.*\[14e4:'; then
		printf '%s\n' iwd linux-firmware
	fi
	if printf '%s\n' "$setup_pci" | grep -q 'Network controller.*\[10ec:'; then
		printf '%s\n' iwd linux-firmware
	fi

	# Wired Intel often just needs e1000e in the kernel; still pull firmware.
	if printf '%s\n' "$setup_pci" | grep -q 'Ethernet controller.*\[8086:'; then
		printf '%s\n' linux-firmware
	fi

	# Audio: PipeWire userspace is in the Plasma profiles; ALSA utils help
	# on a console box.
	if printf '%s\n' "$setup_pci" | grep -q 'Audio device'; then
		printf '%s\n' alsa-utils
	fi

	# NVMe / SATA management tools when those controllers are present.
	if printf '%s\n' "$setup_pci" | grep -q 'Non-Volatile memory controller'; then
		printf '%s\n' nvme-cli
	fi
	if printf '%s\n' "$setup_pci" | grep -q 'SATA controller'; then
		printf '%s\n' smartmontools
	fi
}

setup_hw_summary()
{
	setup_pci=$(setup_hw_lspci)
	setup_cpu=$(setup_hw_cpu_vendor)
	printf 'CPU vendor: %s\n' "${setup_cpu:-unknown}"
	printf '%s\n' "$setup_pci" | awk '
		/VGA compatible controller|3D controller|Network controller|Ethernet controller|Audio device|SATA controller|Non-Volatile memory/ {
			print
		}
	'
}
