# SPS 1.0 formats and behavior

This file documents the interfaces that packages and distro tooling can depend
on in SPS 1.0.

Package metadata, indexes, and installed records are meant to be inspectable
and scriptable.

The current package format is `format 1`. If a later SPS release needs an
incompatible package layout, it must use a new format number.

## Recipe format

A recipe is a line-oriented file named `recipe`. Each logical line is a key,
whitespace, then a value. A trailing backslash continues the value on the next
physical line. Blank lines and lines beginning with `#` are ignored.

Required metadata fields:

```text
name
version
release
```

`arch` is optional and defaults to the configured architecture. Use `any` for
architecture-independent packages. `noarch` is accepted as a compatibility
spelling, but official recipes use `any`.

Repeatable metadata fields:

```text
source
hash
depend
builddep
optional
conflict
```

`conflict` names packages that must not be installed together. `sget install`
refuses a transaction that contains both a package and one of its conflicts,
and also refuses to install a package that conflicts with something already
in the database. `src update` still validates the whole graph; two packages
that conflict may both exist in the repository.

`description` is a single-value field.

Build phases are repeatable command fields:

```text
prepare
configure
build
install
```

At least one `install` command is required, and it must produce a non-empty
staged payload. Reading recipe metadata never executes phase commands.

`mkpkg` runs each phase with `/bin/sh -eu`, starting in `$WORK`. It exports
`PKG` as the staging root, `SRC` as the acquired-source directory, `WORK` as the
extracted source root, and `MAKEJOBS` as a positive integer. Phase commands
must install below `$PKG`, never directly into the live root.

Hashes correspond to sources in declaration order and use this form:

```text
sha256:64_HEX_DIGITS
```

Every declared source is verified. There is no checksum-skip value.

A recipe directory may also contain real `files/`, `patches/`, and `hooks/`
directories. Their entries must be ordinary directories or regular files;
symlinks, special files, and paths containing tabs or newlines are rejected.
`files/` and `patches/` are copied to `$SRC/files` and `$SRC/patches` and are
not applied or installed automatically. The only hook names accepted by 1.0
are:

```text
pre-install
post-install
pre-remove
post-remove
```

Hook entries must be regular files, not symlinks.

`pkin` always attempts to enable a mapped service after a successful
post-install. The map is `$SPS_LIBDIR/setup/services`. The init name is
read from `$SPS_ROOT/etc/sps/init`. Supported names are `systemd`,
`openrc`, `s6`, `runit`, `dinit`, and `shepherd`. When the package did
not ship a file for that init, a stock script is copied from
`$SPS_LIBDIR/setup/sv/<init>/` and then enabled. Unknown packages and
`init` set to `none` are no-ops.

`setup --init` installs the matching `init-*` metapackage, drops
conflicting PID 1 packages from the plan, writes `/etc/sps/init` and
`/etc/sps/sps.conf` before the first `sget`, and enables every mapped
service that is present (or can be filled from stock scripts).

## Repository index

Indexes live under `$SPS_CACHE/indexes`. Each package record is tab-separated
and contains:

```text
name version release arch depends builddeps optional repo priority recipe_path description definition_sha256 conflicts
```

`conflicts` is empty when the recipe has no `conflict` records. Older 12-field
index files are still accepted; missing conflicts are treated as none.

Dependency lists are comma-separated. Field values may not contain tabs or
newlines. The definition digest covers the recipe content and the relative
paths, contents, and copied modes of its `files/`, `patches/`, and `hooks/`
inputs, so a changed support file invalidates the index as well as a changed
recipe. Recipe-only packages hash the same two-line manifest; `src update`
batches those file hashes and then applies that manifest, so the digest
matches the per-package hasher.

When more than one configured repository supplies the same package, SPS picks
the highest numeric priority. Configuration order breaks equal priorities. A
duplicate package name within one repository is an error; categories are not
part of package identity.

Repository declarations are `git NAME SOURCE [PRIORITY]` or
`dir NAME ABSOLUTE_PATH [PRIORITY]`. `repo` is accepted as a compatibility
alias for `dir`. Git checkouts live below `$SPS_REPO_ROOT`, defaulting to
`/usr/src/sps`, while directory repositories stay at their configured paths.

`src update` clones an absent Git checkout, fetches an existing clean checkout,
and fast-forwards only when its configured upstream is a descendant of `HEAD`.
It leaves detached heads, branches without an `origin` upstream, and locally
ahead branches pinned. Dirty, divergent, mismatched-origin, or invalid
checkouts are refused without reset or cleanup. After synchronization, `src`
validates recipes, same-repository uniqueness, and the selected runtime/build
dependency graph before atomically replacing the local index.

## Binary package format

An SPS package is a tar archive, optionally compressed with gzip, xz, or zstd.
Archive member names are relative to the target root.

Control data lives in `.SPS/`:

```text
.SPS/meta
.SPS/files
.SPS/hashes
.SPS/hooks/       optional
usr/...
etc/...
```

`.SPS/meta` contains at least:

```text
format 1
definition_sha256 VALUE
name VALUE
version VALUE
release VALUE
arch VALUE
```

`definition_sha256` binds a built artifact to the indexed recipe and its
support files. `sget` rebuilds a cached artifact when this digest is absent or
does not match, even when name, version, and release are unchanged.

`.SPS/files` is a sorted list of normalized payload paths. Directory entries
end in `/`.

`.SPS/hashes` contains one record for each regular file:

```text
sha256<TAB>digest<TAB>path
```

Before committing installed metadata, `pkin` rejects malformed control files,
absolute or traversing paths, unsupported control members, unsafe symlink
parents, manifest/archive mismatches, and bad payload hashes.

Packages marked `any` can be installed on any architecture. `noarch` is
accepted as a compatibility spelling. Other package architectures must match
`SPS_ARCH` exactly.

## Lifecycle hooks

Hooks are stored in the package and run with `/bin/sh -eu`.

The hook environment includes normal SPS configuration plus:

```text
SPS_ACTION=install|upgrade|remove
SPS_PACKAGE=name
SPS_VERSION=version
SPS_RELEASE=release
SPS_PACKAGE_ARCH=arch
```

`SPS_RELEASE` and `SPS_PACKAGE_ARCH` apply to install and upgrade hooks.

A failing pre-hook stops the requested payload change. A failing post-hook
returns status 10 after the package database operation has already committed.
The history entry still records the operation that actually happened.

## Installed database

Installed package records live at:

```text
$SPS_DB/installed/NAME/
```

A record contains `meta`, `files`, `hashes`, and optional `hooks/`.

Other database files are:

```text
$SPS_DB/owners    path<TAB>package for managed non-directory paths
$SPS_DB/world     one explicit package name per line
$SPS_DB/history   append-only human-readable operation log
```

Writers create temporary siblings and rename them into place. Low-level package
writers use `$SPS_DB/.lock`. State-changing `sget` operations also use
`$SPS_DB/.transaction` so a dependency operation cannot interleave with
another high-level dependency operation.

Read-only queries and plans do not take the high-level transaction lock.

A lock is considered stale only when it contains a numeric PID that can be
verified as no longer running. SPS does not remove an unreadable or malformed
lock on a guess.

Database-file replacement is atomic. Installation of an entire package payload
is not, and SPS does not claim whole-root filesystem atomicity.

## Explicit packages and dependencies

`world` is the set of explicit roots.

`pkin --explicit` and `pkmark explicit` add a package to it. `pkin --dependency`
and `pkmark dependency` leave or remove a package from it without uninstalling
the package.

`pkstat --orphans` walks installed runtime dependencies starting from `world`.
Any dependency-installed package that cannot be reached from an explicit root
is reported as an orphan.

## File ownership and conflicts

A managed non-directory path has one SPS owner. `pkin` checks both the owner
index and the target filesystem before writing a payload entry.

An existing unowned file is a conflict unless it is already identical to the
payload: the same symlink target, or a regular file with the same SHA-256
digest. Identical paths are adopted so a live image can install `filesystem`
over usr-merge links it already created.

A different digest still fails on an ordinary system. On a live image
(`$SPS_ROOT/etc/sps/live`), `pkin` replaces an unowned regular file or
symlink with the packaged leaf so host copies such as `/usr/bin/openssl`
and busybox applets such as `/usr/bin/clear` can be claimed by their
packages. Paths under `SPS_PRESERVE` are not overwritten this way. On a live
image, an unowned preserved file (typically host-seeded `/etc/ssl`) is kept
as-is, the package takes ownership, and a differing packaged default is
written beside it as `.sps-new`. The live shell and init (`bin/sh`,
`sbin/init`, `busybox`), and the usr-merge names `bin`, `sbin`, `lib`,
and `lib64` are not replaced this way. A different usr-merge symlink
target remains a conflict.

Shared directories include real directories and conservative in-root
directory symlinks: usr-merge `bin`, `sbin`, `lib`, and `lib64` when they
point at the matching `usr/*` directory, and filesystem compat links
`var/run` -> `../run` and `var/lock` -> `../run/lock`. A package may install
files below `/lib` or `/var/run` without replacing those links. Existing
shared directories are not re-owned or chmodded just because another package
contains the same directory entry.

When installation runs as uid 0, newly installed regular payload files and new
package directories are normalized to uid/gid 0 while retaining their packaged
permission modes.

## Protected files

`SPS_PRESERVE` is a comma-separated list of package-relative path prefixes. The
default is `etc`. Set it to `none` to disable this behavior.

For a protected regular file that differs from the hash recorded by the
installed package:

- removal leaves the local file in place and drops SPS ownership;
- upgrade leaves the local file in place;
- if the new package also changed that file, its copy is written beside the
  local file as `.sps-new`, or as `.sps-new.VERSION-RELEASE` if needed to avoid
  a collision.

SPS reports the situation and leaves merging to the administrator.

## Binary package cache

`sget` stores completed package artifacts under `$SPS_CACHE/packages`.

An exact name/version/release/architecture package may be reused instead of
being rebuilt. The cached archive's embedded package identity is checked before
it is trusted.

If a distribution changes build inputs or package behavior without changing
the upstream version, it must bump the package release.

## Dependency resolution

Runtime and build dependencies form a directed graph. `sget` computes a stable
topological order and rejects missing dependencies and cycles.

`sget install` resolves the runtime closure first. Build dependencies are added
only for packages that will actually be compiled (not already installed at the
selected version, and not a usable cached archive). Well-known build tools
already on `PATH` (`cmake`, `ninja`, `meson`, `patch`, `pkgconf`, `gperf`,
`python`, `go`, `rust`) are used in place of those packages when they are not
themselves a runtime requirement. That is why `fastfetch` does not install
`cmake` or `openssl` on a live image that already has cmake.

`sget depends --build` still shows the full declared build graph.

`sget upgrade` starts with the explicit `world` set and resolves its selected
dependency closure. `sget dependees` shows reverse dependencies. `sget why`
shows one dependency path between two selected packages.

`pkin` and `pkdel` do no dependency solving.
