# SPS Source Package System

SPS is a source package system for small, administrator-run Unix-like systems.
It is made from separate command-line tools, plain text state, POSIX shell,
POSIX AWK, and normal tar archives.

The layout is influenced by CRUX and older Unix package tools, but SPS is not a
CRUX compatibility project. It has its own recipes, package metadata, repository
index, dependency handling, commands, and upgrade rules.

If you REALLY want the project rationale and the boundaries of the design, read
[MANIFESTO.md](MANIFESTO.md). The exact 1.0 file formats and behavior are in
[DESIGN.md](DESIGN.md).

## SPS is not the distro

SPS is the source package system. It is not locked to one operating system.
You can run `src`, `sget`, `mkpkg`, `pkin`, and the rest on Linux From Scratch,
on a custom chroot, or next to another distro's userland. Recipes are plain
text; an LFS tree can consume sps-core and sps-extra the same way SPS Linux
does.

**SPS Linux** is a Linux distribution that *uses* SPS. Informally it is called
**Splux**. Official installer flow, live ISOs, Plasma profiles, and the
`linux-desktop` kernel are SPS Linux pieces. They live in this tree and in
the core/extra collections because that is how Splux is built and installed.

If you take SPS into an LFS (or any other) project, do not assume `setup`
will do the right thing for you. The installer partitions disks, writes
fstab, chooses systemd or OpenRC, copies a Splux hostname, and installs
distro profiles. Your LFS book already has its own disk, boot, and
configuration story. Use `sget` and `mkpkg` there; skip `setup` and `mkiso`
unless you actually want SPS Linux on that machine.

## Tools

SPS is a set of tools rather than one large front end:

- `src` indexes and queries source repositories.
- `sget` handles dependency-aware installs, upgrades, removals, and queries.
- `mkpkg` builds a binary package from a recipe.
- `pkin` installs or upgrades one binary package.
- `pkdel` removes one installed package.
- `pkstat` reads the installed package database (`pkstat --count` prints
  the number of installed packages).
- `pkcheck` checks installed files and database consistency.
- `pkmark` changes whether an installed package is explicit or dependency-only.
- `setup` is the SPS Linux (Splux) dialog(1) installer (Slackware/FreeBSD
  style). Optional; other projects using SPS do not need it.
- `mkiso` builds an SPS Linux live ISO (systemd by default; busybox init if
  systemd is not on the build host) you can flash and boot into `setup`.

The split matters. `pkin` does not search repositories. `pkdel` does not solve
dependencies. `src` does not install anything. `sget` ties the lower-level tools
together when you want the usual package-manager workflow.

# Below is info on installing the package manager elsewhere, not Splux itself.
----------------------------
## Requirements

SPS does not compile into a binary. The core needs a POSIX `sh`, a POSIX `awk`,
and a fairly normal Unix userland:

```text
tar find sort sed grep comm cmp cp mv rm mkdir ls mktemp
```

A SHA-256 tool is also required. `sha256sum`, `sha256`, `shasum`, and `openssl`
are supported where available.

`git` is required only when a `git` repository is configured. Local `dir`
repositories can be indexed without it.

Compression support depends on the package or source being used. Install
`gzip`, `xz`, or `zstd` if you want those formats. Remote HTTP or HTTPS sources
need `curl` or `wget` when building.

## Test it

```sh
make check
```

The tests use temporary roots. They cover repository selection, dependency
ordering, package creation, install and removal, upgrades, file ownership,
protected configuration files, hooks, package compression, the installed
layout, locks, architecture checks, and hostile archive/database cases.

## Install it

For packaging into a staging root:

```sh
make DESTDIR="$pkgdir" PREFIX=/usr install
make DESTDIR="$pkgdir" install-config
```

For a direct system install:

```sh
sudo make PREFIX=/usr install
sudo make install-config
```

`install-config` leaves existing `sps.conf` and `repos.conf` alone. A
distribution can skip it and ship its own configuration instead.

## Set up repositories

Official repositories are ordinary Git checkouts managed by `src`. Local
administrator trees use the same recipe format and need no transport layer.
Put this in `/etc/sps/repos.conf`:

```text
dir local /usr/local/src/sps-local 200
git core https://github.com/RobertFlexx/sps-core.git 100
git extra https://github.com/RobertFlexx/sps-extra.git 80
```

Then synchronize Git checkouts and build the local index:

```sh
src update
src search shell
sget info bash
```

Git repositories are cloned below `/usr/src/sps` by default, so the example
uses `/usr/src/sps/core` and `/usr/src/sps/extra`. `src update` fetches and
fast-forwards clean tracking branches, but never resets, cleans, or overwrites
a checkout with local changes. The checkouts remain normal Git repositories;
`git status`, `git log`, and `git diff` work as usual. A `dir` repository is
never synchronized by SPS.

## Normal use

The high-level interface is `sget`:

```sh
sget install neovim
sget upgrade --plan
sget upgrade
sget depends firefox
sget dependees openssl
sget why firefox libxml2
sget remove neovim
```

`sget install` prints each package as it begins, then leaves `mkpkg` and the
upstream build attached to the terminal. An exact cached archive is reused
instead of rebuilding.

The lower-level tools are always available:

```sh
mkpkg /usr/local/src/sps-local/base/foo/recipe
pkin foo-1.0-1-x86_64.pkg.tar.zst
pkstat foo
pkcheck foo
pkdel foo
```

This is useful for recovery work, distro installers, package development, and
cases where the administrator wants to bypass dependency policy on purpose.

## Install SPS Linux (Splux)

`setup` is the **SPS Linux** installer, not a generic SPS or LFS installer.
It uses `dialog` screens, or the same choices from flags for scripts:

```sh
setup
setup --plan --profile plasma-desktop --target /mnt --user alex
setup --non-interactive --profile minimal --target /mnt --hostname darkstar
```

Profiles are `minimal`, `server`, `plasma-desktop`, and `plasma-full`. Optional
sets cover CLI tools, development, languages, KDE apps, NVIDIA, Flatpak, power
management, multimedia, printing, browsers, extra shells, fonts, office tools,
SSH, and more. `setup --list-sets` prints them. There is also an extra-package
checklist (`--extra`) plus locale and login-shell screens.

The installer writes hostname, timezone, keymap, and a first user into the
target, then runs `src update` and `sget install`. Guided partitioning is
optional and waits until the last confirmation. Choose systemd or OpenRC
as PID 1 (`--init`); those packages conflict. `grub-install` still needs
`--install-bootloader` and `--disk`.

## SPS Linux live ISO

`mkiso` writes a hybrid ISO for SPS Linux (Splux). Flash it to USB, boot to a
console, mount a destination filesystem on `/mnt`, and run `setup`. Ready-made
images:

https://github.com/RobertFlexx/SPS/releases/tag/live-2026-08-31-2

```sh
mkiso --output dist/sps-live.iso --init systemd \
  --busybox /path/to/busybox \
  --core /usr/src/sps/core \
  --extra /usr/src/sps/extra

make iso
make iso-slim
make iso-plasma
```

Live PID 1 is systemd when the build host has it, otherwise busybox init
with gettys on tty1 and ttyS0. The earlier live TTY image exec'd a shell
as PID 1 and panicked in QEMU (`Attempted to kill init`, exit 127) when
that shell exited. `--session plasma` copies a host Plasma/Wayland stack;
NVIDIA live graphics go through nouveau.

`--layout DIR` writes the live root without making an ISO. `--no-seed` skips
copying the host compiler. `--with-firmware` copies `/lib/firmware` (large;
published images omit it). The live image never runs `grub-install` on a disk.

Download a ready-made hybrid ISO from this repository's GitHub Releases, flash
it to USB, boot the "SPS Linux live (Splux)" entry, mount a destination
filesystem on `/mnt`, and run `setup`. The image includes the installer,
sps-core and sps-extra recipes, and a host seed compiler so `setup` can build
packages. A full Plasma install compiles Qt and KDE from source and takes a
long time.

```sh
# flash (example)
dd if=sps-live-tty.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

## Alternate roots

`SPS_ROOT` points SPS at another filesystem tree. Database, cache, and build
paths are rooted below it unless you override those paths separately.

For example:

```sh
SPS_ROOT=/mnt/root pkin base-1.0-1-x86_64.pkg.tar.zst
```

That makes SPS usable from an installer or rescue system without needing a
special package-install mode.

## Upgrades and configuration files

By default, regular files below `etc` are protected when an administrator has
changed them locally. During an upgrade SPS keeps the local file. If the new
package also changed its copy, the new one is written beside it as `.sps-new`
(or a versioned `.sps-new` name if necessary).

SPS never attempts to merge the two files automatically.

`pkin` is still a direct installer. `sget upgrade` starts from the explicit
`world` set, resolves that dependency closure, and upgrades it in dependency
order. A locally newer version is kept unless `--downgrade` is requested.

## Hooks

A recipe may ship these files in a `hooks/` directory:

```text
pre-install
post-install
pre-remove
post-remove
```

They are copied into the package and can be inspected before installation.
Hooks run with `/bin/sh -eu`. There is no generic plugin loader or background
trigger service.

Use hooks sparingly. Most packages should just install files.

## Files and state

The defaults are:

```text
/etc/sps/       configuration
/var/lib/sps/   installed records, ownership, world, history
/var/cache/sps/ sources, repository indexes, built packages
/var/tmp/sps/   build and staging directories
```

Package state is text. Binary packages are tar archives, optionally compressed
with gzip, xz, or zstd.

Nothing in SPS needs a daemon or a database server, and no command refreshes a
repository in the background. If you do not run a state-changing command, SPS
does not change the system. Its intentionally minimal ;)
