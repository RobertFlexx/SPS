# SPS package maintainer guide

An SPS package directory contains a line-oriented file named `recipe`. It may
also contain `files/`, `patches/`, and `hooks/`. Recipes are data, not shell
files: repository indexing parses them without executing build commands.

The same recipe format works anywhere SPS runs, including Linux From Scratch
and custom roots. `linux-desktop`, Plasma profiles, and `setup` defaults are
**SPS Linux** (Splux) distro pieces; an LFS project can ignore them.

## Recipe records

Each logical line is a key, whitespace, and a non-empty value. Blank lines and
lines beginning with `#` are ignored. A trailing backslash continues a value on
the next physical line. Inline comments are not recognized.

The complete key set is:

| Key | Count | Meaning |
| --- | --- | --- |
| `name` | one | Package name |
| `version` | one | Upstream source version |
| `release` | one | SPS recipe release |
| `arch` | zero or one | Target architecture |
| `description` | zero or one | Short package description |
| `source` | repeatable | Upstream URL or local source path |
| `hash` | one per source | Source SHA-256 digest |
| `depend` | repeatable | Runtime dependency |
| `builddep` | repeatable | Build dependency |
| `optional` | repeatable | Informational optional dependency |
| `conflict` | repeatable | Package names that cannot be co-installed |
| `prepare` | repeatable | Source preparation command |
| `configure` | repeatable | Configuration command |
| `build` | repeatable | Build command |
| `install` | one or more | Staged installation command |

Unknown keys are errors. SPS 1.0 has no recipe keys for homepage, license,
maintainer, replacements, provides, or package options. Keep that
information in repository documentation when needed; do not invent fields.

`conflict` is supported: `sget` will not install a package next to a named
conflict. Use it for init systems (`systemd` vs `openrc`) and for udev
implementations (`systemd` vs `eudev`).

`name`, `version`, `release`, and at least one `install` record are required.
The install phase must produce a non-empty package. `name` must begin with an
alphanumeric character and may then contain letters, digits, `+`, `_`, `.`, or
`-`. Versions and releases also allow `~`.

`${name}`, `${version}`, `${release}`, and `${arch}` are expanded as recipe
data. No other recipe variables are defined by the parser.

## Sources and hashes

Every source has one hash in the same declaration order:

```text
source https://example.org/project/project-${version}.tar.xz
hash sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

The digest must contain exactly 64 hexadecimal digits. There is no `skip`
value or insecure checksum mode. Download the canonical release archive and
calculate its digest before committing the recipe.

HTTP and HTTPS URLs are downloaded with `curl` or `wget`. A bare relative path
is resolved from the recipe directory. Use a bare relative path for a checked-in
source file, or an absolute `file:///path` URL; relative `file://` paths depend
on the caller's working directory and should be avoided.

`mkpkg` automatically extracts `.tar`, `.tar.gz`, `.tgz`, `.tar.xz`, `.txz`,
`.tar.zst`, `.tzst`, `.tar.bz2`, and `.tbz2` sources. When extraction produces
one top-level directory, that directory becomes `$WORK`; otherwise the
extraction root is `$WORK`. Plain files remain below `$SRC`.

Source extraction rejects absolute member names and `..` path components, but
it is not a sandbox for arbitrary hostile archives. Use immutable, reviewed
upstream releases with verified checksums. In particular, current SPS 1.0 does
not independently validate every tar link target before extraction.

## Dependencies

Use the singular keys `depend`, `builddep`, `optional`, and `conflict`. A record may contain
one or more whitespace- or comma-separated specifications. Version constraints
have no spaces around the operator:

```text
depend zlib
depend openssl>=3.0
builddep pkgconf
builddep meson ninja
optional doxygen
```

Supported operators are `=`, `<`, `<=`, `>`, and `>=`. Constraints apply to
the upstream version, not the package release. `sget install` installs build
dependencies while building a dependency closure. `optional` is informational
and is not installed automatically. Low-level `mkpkg` and `pkin` do not resolve
dependencies.

Declare everything needed in a controlled build root. A successful build on a
maintainer workstation is insufficient if undeclared host tools or libraries
made it succeed.

## Architecture and release

Omit `arch` for compiled packages. It then defaults to the exact configured
`SPS_ARCH`, normally `uname -m`. SPS performs no architecture aliasing or ELF
inspection.

Use:

```text
arch any
```

only for architecture-independent scripts, data, documentation, or fonts.
`noarch` is accepted as a compatibility spelling, but official recipes use
`any` consistently.

Keep the upstream version and SPS release separate. Begin a new upstream
version at `release 1`. Increment `release` whenever a recipe, source choice,
patch, local file, hook, or build option changes without an upstream version
change. Binary cache identity is name, version, release, and architecture; a
release bump is therefore required to prevent reuse of an older artifact.

## Build phases

`mkpkg` runs `prepare`, `configure`, `build`, and `install` in that order. Each
phase is a separate `/bin/sh -eu` script starting in `$WORK`. Shell variables,
functions, and directory changes do not carry between phases.

The phase environment provides:

| Variable | Value |
| --- | --- |
| `WORK` | Extracted source root and phase working directory |
| `SRC` | Downloaded/copied sources and support trees |
| `PKG` | Package staging root |
| `MAKEJOBS` | Positive parallel-job count |
| `SPS_TARGET_LIBRARY_PATH` | Target `lib64`/`lib` dirs when `SPS_ROOT` is not `/` |

Typical build-system records look like:

```text
configure ./configure --prefix=/usr
build make -j"$MAKEJOBS"
install make DESTDIR="$PKG" install
```

```text
configure cmake -S . -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr
build cmake --build build --parallel "$MAKEJOBS"
install DESTDIR="$PKG" cmake --install build
```

```text
configure meson setup build --prefix=/usr --libdir=lib64 --buildtype=release
build meson compile -C build -j "$MAKEJOBS"
install DESTDIR="$PKG" meson install -C build
```

Meson feature options take `enabled`, `disabled`, or `auto`, not `true`/`false`.
Passing `-Dpython=false` to libxml2 2.15 is a meson error, not a compiler error.

Use the upstream project's intended build system and supported options. Build
commands run on the host; `mkpkg` is not a chroot and cannot prevent a bad
command from modifying paths outside `$PKG`.

When `SPS_ROOT` is a mounted disk (live `setup`), `mkpkg` puts that root on
`LD_LIBRARY_PATH` so a just-built interpreter can import its own extensions
against libraries already unpacked into the target. CPython's
`check_extension_modules` will otherwise load the live disc's older
`libsqlite3`, rename `_sqlite3` to `_sqlite3_failed`, and then `make install`
dies on `sharedinstall`. Host `gcc`, `python3`, `meson`, and `git` wrappers
restore the previous `LD_LIBRARY_PATH` so those tools do not load a
half-installed libc from the disk. Shared libraries belong in `lib64` on
this architecture; pass `--libdir=/usr/lib64` (or Meson's `--libdir=lib64`)
instead of relying on Autoconf's `/usr/lib` default.

## Local files and patches

A real `files/` directory is copied to `$SRC/files`; a real `patches/` directory
is copied to `$SRC/patches`. Entries must be ordinary directories or regular
files. Symlinks, special files, and paths containing tabs or newlines are
rejected. The repository definition digest includes support paths, contents,
and copied modes, so run `src update` after any of them changes. Nothing is
applied or installed automatically.

For example:

```text
builddep patch
prepare patch -Np1 -i "$SRC/patches/fix-build.patch"
install mkdir -p "$PKG/etc/example"
install cp "$SRC/files/example.conf" "$PKG/etc/example/example.conf"
```

Document why each patch exists beside the patch or in the package's repository
history. Remove patches that upstream no longer needs.

## Hooks

The only lifecycle files accepted below `hooks/` are:

```text
pre-install
post-install
pre-remove
post-remove
```

They must be regular files, not symlinks, and their names may not contain tabs
or newlines. Hook contents are part of the repository definition digest.
`mkpkg` stores them as mode `0644`, and package tools invoke them with
`/bin/sh -eu`; an executable bit and shebang are unnecessary.

Install and upgrade hooks receive `SPS_ACTION`, `SPS_PACKAGE`, `SPS_VERSION`,
`SPS_RELEASE`, and `SPS_PACKAGE_ARCH`. Remove hooks receive `SPS_ACTION`,
`SPS_PACKAGE`, and `SPS_VERSION`. Normal SPS configuration variables, including
`SPS_ROOT`, are also exported. Hooks run on the host rather than in a chroot and
must prefix target paths with `$SPS_ROOT`.

A failed pre-hook stops the payload action. A failed post-hook returns status
10 after the package database change has committed. Use hooks only for visible,
idempotent lifecycle work; ordinary build and install commands belong in the
recipe.

## Complete local example

`examples/hello/recipe` is a complete, offline recipe:

```text
name        hello-sps
version     1.0
release     1
arch        any
description Minimal hello-world package used by the SPS examples

source      hello.sh
hash        sha256:25576de85c3f0b4dc3e7847956daf896c450318a00bb1b818869accf8fdc7268

install     mkdir -p \
            "$PKG/usr/bin"
install     cp "$SRC/hello.sh" "$PKG/usr/bin/hello-sps"
install     chmod 755 "$PKG/usr/bin/hello-sps"
```

Build it with:

```sh
cd examples/hello
mkpkg --no-download --compression none
```

## Package verification

Build, inspect, install, verify, query, smoke-test, and remove every completed
package. Keep SPS state outside the disposable filesystem root so leftover
payload is easy to see:

```sh
tmp=$(mktemp -d)
root=$tmp/root
mkdir -p "$root" "$tmp/db" "$tmp/cache" "$tmp/build" "$tmp/out"

run_sps()
{
    SPS_ROOT="$root" \
    SPS_DB="$tmp/db" \
    SPS_CACHE="$tmp/cache" \
    SPS_BUILD="$tmp/build" \
    SPS_CONFIG=/dev/null \
    SPS_REPOS_CONFIG=/dev/null \
    "$@"
}

result=$(mktemp)
run_sps mkpkg --artifact-file "$result" --output "$tmp/out" ./recipe
artifact=$(cat "$result")
tar -tf "$artifact"
run_sps pkin "$artifact"
run_sps pkcheck package-name
run_sps pkcheck --database
run_sps pkstat package-name
run_sps pkstat --files package-name

# Run an appropriate executable, link, or data smoke test here.

run_sps pkdel package-name
run_sps pkcheck --database
find "$root" -mindepth 1 -print
```

Read the archive path from `--artifact-file` after `mkpkg` exits 0. Compression
depends on the local configuration. Use a fresh output directory because `mkpkg`
does not overwrite an existing artifact. `--keep-build` retains work and staging
paths for failure inspection; redirect command output to a log outside Git when
preserving a build log.

`SPS_ROOT` redirects installation but does not chroot a smoke test. Running a
dynamically linked executable under `$root/usr/bin` may still use host runtime
libraries. Use a controlled chroot or container when validating declared
dependencies and runtime linkage.

`pkcheck` verifies installed presence, regular-file hashes, and database
relationships. Also inspect modes, ownership, symlink targets, installed paths,
and the resulting archive manually. After removal, account for intentionally
retained modified protected files and any state created by lifecycle hooks.
