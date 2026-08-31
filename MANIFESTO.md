# SPS Source Package System

## What SPS is

SPS is a source package system for Unix-like operating systems. It is meant for
small independent distributions and for administrators who want to understand
how packages get from a recipe into the filesystem.

It is built from a few separate tools, plain text metadata, POSIX shell, POSIX
AWK, and standard Unix utilities. There is no package daemon, SQL database,
plugin framework, or hidden update service.

CRUX is an obvious influence. The useful part to borrow is not its command
names or file formats, but the idea that package management can stay small,
readable, and close to the filesystem. SPS keeps that idea and builds its own
system around it.

The point is not to make the smallest package manager possible. The point is to
keep the machinery understandable while still having the things a real distro
needs: dependency ordering, package ownership, upgrades, repository indexes,
checksums, binary package reuse, configuration-file protection, and recovery
from bad package state.

## The tool split

SPS is not one command with a large subcommand tree.

```text
src       source repository index and queries
sget      dependency-aware package coordination
mkpkg     recipe to binary package
pkin      binary package installation and upgrade
pkdel     low-level package removal
pkstat    installed package queries
pkcheck   installed-state verification
pkmark    explicit/dependency package marking
setup     dialog-based system installer
mkiso     live TTY ISO builder
```

Each tool has a boundary.

`src` reads source repositories and writes the local index. It never installs a
package.

`mkpkg` reads one recipe, builds it in a staging area, and writes one package
archive. It does not copy package files into the live root.

`pkin` installs one already-built package. It knows about package format,
filesystem conflicts, ownership, protected files, and the local package
database. It does not search repositories or resolve dependencies.

`pkdel` removes one package from the installed system. Dependency policy belongs
to `sget`, not `pkdel`.

`pkstat` and `pkcheck` are readers. They should stay useful even if the source
repositories are offline or missing.

`sget` is the convenient layer. It reads the repository index, resolves the
package graph, calls `mkpkg` when it needs an artifact, and hands finished
packages to `pkin` or names to `pkdel`.

This split is useful beyond aesthetics. During rescue work, installation, or
package development, the lower-level tools can be used directly without
bringing the whole dependency layer along.

## What a package is

An SPS binary package is a tar archive with a small `.SPS/` control directory.
The payload is laid out the same way it will appear below the target root.

A package records its name, version, release, architecture, file list, regular
file hashes, dependency metadata, and optional lifecycle hooks. Nothing is kept
in an opaque package database format.

The archive can be inspected with normal tools. The installed record can be
read with normal tools. If SPS itself is unavailable during recovery, the state
is still understandable.

The exact package format is documented in [DESIGN.md](DESIGN.md).

## Recipes

Recipes are line-oriented text files. Metadata can be read without executing
the build commands. This matters for repository indexing and for auditing a
source tree.

A normal recipe contains:

```text
name
version
release
arch
source
hash
depend
builddep
optional
description
prepare
configure
build
install
```

Only the phase fields are executed as build commands. Name, version,
dependencies, sources, and hashes remain data.

SPS does not try to invent a replacement for shell or for existing build
systems. A package recipe can call `make`, `cmake`, `ninja`, `meson`, or a
project-specific script as needed.

Builds happen away from the target root. The install phase writes below `$PKG`,
which becomes the package payload. A recipe that writes directly into the live
system is broken.

## Repositories

An SPS source repository is a directory tree containing recipes. Official trees
are published and synchronized with ordinary Git; an administrator can inspect
or repair their checkouts with ordinary Git commands. `src` owns the small
amount of conservative Git synchronization needed by `src update`, while Git
remains the transport and history mechanism.

A local administrator repository is not a special package format. It is a
configured directory tree, usually with a higher priority, and `src` never
tries to synchronize it. Other transports can likewise populate a directory
repository before indexing.

Repository indexes are cached TSV records. Queries do not walk thousands of
recipe files every time somebody runs `sget search`.

## Dependencies

Dependencies form a graph. SPS topologically orders that graph for builds and
installs, rejects missing dependencies, and reports cycles rather than trying
to guess around them.

The installed `world` file contains packages that were explicitly requested.
Packages pulled in only as dependencies are tracked separately through that
root set. `pkstat --orphans` can therefore report dependency subgraphs that are
no longer reachable from any explicit package.

SPS 1.0 does not have an SAT solver, virtual providers, or a large policy
language. A small source distribution normally controls its own repository and
can keep dependency choices deterministic. If a future distribution runs into
a real problem that needs more machinery, that feature can be added then.

## Installed state

The installed database lives under `/var/lib/sps` by default. Each installed
package gets its own record containing metadata, its manifest, hashes, and any
hooks. A separate owner index maps managed non-directory paths to packages.

The database is plain text because administrators sometimes have to repair
systems by hand. That should be possible without reverse engineering a private
serialization format.

SPS uses locks around package database writers and a higher-level transaction
lock around state-changing `sget` operations. Database files are replaced by
writing a temporary file and renaming it into place.

This does not make the whole root filesystem transactional. SPS does not claim
that it does. Package installation still consists of filesystem writes.

## File ownership

Managed files have one package owner. Before installation, `pkin` checks both
the owner index and the target filesystem.

If an unowned file already exists where a package wants to install one, that is
a conflict. SPS does not silently take it over.

Directories are shared. They are kept out of the exclusive owner index, and an
existing shared directory is not re-owned or chmodded just because a new
package lists it.

When `pkin` runs as root, newly installed payload files and new package
directories are normalized to uid/gid 0 while keeping their packaged modes.
This prevents a package built by an ordinary user from leaking the builder's
numeric UID or GID into the installed system.

## Configuration files

The default protected prefix is `etc`.

If an installed protected regular file has been edited locally, an upgrade
keeps the local copy. When the packaged default changed too, SPS writes the new
copy beside it as `.sps-new`. Removal also leaves a locally modified protected
file alone and drops package ownership of it.

There is no automatic merge. The administrator gets both versions and decides
what to do.

The protected-prefix list is configurable, and it can be disabled.

## Hooks

SPS supports four package hooks:

```text
pre-install
post-install
pre-remove
post-remove
```

That is enough for the cases where installing files is not sufficient, such as
refreshing a loader cache or another system-maintained index.

Hooks are regular files stored in the package. They are not downloaded later
and are not hidden behind a trigger database. Package maintainers should avoid
them when ordinary files or build-time work can solve the same problem.

There is no generic plugin interface in 1.0.

## Binary package cache

SPS is source-oriented, but there is no reason to rebuild an identical package
on every reinstall. `sget` keeps completed binary artifacts under the SPS cache
and reuses an exact name/version/release/architecture match.

The recipe is still authoritative. If a distribution changes how a package is
built without changing the upstream version, the package release must be
bumped. This is normal package-maintainer responsibility, not something the
cache should try to infer.

## Alternate roots

The whole system can be pointed at another root with `SPS_ROOT`. This is useful
for installers, rescue systems, chroots, and image construction.

A package tool should not need a separate special mode just because the target
filesystem is mounted at `/mnt/root` instead of `/`.

## Why AWK

Most package-manager state is text: recipe fields, indexes, manifests,
dependency lists, package records, and ownership tables. AWK is very good at
that work and is available on small systems.

Using it also keeps the project honest. SPS does not need a language runtime,
module registry, or dependency tree of its own just to manage the operating
system's packages.

AWK is not used for jobs it is bad at. SPS calls existing tools for archive
handling, compression, hashing, downloads, patching, and builds. Reimplementing
those in AWK would make the system larger and worse for no practical benefit.

The target is POSIX AWK, not a GNU awk application that happens to use an AWK
file extension.

## KISS in SPS

KISS does not mean refusing every feature. It means a feature has to pay for
the complexity it adds.

A few rules keep SPS on track:

1. A simple command should have a simple path through the code.
2. Read-only commands should not contact the network or modify state.
3. Low-level tools should not grow policy that belongs in `sget`.
4. Metadata should stay inspectable with normal Unix tools.
5. New abstractions need a real use case, not just a cleaner diagram.
6. Existing Unix programs should be used when they already solve the job well.
7. Hidden background behavior is out of scope.
8. Errors should say what failed and leave enough state to diagnose it.
9. A distro maintainer should be able to read the implementation without
   learning a framework first.
10. When a feature cannot be implemented cleanly yet, it can wait.

# And uh yeah thats about it
