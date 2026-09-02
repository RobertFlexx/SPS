#!/usr/bin/env python3
"""Write stock init scripts for every supported init, and ship a copy of
each script with the daemon recipe so pkin only has to enable.

Supported inits: systemd, openrc, s6, runit, dinit, shepherd, sysvinit.
"""
from __future__ import annotations

import argparse
from pathlib import Path

SPS = Path(__file__).resolve().parents[1]
SV = SPS / "lib" / "setup" / "sv"
MAP = SPS / "lib" / "setup" / "services"

# package, rc, unit, wanted, runlevel, description, argv, flags
# flags: dbus, user, pre, oneshot, prio
SERVICES = [
    ("dbus", "dbus", "dbus.service", "multi-user.target", "sysinit",
     "D-Bus system message bus",
     ["/usr/bin/dbus-daemon", "--system", "--nofork", "--nopidfile", "--nosyslog"],
     {"pre": ["mkdir -p /run/dbus /var/lib/dbus"]}),
    ("eudev", "udevd", "udevd.service", "sysinit.target", "sysinit",
     "eudev device manager",
     ["/usr/sbin/udevd"], {}),
    ("elogind", "elogind", "elogind.service", "multi-user.target", "sysinit",
     "elogind login manager",
     ["/usr/libexec/elogind"], {"dbus": True}),
    ("sddm", "sddm", "sddm.service", "graphical.target", "default",
     "Simple Desktop Display Manager",
     ["/usr/bin/sddm"], {"dbus": True}),
    ("networkmanager", "NetworkManager", "NetworkManager.service",
     "multi-user.target", "default",
     "NetworkManager",
     ["/usr/sbin/NetworkManager", "--no-daemon"], {"dbus": True}),
    ("openssh", "sshd", "sshd.service", "multi-user.target", "default",
     "OpenSSH daemon",
     ["/usr/sbin/sshd", "-D"],
     {"pre": ["if command -v ssh-keygen >/dev/null 2>&1; then ssh-keygen -A >/dev/null 2>&1 || :; fi"]}),
    ("cups", "cupsd", "cups.service", "multi-user.target", "default",
     "CUPS printing service",
     ["/usr/sbin/cupsd", "-f"], {"dbus": True}),
    ("bluez", "bluetooth", "bluetooth.service", "multi-user.target", "default",
     "Bluetooth daemon",
     ["/usr/libexec/bluetooth/bluetoothd"], {"dbus": True}),
    ("iwd", "iwd", "iwd.service", "multi-user.target", "default",
     "iNet wireless daemon",
     ["/usr/libexec/iwd"], {"dbus": True}),
    ("dhcpcd", "dhcpcd", "dhcpcd.service", "multi-user.target", "default",
     "DHCP client daemon",
     ["/usr/sbin/dhcpcd", "--nobackground"], {}),
    ("seatd", "seatd", "seatd.service", "multi-user.target", "default",
     "seat management daemon",
     ["/usr/bin/seatd", "-g", "video"], {}),
    ("power-profiles-daemon", "power-profiles-daemon",
     "power-profiles-daemon.service", "multi-user.target", "default",
     "Power profiles daemon",
     ["/usr/libexec/power-profiles-daemon"], {"dbus": True}),
    ("pipewire", "pipewire", "pipewire.service", "default.target", "default",
     "PipeWire multimedia server",
     ["/usr/bin/pipewire"], {"dbus": True}),
    ("wireplumber", "wireplumber", "wireplumber.service", "default.target",
     "default",
     "PipeWire session manager",
     ["/usr/bin/wireplumber"], {"dbus": True}),
    ("polkit", "polkitd", "polkit.service", "multi-user.target", "sysinit",
     "polkit authorization manager",
     ["/usr/libexec/polkitd", "--no-debug"], {"dbus": True}),
    ("cronie", "crond", "crond.service", "multi-user.target", "default",
     "cron daemon",
     ["/usr/sbin/crond", "-n"], {}),
    ("at", "atd", "atd.service", "multi-user.target", "default",
     "at job scheduler",
     ["/usr/sbin/atd", "-f"], {}),
    ("chrony", "chronyd", "chronyd.service", "multi-user.target", "default",
     "chrony NTP daemon",
     ["/usr/sbin/chronyd", "-d"], {}),
    ("haveged", "haveged", "haveged.service", "multi-user.target", "sysinit",
     "haveged entropy daemon",
     ["/usr/sbin/haveged", "-w", "1024", "-F"], {}),
    ("nginx", "nginx", "nginx.service", "multi-user.target", "default",
     "nginx HTTP server",
     ["/usr/bin/nginx", "-g", "daemon off;"], {}),
    ("caddy", "caddy", "caddy.service", "multi-user.target", "default",
     "Caddy HTTP server",
     ["/usr/bin/caddy", "run"], {}),
    ("redis", "redis", "redis.service", "multi-user.target", "default",
     "Redis data store",
     ["/usr/bin/redis-server", "--daemonize", "no"], {}),
    ("syncthing", "syncthing", "syncthing.service", "multi-user.target", "default",
     "Syncthing file synchronization",
     ["/usr/bin/syncthing", "serve", "--no-browser", "--home=/var/lib/syncthing"],
     {"pre": ["install -d -m 0755 /var/lib/syncthing || :"]}),
    ("wpa_supplicant", "wpa_supplicant", "wpa_supplicant.service",
     "multi-user.target", "default",
     "wpa_supplicant Wi-Fi client",
     ["/usr/sbin/wpa_supplicant", "-u", "-s"], {"dbus": True}),
    ("tlp", "tlp", "tlp.service", "multi-user.target", "default",
     "TLP laptop power management",
     ["/usr/sbin/tlp", "init", "start"], {"oneshot": True}),
    ("smartmontools", "smartd", "smartd.service", "multi-user.target", "default",
     "S.M.A.R.T. disk monitoring",
     ["/usr/sbin/smartd", "-n"], {}),
    ("upower", "upowerd", "upower.service", "multi-user.target", "default",
     "UPower power management",
     ["/usr/libexec/upowerd"], {"dbus": True}),
    ("transmission", "transmission-daemon", "transmission-daemon.service",
     "multi-user.target", "default",
     "Transmission BitTorrent daemon",
     ["/usr/bin/transmission-daemon", "-f", "--log-level=error"], {}),
    ("nftables", "nftables", "nftables.service", "multi-user.target", "sysinit",
     "nftables packet filter",
     ["/usr/sbin/nft", "-f", "/etc/nftables.conf"], {"oneshot": True}),
    ("fail2ban", "fail2ban", "fail2ban.service", "multi-user.target", "default",
     "fail2ban authentication ban daemon",
     ["/usr/bin/fail2ban-server", "-xf", "--logtarget=stdout"], {}),
    ("unbound", "unbound", "unbound.service", "multi-user.target", "default",
     "validating recursive DNS resolver",
     ["/usr/sbin/unbound", "-d"], {}),
    ("dnsmasq", "dnsmasq", "dnsmasq.service", "multi-user.target", "default",
     "DNS and DHCP server",
     ["/usr/sbin/dnsmasq", "-k"], {}),
    ("openvpn", "openvpn", "openvpn.service", "multi-user.target", "default",
     "OpenVPN server",
     ["/usr/sbin/openvpn", "--config", "/etc/openvpn/server.conf"], {}),
    ("tor", "tor", "tor.service", "multi-user.target", "default",
     "Tor anonymity daemon",
     ["/usr/bin/tor", "--RunAsDaemon", "0"], {}),
    ("dropbear", "dropbear", "dropbear.service", "multi-user.target", "default",
     "Dropbear SSH server",
     ["/usr/sbin/dropbear", "-F", "-E"],
     {"pre": ["if command -v dropbearkey >/dev/null 2>&1; then",
              "  mkdir -p /etc/dropbear",
              "  [ -f /etc/dropbear/dropbear_rsa_host_key ] || dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null",
              "fi"]}),
    ("tinyproxy", "tinyproxy", "tinyproxy.service", "multi-user.target", "default",
     "Tinyproxy HTTP proxy",
     ["/usr/bin/tinyproxy", "-d"], {}),
    ("haproxy", "haproxy", "haproxy.service", "multi-user.target", "default",
     "HAProxy load balancer",
     ["/usr/sbin/haproxy", "-f", "/etc/haproxy/haproxy.cfg", "-db"], {}),
    ("lighttpd", "lighttpd", "lighttpd.service", "multi-user.target", "default",
     "lighttpd web server",
     ["/usr/sbin/lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"], {}),
    ("avahi", "avahi-daemon", "avahi-daemon.service", "multi-user.target", "default",
     "Avahi mDNS/DNS-SD daemon",
     ["/usr/sbin/avahi-daemon", "--no-chroot"],
     {"dbus": True}),
    ("nfs-utils", "nfs-server", "nfs-server.service", "multi-user.target", "default",
     "NFS server",
     ["/usr/sbin/rpc.mountd", "-F"],
     {"pre": ["if command -v exportfs >/dev/null 2>&1; then exportfs -ra || :; fi",
              "if command -v rpc.statd >/dev/null 2>&1; then rpc.statd --no-notify || :; fi",
              "if command -v rpc.nfsd >/dev/null 2>&1; then rpc.nfsd 8 || :; fi"]}),
    ("libvirt", "libvirtd", "libvirtd.service", "multi-user.target", "default",
     "libvirt virtualization daemon",
     ["/usr/sbin/libvirtd"],
     {"dbus": True}),
    ("postgresql", "postgresql", "postgresql.service", "multi-user.target", "default",
     "PostgreSQL database server",
     ["/usr/bin/postgres", "-D", "/var/lib/postgres/data"],
     {"user": "postgres",
      "pre": ["install -d -m 0755 /run/postgresql /var/lib/postgres/data || :"]}),
    ("mariadb", "mariadbd", "mariadb.service", "multi-user.target", "default",
     "MariaDB database server",
     ["/usr/sbin/mariadbd", "--datadir=/var/lib/mysql"],
     {"user": "mysql",
      "pre": ["install -d -m 0750 /run/mysqld /var/lib/mysql || :"]}),
    ("memcached", "memcached", "memcached.service", "multi-user.target", "default",
     "memcached object cache",
     ["/usr/bin/memcached", "-u", "nobody"], {}),
    ("valkey", "valkey", "valkey.service", "multi-user.target", "default",
     "Valkey data store",
     ["/usr/bin/valkey-server", "--daemonize", "no", "--bind", "127.0.0.1"], {}),
    ("conntrack-tools", "conntrackd", "conntrackd.service", "multi-user.target",
     "default",
     "connection tracking daemon",
     ["/usr/sbin/conntrackd", "-C", "/etc/conntrackd/conntrackd.conf"], {}),
    ("usbmuxd", "usbmuxd", "usbmuxd.service", "multi-user.target", "default",
     "iOS USB multiplexing daemon",
     ["/usr/sbin/usbmuxd", "-f"], {}),
    ("distcc", "distccd", "distccd.service", "multi-user.target", "default",
     "distributed C/C++ compilation daemon",
     ["/usr/bin/distccd", "--no-detach", "--allow", "127.0.0.1", "--log-stderr"], {}),
    ("lxc", "lxc-net", "lxc-net.service", "multi-user.target", "default",
     "LXC bridge networking",
     ["/usr/libexec/lxc/lxc-net", "start"],
     {"oneshot": True}),
]

ALIASES = {
    "nfs-server": "nfs-utils",
    "libvirtd": "libvirt",
    "conntrackd": "conntrack-tools",
    "avahi-daemon": "avahi",
    "mariadbd": "mariadb",
    "distccd": "distcc",
    "lxc-net": "lxc",
    "sshd": "openssh",
    "cupsd": "cups",
    "bluetooth": "bluez",
    "NetworkManager": "networkmanager",
    "udevd": "eudev",
    "polkitd": "polkit",
    "crond": "cronie",
    "atd": "at",
    "chronyd": "chrony",
    "smartd": "smartmontools",
    "upowerd": "upower",
    "transmission-daemon": "transmission",
}


def sh_join(argv: list[str]) -> str:
    out = []
    for a in argv:
        if any(c in a for c in ' \t;"'):
            out.append("'" + a.replace("'", "'\\''") + "'")
        else:
            out.append(a)
    return " ".join(out)


def scm_list(argv: list[str]) -> str:
    return " ".join(f'"{a}"' for a in argv)


def systemd_unit(svc: dict) -> str:
    after = []
    if svc["level"] != "sysinit":
        after.append("network.target")
    if svc["flags"].get("dbus"):
        after.append("dbus.service")
    wanted = svc["wanted"]
    lines = [
        "[Unit]",
        f"Description={svc['desc']}",
    ]
    if after:
        lines.append(f"After={' '.join(after)}")
    lines += ["", "[Service]", f"ExecStart={sh_join(svc['argv'])}"]
    if svc["flags"].get("oneshot"):
        lines.append("Type=oneshot")
        lines.append("RemainAfterExit=yes")
    else:
        lines.append("Restart=on-failure")
    user = svc["flags"].get("user")
    if user:
        lines.append(f"User={user}")
    lines += ["", "[Install]", f"WantedBy={wanted}", ""]
    return "\n".join(lines)


def openrc_script(svc: dict) -> str:
    depend = ["    use net", "    after net"]
    if svc["level"] == "sysinit":
        depend = ["    need localmount"]
    if svc["flags"].get("dbus"):
        depend = ["    need dbus", "    after dbus"]
    pre = svc["flags"].get("pre") or []
    user = svc["flags"].get("user")
    body = [
        "#!/sbin/openrc-run",
        f'description="{svc["desc"]}"',
        f'command="{svc["argv"][0]}"',
        f'command_args="{" ".join(svc["argv"][1:])}"',
    ]
    if svc["flags"].get("oneshot"):
        body.append('command_background="no"')
    else:
        body.extend([
            'command_background="yes"',
            f'pidfile="/run/{svc["rc"]}.pid"',
        ])
    if user:
        body.append(f'command_user="{user}"')
    body.append("")
    body.append("depend() {")
    body.extend(depend)
    body.append("}")
    if pre:
        body.append("")
        body.append("start_pre() {")
        body.extend(f"\t{line}" for line in pre)
        body.append("}")
    body.append("")
    return "\n".join(body)


def supervised_run(svc: dict) -> str:
    lines = ["#!/bin/sh", "exec 2>&1"]
    for line in svc["flags"].get("pre") or []:
        lines.append(line)
    if svc["flags"].get("oneshot"):
        lines.append(f"{sh_join(svc['argv'])}")
        lines.append("exec pause")
    else:
        lines.append(f"exec {sh_join(svc['argv'])}")
    lines.append("")
    return "\n".join(lines)


def dinit_file(svc: dict) -> str:
    if svc["flags"].get("oneshot"):
        lines = [
            "type = script",
            f"command = {sh_join(svc['argv'])}",
            "restart = false",
        ]
    else:
        lines = [
            "type = process",
            f"command = {sh_join(svc['argv'])}",
            "restart = true",
            "smooth-recovery = true",
        ]
    if svc["flags"].get("dbus"):
        lines.append("depends-on = dbus")
    lines.append("")
    return "\n".join(lines)


def shepherd_file(svc: dict) -> str:
    req = "'(dbus)" if svc["flags"].get("dbus") else "'()"
    return (
        "(use-modules (shepherd service))\n"
        "(register-services\n"
        " (list (service\n"
        f"        '({svc['rc']})\n"
        f"        #:requirement {req}\n"
        f"        #:documentation \"{svc['desc']}\"\n"
        f"        #:start (make-forkexec-constructor '({scm_list(svc['argv'])}))\n"
        "        #:stop (make-kill-destructor)\n"
        "        #:respawn? #t)))\n"
    )


def sysvinit_script(svc: dict) -> str:
    if svc["level"] == "sysinit":
        start, stop = "S", ""
    else:
        start, stop = "2 3 4 5", "0 1 6"
    req = "$remote_fs"
    if svc["flags"].get("dbus"):
        req = "$remote_fs dbus"
    args = " ".join(svc["argv"][1:])
    user = svc["flags"].get("user") or ""
    pre = svc["flags"].get("pre") or []
    oneshot = bool(svc["flags"].get("oneshot"))
    lines = [
        "#!/bin/sh",
        "### BEGIN INIT INFO",
        f"# Provides:          {svc['rc']}",
        f"# Required-Start:    {req}",
        f"# Required-Stop:     {req}",
        f"# Default-Start:     {start}",
        f"# Default-Stop:      {stop}",
        f"# Short-Description: {svc['desc']}",
        "### END INIT INFO",
        "",
        "if [ -f /etc/rc.d/init.d/functions ]; then",
        "	. /etc/rc.d/init.d/functions",
        "elif [ -f /etc/init.d/functions ]; then",
        "	. /etc/init.d/functions",
        "fi",
        "",
        f"NAME={svc['rc']}",
        f'DAEMON="{svc["argv"][0]}"',
        f'DAEMON_ARGS="{args}"',
        f'PIDFILE="/run/{svc["rc"]}.pid"',
        f'USER="{user}"',
        "",
        "start() {",
    ]
    for line in pre:
        lines.append(f"	{line}")
    if oneshot:
        lines.append('	eval "$DAEMON" $DAEMON_ARGS')
        lines.append("	return $?")
    else:
        lines.append('	start_daemon -p "$PIDFILE" ${USER:+-c "$USER"} "$DAEMON" $DAEMON_ARGS')
    lines += [
        "}",
        "",
        "stop() {",
    ]
    if oneshot:
        lines.append("	return 0")
    else:
        lines.append('	killproc -p "$PIDFILE" "$DAEMON"')
    lines += [
        "}",
        "",
        "status() {",
        '	pidofproc -p "$PIDFILE" "$DAEMON"',
        "}",
        "",
        'case $1 in',
        "	start) start ;;",
        "	stop) stop ;;",
        "	restart) stop; start ;;",
        "	status) status ;;",
        '	*) printf \'%s\\n\' "Usage: $0 {start|stop|restart|status}" >&2; exit 1 ;;',
        "esac",
        "",
    ]
    return "\n".join(lines)


def write_file(path: Path, text: str, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)


def parse_services() -> list[dict]:
    out = []
    for pkg, rc, unit, wanted, level, desc, argv, flags in SERVICES:
        out.append({
            "pkg": pkg, "rc": rc, "unit": unit, "wanted": wanted,
            "level": level, "desc": desc, "argv": argv, "flags": flags,
        })
    return out


def write_stock(services: list[dict]) -> None:
    for svc in services:
        write_file(SV / "systemd" / svc["unit"], systemd_unit(svc), 0o644)
        write_file(SV / "openrc" / svc["rc"], openrc_script(svc), 0o755)
        write_file(SV / "runit" / svc["rc"] / "run", supervised_run(svc), 0o755)
        write_file(SV / "s6" / svc["rc"] / "run", supervised_run(svc), 0o755)
        write_file(SV / "dinit" / svc["rc"], dinit_file(svc), 0o644)
        write_file(SV / "shepherd" / f"{svc['rc']}.scm", shepherd_file(svc), 0o644)
        write_file(SV / "sysvinit" / svc["rc"], sysvinit_script(svc), 0o755)


def update_map(services: list[dict]) -> list[str]:
    header = (
        "# package  systemd-unit  wanted-by  rc-name  runlevel\n"
        "# Scripts for every init live in lib/setup/sv and are also shipped\n"
        "# in the daemon recipe (systemd, OpenRC, runit, s6, dinit,\n"
        "# Shepherd, SysV). pkin enables the detected target init.\n"
    )
    rows = []
    have = set()
    added = []

    def add_row(name: str, svc: dict) -> None:
        if name in have:
            return
        rows.append(
            f"{name}\t{svc['unit']}\t{svc['wanted']}\t{svc['rc']}\t{svc['level']}\n"
        )
        have.add(name)
        added.append(name)

    for svc in services:
        add_row(svc["pkg"], svc)
        for alias, pkg in ALIASES.items():
            if pkg == svc["pkg"]:
                add_row(alias, svc)
    MAP.write_text(header + "".join(rows), encoding="utf-8")
    return added


def find_recipe(tree: Path, name: str) -> Path | None:
    for recipe in tree.rglob("recipe"):
        if ".git" in recipe.parts:
            continue
        try:
            for line in recipe.read_text(encoding="utf-8").splitlines():
                if line.startswith("name"):
                    rec_name = line.split(None, 1)[1].strip()
                    if rec_name == name:
                        return recipe
                    break
        except OSError:
            continue
    return None


def bump_release(text: str) -> str:
    out = []
    done = False
    for line in text.splitlines(keepends=True):
        if not done and line.startswith("release"):
            parts = line.split(None, 1)
            try:
                rel = int(parts[1].strip())
            except (IndexError, ValueError):
                rel = 1
            line = f"release     {rel + 1}\n"
            done = True
        out.append(line)
    return "".join(out)


def recipe_install_block(svc: dict) -> str:
    rc = svc["rc"]
    unit = svc["unit"]
    return (
        'install     mkdir -p "$PKG/usr/lib/systemd/system" "$PKG/etc/init.d" '
        f'"$PKG/etc/sv/{rc}" "$PKG/etc/s6/sv/{rc}" '
        '"$PKG/etc/dinit.d" "$PKG/etc/shepherd.d" "$PKG/etc/rc.d/init.d"\n'
        f'install     install -m 0644 "$SRC/files/{unit}" '
        f'"$PKG/usr/lib/systemd/system/{unit}"\n'
        f'install     install -m 0755 "$SRC/files/openrc-{rc}" '
        f'"$PKG/etc/init.d/{rc}"\n'
        f'install     install -m 0755 "$SRC/files/runit-{rc}" '
        f'"$PKG/etc/sv/{rc}/run"\n'
        f'install     install -m 0755 "$SRC/files/s6-{rc}" '
        f'"$PKG/etc/s6/sv/{rc}/run"\n'
        f'install     install -m 0644 "$SRC/files/dinit-{rc}" '
        f'"$PKG/etc/dinit.d/{rc}"\n'
        f'install     install -m 0644 "$SRC/files/shepherd-{rc}.scm" '
        f'"$PKG/etc/shepherd.d/{rc}.scm"\n'
        f'install     install -m 0755 "$SRC/files/sysvinit-{rc}" '
        f'"$PKG/etc/rc.d/init.d/{rc}"\n'
    )


def install_recipe_files(tree: Path, services: list[dict]) -> list[str]:
    touched = []
    for svc in services:
        recipe = find_recipe(tree, svc["pkg"])
        if recipe is None:
            continue
        files = recipe.parent / "files"
        rc = svc["rc"]
        write_file(files / svc["unit"], systemd_unit(svc), 0o644)
        write_file(files / f"openrc-{rc}", openrc_script(svc), 0o755)
        write_file(files / f"runit-{rc}", supervised_run(svc), 0o755)
        write_file(files / f"s6-{rc}", supervised_run(svc), 0o755)
        write_file(files / f"dinit-{rc}", dinit_file(svc), 0o644)
        write_file(files / f"shepherd-{rc}.scm", shepherd_file(svc), 0o644)
        write_file(files / f"sysvinit-{rc}", sysvinit_script(svc), 0o755)
        text = recipe.read_text(encoding="utf-8")
        marker = f"$SRC/files/sysvinit-{rc}"
        if marker not in text:
            text = bump_release(text)
            if not text.endswith("\n"):
                text += "\n"
            text += recipe_install_block(svc)
            recipe.write_text(text, encoding="utf-8")
        touched.append(str(recipe))
    return touched


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--extra", default="/tmp/sps-extra",
                    help="extra recipe tree (default: /tmp/sps-extra)")
    ap.add_argument("--core", default="", help="optional core recipe tree")
    args = ap.parse_args()
    services = parse_services()
    write_stock(services)
    added = update_map(services)
    extra = Path(args.extra)
    touched = []
    if extra.is_dir():
        touched.extend(install_recipe_files(extra, services))
    if args.core:
        core = Path(args.core)
        if core.is_dir():
            touched.extend(install_recipe_files(core, services))
    print(f"stock services: {len(services)}")
    print(f"map rows written: {len(added)}")
    print(f"recipes updated: {len(touched)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
