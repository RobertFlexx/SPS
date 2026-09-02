#!/usr/bin/env python3
"""Write stock init scripts for every supported init, and ship systemd plus
OpenRC copies next to extra recipes that provide the daemon.

Supported inits: systemd, openrc, s6, runit, dinit, shepherd.
"""
from __future__ import annotations

import argparse
from pathlib import Path

SPS = Path(__file__).resolve().parents[1]
SV = SPS / "lib" / "setup" / "sv"
MAP = SPS / "lib" / "setup" / "services"

# package, rc, unit, wanted, runlevel, description, argv, flags
# flags: dbus, user, pre (list of shell lines for supervised run scripts)
SERVICES = [
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
    ("conntrack-tools", "conntrackd", "conntrackd.service", "multi-user.target", "default",
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
}


def sh_join(argv: list[str]) -> str:
    return " ".join(argv)


def scm_list(argv: list[str]) -> str:
    return " ".join(f'"{a}"' for a in argv)


def systemd_unit(svc: dict) -> str:
    after = ["network.target"]
    if svc["flags"].get("dbus"):
        after.append("dbus.service")
    lines = [
        "[Unit]",
        f"Description={svc['desc']}",
        f"After={' '.join(after)}",
        "",
        "[Service]",
        f"ExecStart={sh_join(svc['argv'])}",
    ]
    if svc["flags"].get("oneshot"):
        lines.append("Type=oneshot")
        lines.append("RemainAfterExit=yes")
    else:
        lines.append("Restart=on-failure")
    user = svc["flags"].get("user")
    if user:
        lines.append(f"User={user}")
    lines += ["", "[Install]", f"WantedBy={svc['wanted']}", ""]
    return "\n".join(lines)


def openrc_script(svc: dict) -> str:
    depend = ["    use net", "    after net"]
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
    lines.append(f"exec {sh_join(svc['argv'])}")
    lines.append("")
    return "\n".join(lines)


def dinit_file(svc: dict) -> str:
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


def update_map(services: list[dict]) -> None:
    existing = MAP.read_text(encoding="utf-8")
    lines = existing.rstrip() + "\n"
    have = set()
    for raw in existing.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        have.add(raw.split()[0])
    added = []
    for svc in services:
        row = f"{svc['pkg']}\t{svc['unit']}\t{svc['wanted']}\t{svc['rc']}\t{svc['level']}\n"
        if svc["pkg"] not in have:
            lines += row
            have.add(svc["pkg"])
            added.append(svc["pkg"])
        for alias, pkg in ALIASES.items():
            if pkg == svc["pkg"] and alias not in have:
                lines += (
                    f"{alias}\t{svc['unit']}\t{svc['wanted']}\t"
                    f"{svc['rc']}\t{svc['level']}\n"
                )
                have.add(alias)
                added.append(alias)
    MAP.write_text(lines, encoding="utf-8")
    return added


def find_recipe(tree: Path, name: str) -> Path | None:
    for recipe in tree.rglob("recipe"):
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


def install_recipe_files(tree: Path, services: list[dict]) -> list[str]:
    touched = []
    for svc in services:
        recipe = find_recipe(tree, svc["pkg"])
        if recipe is None:
            continue
        files = recipe.parent / "files"
        write_file(files / svc["unit"], systemd_unit(svc), 0o644)
        write_file(files / f"openrc-{svc['rc']}", openrc_script(svc), 0o755)
        text = recipe.read_text(encoding="utf-8")
        marker = f"$SRC/files/{svc['unit']}"
        if marker not in text:
            text = bump_release(text)
            if not text.endswith("\n"):
                text += "\n"
            text += (
                'install     mkdir -p "$PKG/usr/lib/systemd/system" "$PKG/etc/init.d"\n'
                f'install     install -m 0644 "$SRC/files/{svc["unit"]}" '
                f'"$PKG/usr/lib/systemd/system/{svc["unit"]}"\n'
                f'install     install -m 0755 "$SRC/files/openrc-{svc["rc"]}" '
                f'"$PKG/etc/init.d/{svc["rc"]}"\n'
            )
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
    print(f"map added: {', '.join(added) if added else '(none)'}")
    print(f"recipes updated: {len(touched)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
