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

## Tools

SPS is a set of tools rather than one large front end:

- `src` indexes and queries source repositories.
- `sget` handles dependency-aware installs, upgrades, removals, and queries.
- `mkpkg` builds a binary package from a recipe.
- `pkin` installs or upgrades one binary package.
- `pkdel` removes one installed package.
- `pkstat` reads the installed package database.
- `pkcheck` checks installed files and database consistency.
- `pkmark` changes whether an installed package is explicit or dependency-only.

The split matters. `pkin` does not search repositories. `pkdel` does not solve
dependencies. `src` does not install anything. `sget` ties the lower-level tools
together when you want the usual package-manager workflow.

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
