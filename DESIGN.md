# SPS 1.0 formats and behavior

This file documents the interfaces that packages and distro tooling can depend
on in SPS Package metadata,
indexes, and installed records are meant to be inspectable and scriptable.

The current package format is `format 1`. If a later SPS release needs an
incompatible package layout, it must use a new format number.

## Recipe format

A recipe is a line-oriented file named `recipe`. Each logical line is a key,
whitespace, then a value. A trailing backslash continues the value on the next
physical line. Blank lines and lines beginning with `#` are ignored.

Required fields:

```text
name
version
release
```

`arch` is optional and defaults to the configured architecture.

Repeatable metadata fields:

```text
source
hash
depend
builddep
optional
```

`description` is a single-value field.

Build phases are repeatable command fields:

```text
prepare
configure
build
install
```

Reading recipe metadata never executes those commands.

Hashes correspond to sources in declaration order and use this form:

```text
sha256:HEX
```

`skip` is accepted only when `mkpkg` is run with its explicit insecure checksum
override.

A recipe directory may also contain `files/`, `patches/`, and `hooks/`. The
only hook names accepted by 1.0 are:

```text
pre-install
post-install
pre-remove
post-remove
```

Hook entries must be regular files, not symlinks.

## Repository index

Indexes live under `$SPS_CACHE/indexes`. The first line identifies the schema.
Each package record after that is tab-separated and contains:

```text
name version release arch depends builddeps optional repo priority recipe_path description recipe_sha256
```

Dependency lists are comma-separated. Field values may not contain tabs or
newlines.

When more than one configured repository supplies the same package, SPS picks
the highest numeric priority. Configuration order breaks equal priorities,
then lexical recipe path breaks any remaining tie. The result is deterministic.

`src update` indexes local directories. Moving repository data onto the machine
is outside the SPS package format and is left to the distribution.

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
name VALUE
version VALUE
release VALUE
arch VALUE
```

`.SPS/files` is a sorted list of normalized payload paths. Directory entries
end in `/`.

`.SPS/hashes` contains one record for each regular file:

```text
sha256<TAB>digest<TAB>path
```

Before committing installed metadata, `pkin` rejects malformed control files,
absolute or traversing paths, unsupported control members, unsafe symlink
parents, manifest/archive mismatches, and bad payload hashes.

Packages marked `any` or `noarch` can be installed on any architecture. Other
package architectures must match `SPS_ARCH`.

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

An existing unowned file is a conflict. SPS does not silently claim it.

Directories are shared and are not stored in the exclusive owner index.
Existing shared directories are not re-owned or chmodded just because another
package contains the same directory entry.

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

`sget upgrade` starts with the explicit `world` set and resolves its selected
dependency closure. `sget dependees` shows reverse dependencies. `sget why`
shows one dependency path between two selected packages.

`pkin` and `pkdel` do no dependency solving.
