# Build the Official SPS Package Repository System

You are working on SPS, the Source Package System.

SPS is a small source package management system written primarily in POSIX AWK and POSIX shell. It is intended to serve as the package management core of an independent, advanced-user Linux distribution.

Your task is to establish the complete official SPS package repository infrastructure using Git and GitHub, then populate it with a large, coherent collection of real, buildable Linux packages.

Do not redesign SPS into a monolithic package manager.

Do not replace its existing Unix-style split tooling.

Do not introduce a repository daemon, package server, SQL database, custom remote protocol, JavaScript tooling, Python repository generator, or large framework.

The repository system should feel natural beside traditional ports systems.

The package repositories themselves are part of the distribution source tree.

They should be readable, clonable, editable, auditable, forkable, and recoverable using ordinary Git.

---

# 1. Repository Layout

There must be separate Git repositories for SPS itself and the package collections.

Use this structure:

```text
sps
sps-core
sps-extra
```

The existing `sps` repository contains only the package manager implementation, documentation, tests, examples, releases, and development history.

Do not turn the SPS source repository into the distribution package tree.

Create:

```text
sps-core
```

for the base operating system, toolchain, fundamental libraries, boot infrastructure, package management tools, and software required to build and maintain the distribution.

Create:

```text
sps-extra
```

for software which is useful but not part of the minimal base system.

This includes graphics, Wayland, X11, desktop software, multimedia, networking tools, editors, language runtimes, development tools, games infrastructure, and other general-purpose packages.

Do not prematurely create ten repositories.

Two official trees are enough for the first release.

Additional trees can be split later when there is a real organizational need.

---

# 2. GitHub Setup

Use `gh` and `git`.

Before doing anything destructive, check authentication:

```sh
gh auth status
```

Never print authentication tokens.

Never place credentials inside repository files.

Determine the authenticated GitHub account or organization and create:

```text
sps-core
sps-extra
```

if they do not already exist.

Use commands equivalent to:

```sh
gh repo create sps-core --public
gh repo create sps-extra --public
```

Do not recreate or destroy existing repositories.

If they already exist, clone them and work with the existing history.

Use ordinary Git repositories.

No Git LFS should be necessary for recipes.

Do not commit source tarballs or large binary packages to Git.

The repositories contain package definitions, patches, small auxiliary files, documentation, and indexes where appropriate.

---

# 3. What Git Means to SPS

Git is the repository transport and history mechanism.

SPS should not hide this.

An administrator should be able to do:

```sh
cd /usr/src/sps/core
git status
git log
git diff
```

and understand what has changed.

`src update` should provide the normal convenient SPS interface, but the repository remains an ordinary Git checkout underneath.

This is intentional.

The package repository should not depend on GitHub-specific APIs after it has been cloned.

GitHub is hosting.

Git is the repository mechanism.

SPS is the package system.

Keep those concepts separate.

---

# 4. Official Repository Configuration

The installed system should support a repository configuration approximately like:

```text
git core  https://github.com/OWNER/sps-core.git   100
git extra https://github.com/OWNER/sps-extra.git   80
dir local /usr/local/src/sps-local                200
```

Use the actual repository URLs created for the project.

The exact syntax must follow the repository parser SPS actually implements.

Do not document a configuration syntax which the current implementation cannot parse.

If Git-backed repositories are not yet fully implemented by `src`, extend the existing `src` implementation carefully.

Do not bolt Git logic into unrelated tools.

`src` owns repository synchronization.

`sget` consumes repository metadata.

`mkpkg` builds recipes.

`pkin` installs package archives.

Keep that separation.

---

# 5. Repository Checkout Location

Use a predictable filesystem location.

The preferred distribution layout is:

```text
/usr/src/sps/
    core/
    extra/
```

A local administrator-maintained collection may live at:

```text
/usr/local/src/sps-local/
```

SPS state, indexes, installed package information, and caches remain under their existing SPS locations.

Do not confuse repository checkouts with the installed package database.

---

# 6. Local Repositories

Local repositories are first-class repositories.

They must not require special package formats.

An administrator should be able to create:

```text
/usr/local/src/sps-local/
```

put normal SPS packages inside it, configure it with a higher priority, and override an official package.

Example:

```text
dir local /usr/local/src/sps-local 200
git core https://github.com/OWNER/sps-core.git 100
git extra https://github.com/OWNER/sps-extra.git 80
```

If both `local` and `core` contain `mesa`, local wins because it has greater priority.

Repository selection must be deterministic.

`src which mesa` should explain which package definition wins and which alternatives exist.

Do not hide precedence.

---

# 7. Repository Structure

Package categories are organizational only.

Do not make category names part of package identity.

A package is identified by its recipe metadata.

A good `sps-core` structure is:

```text
sps-core/
    README.md

    base/
    boot/
    devel/
    libs/
    net/
    system/
```

A good `sps-extra` structure is:

```text
sps-extra/
    README.md

    audio/
    desktop/
    devel/
    editors/
    fonts/
    graphics/
    libs/
    multimedia/
    net/
    shells/
    utils/
    wayland/
    xorg/
```

A package directory looks like:

```text
category/package/
    recipe
```

and may also contain:

```text
category/package/
    recipe
    patches/
    files/
```

Do not create empty directories.

Do not create a separate checksum file if the SPS recipe format already stores checksums in the recipe.

Follow the actual SPS 1.0 format.

---

# 8. Package Definitions Must Be Real

This requirement is absolute.

Do not generate filler recipes.

Do not invent:

* package versions
* source URLs
* SHA-256 hashes
* dependency names
* configure options
* build systems
* installation paths
* patches
* project homepages

Every package must refer to a real upstream project.

Before adding a package:

1. determine the current stable upstream release appropriate for the repository;
2. locate its canonical source archive;
3. download the archive;
4. calculate the actual checksum;
5. inspect upstream build instructions;
6. determine the real build dependencies;
7. determine the real runtime dependencies;
8. write the SPS recipe;
9. build it;
10. install it into a disposable SPS root;
11. run `pkcheck`;
12. remove it;
13. confirm the package leaves the fake root clean.

A recipe that has not passed this process is not considered finished.

Do not mark an untested package as complete.

---

# 9. Do Not Chase Every Latest Version Blindly

Use stable upstream versions.

Do not select an unstable snapshot merely because its version number is newer.

Avoid:

```text
git master snapshots
release candidates
alpha releases
beta releases
nightly builds
random Git commits
```

unless a package specifically requires such a revision and that choice is documented.

Prefer canonical release tarballs.

When several official mirrors exist, prefer the upstream project's primary release infrastructure.

---

# 10. Package Recipe Quality

Recipes should remain short.

Do not write giant generated shell programs inside recipes.

Use the software's intended build system.

Examples include:

```text
configure / make
cmake / ninja
meson / ninja
make
cargo
go
```

where appropriate.

Do not force every project through one build style.

Avoid redundant flags.

Do not add distribution-specific patches unless they solve an actual problem.

When patches are needed, keep them beside the recipe and document why they exist.

---

# 11. Package Naming

Prefer upstream project names.

Examples:

```text
zlib
xz
zstd
openssl
curl
git
cmake
ninja
wayland
mesa
libdrm
```

Do not create unnecessary renamed packages such as:

```text
sps-zlib
sps-openssl
sps-mesa
```

The package belongs to SPS without needing `sps-` in its name.

Use lowercase names unless upstream naming or existing SPS rules require otherwise.

Names must remain safe for SPS package metadata and filesystem paths.

---

# 12. The SPS Package

SPS itself must be packaged by SPS.

Put an SPS package definition in:

```text
sps-core/system/sps/
```

or another appropriate core category.

Its recipe must download an official SPS release archive from the SPS source repository.

Do not copy the SPS implementation into `sps-core`.

The relationship is:

```text
sps repository
      |
      | release archive
      v
sps-core recipe
      |
      v
mkpkg
      |
      v
SPS binary package
```

This makes SPS self-hosting.

The SPS package should install:

```text
src
sget
mkpkg
pkin
pkdel
pkstat
pkcheck
pkmark
```

along with SPS libraries, documentation, examples where appropriate, and manual pages.

---

# 13. Bootstrap Goal

`sps-core` should eventually contain enough software to build a functioning SPS-based Linux system from source.

The core package set should cover at least:

* filesystem hierarchy
* C library
* Linux API headers
* compiler
* assembler/linker
* build tools
* shell
* AWK
* text processing tools
* archive tools
* compression
* hashing
* TLS
* downloader
* Git
* SPS
* device management
* filesystem tools
* boot tools
* basic networking
* process utilities

Do not claim a package tree is bootstrap-ready until a bootstrap has actually been tested.

---

# 14. Initial `sps-core` Package Set

Build a substantial real core collection.

At minimum investigate, package, and test appropriate stable releases of the following projects where they are applicable to the chosen GNU/Linux base:

## Base and filesystem

```text
filesystem
iana-etc
tzdata
cacert
```

`filesystem` may be an SPS-maintained package rather than an upstream tarball.

It should create the base directory hierarchy and essential static configuration expected by the distribution.

Do not let unrelated packages implicitly own the base filesystem.

## Toolchain

```text
linux-headers
binutils
gcc
glibc
m4
make
pkgconf
```

Potentially:

```text
libxcrypt
```

depending on the libc/system architecture.

Bootstrap order must be documented.

## Shell and text environment

```text
bash
dash
gawk
sed
grep
findutils
diffutils
patch
less
which
file
```

Where GNU packages are used, use official GNU release sources.

## Core utilities

```text
coreutils
util-linux
procps-ng
psmisc
shadow
acl
attr
libcap
libcap-ng
```

Review package ownership carefully because `util-linux`, `coreutils`, and similar projects can overlap depending on build options.

Avoid file collisions by choosing build configuration deliberately.

## Archives and compression

```text
tar
gzip
bzip2
xz
zstd
libarchive
```

## Core libraries

```text
zlib
zstd
xz
bzip2
pcre2
libffi
expat
libxml2
libxslt
ncurses
readline
gmp
mpfr
mpc
```

Only declare dependencies which are actually needed.

## Security and networking

```text
openssl
ca-certificates
curl
wget
libpsl
nghttp2
```

Add related libraries where required by the selected builds.

## Version control

```text
git
```

## Build infrastructure

```text
autoconf
automake
libtool
cmake
ninja
meson
pkgconf
```

If Python is required for Meson and other core builds, package Python correctly rather than relying on a host Python forever.

## Scripting/runtime support

```text
python
perl
```

Add other runtimes only when justified by the base build graph.

## Filesystems and storage

Investigate and package:

```text
e2fsprogs
dosfstools
xfsprogs
btrfs-progs
mdadm
lvm2
cryptsetup
```

where dependency complexity permits.

## Hardware/system support

Investigate:

```text
kmod
pciutils
usbutils
hwdata
dmidecode
```

## Device and session infrastructure

Choose and document the distro's direction rather than blindly packaging everything.

Likely packages include:

```text
dbus
elogind
eudev
```

or another coherent system design.

Do not casually introduce systemd merely because one upstream package defaults to it.

SPS is intended for an advanced-user independent distribution.

The base system architecture should be explicit.

## Network administration

Investigate:

```text
iproute2
iputils
inetutils
openssh
rsync
dhcpcd
```

Potentially:

```text
networkmanager
```

belongs in `extra` rather than the minimal core.

## Boot infrastructure

Investigate and package:

```text
linux
grub
efibootmgr
```

The kernel package should not pretend one configuration suits every SPS-based distro.

Provide a documented baseline or packaging framework.

Do not commit enormous generated kernel binaries to Git.

## Package management

```text
sps
```

SPS must live in core.

---

# 15. Initial `sps-extra` Package Set

Build a broad but coherent package collection.

Do not dump random software into the tree.

Prioritize enough packages to build a modern graphical Linux workstation.

---

# 16. Graphics Stack

Package and test the real dependency chain for:

```text
libdrm
mesa
libglvnd
vulkan-headers
vulkan-loader
vulkan-tools
glslang
spirv-headers
spirv-tools
shaderc
```

Investigate optional acceleration dependencies carefully.

Do not hardcode proprietary NVIDIA drivers into the generic Mesa stack.

---

# 17. Wayland

Package:

```text
wayland
wayland-protocols
libinput
libxkbcommon
seatd
```

and the required supporting libraries.

Add:

```text
xwayland
```

once the necessary X stack is present.

---

# 18. X11

Build a coherent Xorg stack rather than randomly adding libraries.

This will likely include packages from:

```text
xorgproto
libXau
libXdmcp
libxcb
xcb-proto
libX11
libXext
libXrender
libXfixes
libXi
libXrandr
libXcursor
libXinerama
libXdamage
libXcomposite
libXpresent
libXft
libXt
libICE
libSM
libXmu
libXpm
libxshmfence
pixman
xkeyboard-config
xtrans
xauth
xinit
xorg-server
```

Confirm capitalization and SPS naming policy consistently.

Do not copy another distribution's dependency lists without checking them against the versions being packaged.

---

# 19. Font Stack

Package:

```text
freetype
fontconfig
harfbuzz
graphite2
fribidi
libpng
```

and useful font packages such as:

```text
dejavu-fonts
liberation-fonts
noto-fonts
```

where redistribution and upstream packaging permit it.

Fonts may use upstream archive sources rather than copying font files into the SPS Git repository.

---

# 20. Image and Graphics Libraries

Investigate:

```text
libjpeg-turbo
libpng
libtiff
libwebp
openjpeg
lcms2
cairo
pixman
gdk-pixbuf
librsvg
```

---

# 21. Audio

Build a modern audio foundation.

Investigate and package:

```text
alsa-lib
alsa-utils
libogg
libvorbis
flac
opus
libsndfile
libsamplerate
speexdsp
pipewire
wireplumber
```

If PulseAudio compatibility is provided by PipeWire, document that choice instead of unnecessarily making PulseAudio mandatory.

---

# 22. Multimedia

Package a useful media stack:

```text
ffmpeg
libvpx
dav1d
x264
x265
libass
libplacebo
mpv
```

Only enable codecs whose dependencies are present and whose distribution conditions are appropriate.

Build options should be documented when they significantly change package functionality.

---

# 23. Desktop Foundation

Before adding KDE or another large desktop, package the infrastructure it needs.

Investigate:

```text
dbus
polkit
elogind
upower
udisks2
libgudev
accountsservice
```

Do not mix incompatible session-management designs.

---

# 24. Qt

Build a sensible Qt 6 foundation.

Start with packages actually required by the desktop set rather than immediately packaging every Qt module.

Likely modules include:

```text
qtbase
qttools
qtdeclarative
qtsvg
qtwayland
qtimageformats
qtmultimedia
qttranslations
```

Then add further modules as real package dependencies require them.

---

# 25. KDE Plasma

Once the lower stack is stable, package a working Plasma environment.

Do not begin with all KDE applications.

First target enough software for a login and usable desktop.

Investigate packages around:

```text
extra-cmake-modules
plasma-wayland-protocols
karchive
kconfig
kcoreaddons
ki18n
kwindowsystem
kwayland
solid
sonnet
kglobalaccel
kconfigwidgets
kiconthemes
kservice
kio
kirigami
kwidgetsaddons
kxmlgui
knotifications
kpackage
kdeclarative
kcmutils
knewstuff
frameworkintegration
breeze-icons
layer-shell-qt
kwin
plasma-workspace
plasma-desktop
systemsettings
breeze
oxygen
dolphin
konsole
sddm
```

This list is illustrative, not authoritative.

Determine the actual current KDE dependency graph from upstream.

Do not guess package dependencies from memory.

The result should boot to a functioning Plasma Wayland desktop before calling the desktop stack complete.

---

# 26. GTK Stack

Even if KDE is the main desktop, provide enough GTK infrastructure for common Linux applications.

Investigate:

```text
glib
gobject-introspection
shared-mime-info
desktop-file-utils
gtk3
gtk4
pango
atk
at-spi2-core
```

plus dependencies required by current releases.

---

# 27. Common Desktop Applications

After the desktop foundation works, add useful programs such as:

```text
firefox
mpv
htop
btop
fastfetch
nano
vim
neovim
tmux
tree
ripgrep
fd
jq
```

Where package names differ upstream, use sensible SPS names.

---

# 28. Development Tools

`sps-extra` should eventually provide:

```text
clang
llvm
lld
lldb
rust
cargo
go
nasm
yasm
gdb
strace
valgrind
```

along with the libraries required to build them.

Do not put a huge LLVM toolchain into `core` unless the base distribution actually requires it.

---

# 29. Other Shells

Useful optional shells may include:

```text
zsh
fish
```

Keep Bash and a POSIX `/bin/sh` implementation in core.

---

# 30. Databases and Common Libraries

As the repository grows, investigate:

```text
sqlite
postgresql
mariadb
lmdb
```

Do not make server databases base dependencies.

---

# 31. Networking Applications and Libraries

Potential packages include:

```text
networkmanager
wpa_supplicant
iwd
bind
nmap
socat
openvpn
wireguard-tools
```

Again, choose coherent defaults.

Do not install three competing network managers into the base system by default.

---

# 32. Package Count Target

Do not optimize for a vanity number.

The first serious repository milestone should aim for roughly:

```text
100 to 150 verified packages
```

Then expand toward:

```text
200 to 300
```

only while maintaining build quality.

A repository of 120 tested packages is better than one containing 700 generated recipes which have never built.

Never pad the package count.

---

# 33. Validation Status

Introduce a simple maintainer policy.

A package belongs in the normal official index only if it is considered usable.

Do not invent elaborate metadata states unless SPS needs them.

During repository development, unfinished recipes may remain on a development branch.

Use Git branches rather than putting knowingly broken packages in the normal user path.

For example:

```text
main
testing
```

`main` should remain buildable.

Do not use `main` as a scratchpad.

---

# 34. Package Build Test

For every completed package, test something equivalent to:

```sh
mkpkg
```

Then install into a disposable root:

```sh
SPS_ROOT="$ROOT" pkin package.pkg.tar.zst
```

Then verify:

```sh
SPS_ROOT="$ROOT" pkcheck package
```

Then query:

```sh
SPS_ROOT="$ROOT" pkstat package
```

Then remove:

```sh
SPS_ROOT="$ROOT" pkdel package
```

Where a package provides executable programs, perform a reasonable smoke test.

Examples:

```sh
bash --version
curl --version
git --version
cmake --version
ninja --version
```

For libraries, inspect installed files and linking behavior where practical.

---

# 35. Build Dependency Testing

Do not accidentally build against undeclared host software.

This is a major source-distribution failure mode.

As the repository matures, create a controlled SPS build root containing only declared dependencies.

Packages should build inside that environment.

A recipe that only works because the developer workstation happens to contain Python, Perl, pkg-config, or some undeclared library is broken.

---

# 36. Dependency Graph Validation

Add repository tests which detect:

* dependencies referring to nonexistent packages;
* duplicate package names;
* dependency cycles;
* packages shadowed unexpectedly;
* malformed recipe metadata;
* invalid checksums;
* conflicting repository entries;
* impossible build dependency graphs.

Use the existing SPS indexing and dependency code where practical.

Do not implement an unrelated second resolver solely for the tests.

---

# 37. Repository Indexes

`src update` should generate local indexes from the Git checkouts.

Do not require generated indexes to be committed unless there is a demonstrated reason.

The Git repository should remain primarily authoritative package source definitions.

Indexes are local machine-readable caches.

They should be reproducible from the recipes.

This prevents merge noise from generated files.

---

# 38. Git Synchronization Behavior

For Git repositories, `src update` should behave conservatively.

It should not destroy local modifications.

A reasonable rule is:

* clone when repository is absent;
* fetch remote updates when present;
* fast-forward only when safe;
* refuse destructive reset when the checkout contains local changes.

If a repository cannot be updated safely, report it clearly.

Do not automatically run:

```sh
git reset --hard
git clean -fdx
```

against administrator-owned trees.

Never throw away local work to make synchronization easier.

---

# 39. Repository Pinning

The repository implementation should make it possible to work from a particular branch, tag, or commit.

This does not need to become a giant SPS policy system.

Git already provides the mechanism.

The configuration may later grow a simple branch field if needed.

For now, preserve normal Git interoperability.

---

# 40. Repository History

Use meaningful commits.

Do not make one giant commit called:

```text
add packages
```

for hundreds of packages.

Prefer commits such as:

```text
core: add initial compression libraries
core: add base GNU utilities
core: add OpenSSL and curl
extra: add Wayland protocol stack
extra: add Mesa graphics stack
extra: add FFmpeg dependencies
```

Individual package upgrades should generally be easy to identify in history:

```text
openssl: update to X.Y.Z
mesa: update to X.Y.Z
firefox: update to X.Y
```

Do not mention AI, generation, agents, or prompts in commits.

Write commit messages as the maintainer of the distribution.

---

# 41. README for `sps-core`

Write a concise human README.

It should explain:

* what the repository contains;
* that it is an official SPS source package collection;
* the directory structure;
* how to configure it in SPS;
* how to synchronize it;
* how to build a package;
* contribution expectations.

Do not write marketing copy.

Avoid phrases such as:

```text
blazing fast
next generation
powerful yet simple
robust ecosystem
seamless experience
empowers users
```

Write like a Unix project maintainer.

---

# 42. README for `sps-extra`

Use the same style.

Explain that it contains packages outside the minimal base system.

Do not repeat the entire SPS manifesto.

Link or refer to SPS documentation where needed.

---

# 43. Package Maintainer Documentation

Add a concise package-writing guide.

It should document the actual recipe syntax supported by SPS.

Include:

* required metadata;
* source declarations;
* checksums;
* runtime dependencies;
* build dependencies;
* prepare commands;
* build commands;
* install/staging commands;
* architecture;
* package release number;
* local files;
* patches;
* hooks if supported.

Include several real examples.

Avoid tutorials padded with philosophy.

---

# 44. Package Updates

The normal update workflow should be simple:

```sh
cd sps-core/libs/zlib
$EDITOR recipe
mkpkg
```

Then test.

Then commit:

```sh
git add libs/zlib
git commit -m 'zlib: update to ...'
git push
```

Repository maintainers should not need to run a giant regeneration framework for one package.

If local indexes need regeneration, `src update` handles them on client systems.

---

# 45. Release Numbers

Keep source version and package release separate.

Conceptually:

```text
version 1.3.1
release 1
```

If the upstream software does not change but the SPS recipe changes:

```text
version 1.3.1
release 2
```

Do not invent distribution-style suffix complexity unnecessarily.

---

# 46. Upgrades

Test upgrades, not only fresh installs.

For important core packages:

1. install the previous packaged version;
2. build the new recipe;
3. install the upgrade through SPS;
4. verify ownership;
5. verify protected configuration behavior;
6. run `pkcheck`;
7. ensure obsolete files are removed safely.

This matters especially for:

```text
sps
openssl
glibc
gcc
bash
util-linux
openssh
dbus
mesa
```

---

# 47. Protected Configuration

Respect SPS protected configuration behavior.

Packages should install sane default configuration files.

Do not overwrite administrator modifications during upgrades.

If SPS creates `.sps-new` files for changed package defaults, package recipes should work with that behavior rather than adding unrelated configuration-preservation logic.

---

# 48. Hooks

Use package lifecycle hooks sparingly.

Hooks may be justified for operations such as:

* cache regeneration;
* icon caches;
* MIME databases;
* library caches;
* schema compilation;
* font caches.

Do not put routine build logic in install hooks.

Do not make packages depend on mysterious global hook frameworks.

Any hook must remain visible in package metadata.

---

# 49. Security

Package repositories become privileged supply-chain inputs.

Treat them accordingly.

Never:

* execute downloaded source metadata while indexing;
* disable checksum verification because a package is difficult;
* use `curl | sh`;
* download build-time scripts from mutable URLs without verification;
* accept archive path traversal;
* hide privileged actions inside generated scripts.

Use HTTPS where available.

Use cryptographic hashes for sources.

If an upstream publishes signatures, signature verification may later be added as an additional mechanism.

Do not invent custom cryptography.

---

# 50. Source Mirrors

Do not build a custom SPS mirror infrastructure initially.

Recipes should use upstream release URLs.

If reliability becomes a problem later, a simple source mirror can be added.

Keep source identity tied to cryptographic checksums so mirror location does not define trust.

---

# 51. Binary Packages

The Git package repositories contain recipes, not built binary packages.

Binary package caches belong elsewhere.

Do not commit `.pkg.tar.zst` files to `sps-core` or `sps-extra`.

SPS remains source-oriented even though it may reuse locally cached binary artifacts.

---

# 52. CI

Add practical CI where useful.

CI should at minimum perform repository linting:

* parse every recipe;
* ensure package names are unique;
* validate dependency references;
* validate required metadata;
* validate repository indexes can be generated;
* run shell syntax checks on scripts;
* run SPS repository tests.

Do not pretend GitHub-hosted CI can cheaply rebuild an entire Linux distribution on every commit.

Use CI for quick structural failures.

Perform full package builds in dedicated build environments.

---

# 53. Full Repository Build

Create tooling or documented procedures to attempt builds in dependency order.

Do not turn this into another package manager.

SPS itself should provide the graph.

A repository validation script may orchestrate:

```text
dependency order
    |
    v
mkpkg
    |
    v
pkin into build root
```

The purpose is to prove that the package tree is self-consistent.

---

# 54. Bootstrap Documentation

Create:

```text
BOOTSTRAP.md
```

in `sps-core`.

It should eventually document:

1. required host tools;
2. creation of the initial filesystem root;
3. first-pass toolchain;
4. libc installation;
5. second-pass/native toolchain;
6. essential core utilities;
7. installation of SPS;
8. switching to SPS-managed package builds;
9. bootloader/kernel setup;
10. reaching a self-hosting SPS system.

Do not claim the bootstrap is finished until actually tested.

Clearly distinguish current working steps from planned ones.

---

# 55. Distribution Readiness Definition

The repositories can be called distro-ready when a clean system can:

```text
bootstrap toolchain
        |
install SPS
        |
build core through SPS
        |
boot
        |
network
        |
update repositories
        |
build/install packages
        |
upgrade itself
```

For graphical readiness, additionally require:

```text
DRM/Mesa
Wayland
Xwayland
audio
session infrastructure
desktop environment
display manager
browser or another substantial GUI application
```

Do not use package count as the definition of distro readiness.

---

# 56. A Good Initial Milestone

The first large milestone should produce a command sequence roughly like:

```sh
src update

sget search bash
sget info bash

sget install curl
sget install git
sget install cmake
```

on a functioning SPS system.

The dependency graph should cause prerequisites to build in the correct order.

---

# 57. A Good Desktop Milestone

Later, from the official repositories, something approximately like:

```sh
sget install plasma-desktop
```

should be capable of pulling the required dependency graph and building a functioning desktop stack.

Do not cheat by relying on host-distribution packages which are absent from SPS metadata.

---

# 58. Failure Handling

Do not continue blindly when a package fails.

Record:

* package;
* version;
* build phase;
* actual error;
* build log location.

Fix the package or dependency graph.

Do not mark it complete because the recipe looks plausible.

When an upstream package cannot reasonably be completed during the current work session, document it and continue with independent packages.

Do not fabricate success.

---

# 59. Keep SPS KISS

As repository size grows, resist adding mechanisms merely because larger package managers have them.

Before adding something to SPS itself, ask:

1. Can Git already solve it?
2. Can the package recipe already express it?
3. Can an ordinary Unix tool solve it?
4. Is this actually a recurring package-management problem?
5. Does putting it into SPS make the system easier to understand?

If not, do not add it.

---

# 60. Do Not Copy CRUX

CRUX is an influence.

SPS must remain its own system.

Do not:

* copy the CRUX ports tree wholesale;
* mechanically translate Pkgfiles;
* use CRUX package metadata as if it were authoritative upstream information;
* mirror CRUX command names;
* copy patches without understanding why they exist.

It is acceptable to study CRUX, Slackware, Gentoo, LFS, BLFS, Alpine, Void, and other distributions to understand package relationships and known build problems.

But package definitions must be produced for SPS and verified against upstream software.

The official upstream project remains the primary source of truth.

---

# 61. Use Existing Distribution Knowledge Carefully

Linux From Scratch and Beyond Linux From Scratch are particularly useful for:

* bootstrap ordering;
* core dependency relationships;
* known installation caveats;
* filesystem layout.

Other distributions may be useful for understanding patches or optional dependencies.

Do not blindly copy them.

A patch required by one distribution may be caused by that distribution's configuration rather than SPS.

Always understand a patch before carrying it.

---

# 62. Repository Maintenance Commands

The resulting system should make these workflows natural:

```sh
src update
src status
src search mesa
src show mesa
src which mesa
```

Then:

```sh
sget search mesa
sget info mesa
sget depends mesa
sget dependees mesa
sget why package dependency
sget install mesa
sget upgrade
```

Low-level package tools remain available:

```sh
mkpkg
pkin package.pkg.tar.zst
pkdel package
pkstat package
pkcheck package
pkmark package explicit
```

Do not collapse them into one executable.

---

# 63. Repository Query Performance

Large repositories must remain quick to search.

Do not make every:

```sh
sget search
```

recursively parse hundreds of recipes.

`src update` should produce compact local indexes.

`sget` should query those indexes.

Recipe files are opened when their detailed information or build instructions are needed.

This keeps AWK well within its strengths.

---

# 64. Scale Expectations

Design for thousands of recipes without requiring thousands initially.

Indexes should be single-pass friendly.

Dependency data should be loadable into AWK associative arrays.

Avoid subprocess-per-package query behavior.

Avoid repeated `find`, `grep`, or Git invocations inside tight package loops when one operation can gather the required data.

Measure real performance before adding complicated caches.

---

# 65. Repository Tests

Add tests for at least:

```text
duplicate names
missing dependencies
cycles
bad repository priority
malformed recipe
missing source hash
invalid architecture
repository override
Git update with clean tree
Git update with dirty tree
local repository
package lookup
package search
dependency lookup
```

Git synchronization tests must use temporary local Git repositories rather than depending on GitHub network access during the ordinary SPS unit test suite.

---

# 66. GitHub Release Workflow for SPS

The SPS implementation repository should publish source releases such as:

```text
sps-1.0.0.tar.gz
sps-1.0.1.tar.gz
sps-1.1.0.tar.gz
```

Tag them:

```text
v1.0.0
v1.0.1
v1.1.0
```

The `sps-core` SPS recipe should reference official releases rather than arbitrary branch archives.

Checksums must match the released artifacts exactly.

---

# 67. Repository Tags

Package repositories may use release/snapshot tags when useful.

For a rolling system, normal Git commits can remain the primary state.

Useful tags might later include:

```text
2026.09
2026.10
```

or distro releases.

Do not invent tags without a release policy.

A Git commit ID is already a perfectly valid repository snapshot.

---

# 68. Package Review

Before considering a package done, inspect:

```text
recipe
source archive
installed file list
dependencies
resulting package archive
```

Look for:

* accidental `/usr/local` installation;
* files outside the staged root;
* static libraries when unnecessary;
* debug artifacts;
* development tests installed accidentally;
* package-owned temporary files;
* collisions;
* incorrect permissions;
* wrong architecture;
* undeclared dependencies.

---

# 69. Do Not Strip Blindly

Do not globally run `strip` on every file.

If SPS later adds package stripping, it must distinguish:

* ELF executables;
* shared libraries;
* static archives;
* debug files.

For now, respect the package's build system unless there is a clear SPS policy.

---

# 70. Architecture

Support SPS architecture metadata consistently.

Use actual architecture naming accepted by SPS.

Architecture-independent packages should use the existing SPS convention such as:

```text
any
```

or:

```text
noarch
```

only according to the actual implementation.

Do not create competing aliases.

---

# 71. Kernel

The kernel is special.

Do not hide its configuration.

Provide a package framework which:

* obtains a real kernel release;
* verifies it;
* builds it;
* stages modules;
* installs appropriate kernel artifacts.

Keep the configuration visible.

A distribution baseline config may live beside the recipe as a normal file.

Do not pretend every user must use the distribution kernel.

Advanced users should still be able to build kernels manually.

---

# 72. Bootloader

GRUB packaging must account for EFI and BIOS support sensibly.

Do not run `grub-install` as an automatic package installation hook.

Installing the GRUB package and installing a bootloader onto a disk are not the same operation.

Package management must not silently alter boot sectors or EFI boot variables.

The administrator performs bootloader installation explicitly.

---

# 73. Services

Installing a package must not automatically enable every service it contains.

SPS packages install files.

Service enablement is system policy.

A package may include service scripts, but enabling them should generally remain an explicit administrator action.

This matches the advanced-user distribution model.

---

# 74. Users and Groups

Some packages require dedicated system users or groups.

Develop a simple documented policy.

Avoid random package-specific UID choices where possible.

If SPS hooks are used for account creation, keep those hooks visible and idempotent.

Long-term, a distro-owned static system account allocation file may be more appropriate.

Do not bury user creation in opaque build scripts.

---

# 75. `/etc`

Default system configuration should be packaged where appropriate.

Local administrator changes are not distribution source code.

SPS protected configuration handling should preserve them across package upgrades.

Repository recipes should not fight this behavior.

---

# 76. `/usr/local`

Official SPS packages should not install into:

```text
/usr/local
```

That hierarchy belongs to the local administrator.

Official packages should normally use:

```text
/usr
/etc
/var
```

as appropriate.

---

# 77. `/opt`

Do not use `/opt` merely because a package is large.

Use normal Unix filesystem hierarchy conventions unless upstream software genuinely requires otherwise.

---

# 78. Static and Shared Libraries

Prefer normal shared-library builds for general distribution packages.

Static libraries may be installed when useful for development or upstream convention, but avoid pointless duplication for very large libraries.

Do not invent aggressive global rules before real repository experience exists.

---

# 79. Package Splitting

Do not immediately introduce:

```text
foo
foo-dev
foo-doc
foo-libs
```

for every upstream package.

SPS is modeled after a simpler source distribution.

A package may contain headers, libraries, documentation, and programs together unless there is a practical reason to split it.

Package splitting adds dependency and maintenance complexity.

Use it only when it materially improves the distribution.

---

# 80. Optional Dependencies

Do not make every possible feature mandatory.

A package like FFmpeg has a huge optional dependency surface.

Start with a useful, coherent SPS configuration.

Document important disabled features.

Expand functionality as the corresponding packages become available.

---

# 81. Variants

Do not introduce USE flags or a general package-option language for the first repository version.

If a local administrator needs unusual compile options, they can maintain a local repository override.

This is simple, transparent, and already fits SPS.

---

# 82. Package Replacement

When upstream projects replace others or package names change, use SPS replacement/conflict features only if those features actually exist.

Do not write documentation pretending they do.

Until then, migrations can be documented and handled explicitly.

---

# 83. Real Build Logs

During initial repository construction, retain build logs outside Git.

Use a workspace such as:

```text
/var/tmp/sps-build-logs/
```

or another temporary development location.

Do not commit massive logs.

When a package fails, consult its log instead of repeatedly guessing at build flags.

---

# 84. Work in Dependency Layers

Do not try to build Firefox on day one.

Build the repository in layers.

Suggested progression:

## Layer 1

```text
filesystem
linux-headers
binutils
gcc
glibc
zlib
bash
dash
gawk
coreutils
sed
grep
findutils
tar
gzip
xz
zstd
make
```

## Layer 2

```text
ncurses
readline
openssl
curl
git
pkgconf
m4
autoconf
automake
libtool
```

## Layer 3

```text
python
cmake
ninja
meson
perl
```

## Layer 4

system administration and networking.

## Layer 5

graphics and X/Wayland.

## Layer 6

audio and multimedia.

## Layer 7

desktop frameworks.

## Layer 8

large applications.

This makes failures understandable.

---

# 85. Use Git Commits as Checkpoints

Commit after coherent, tested groups of packages.

Do not wait until hundreds of files are modified.

Example progression:

```text
core: establish repository structure
core: add bootstrap toolchain recipes
core: add base shell and text utilities
core: add compression stack
core: add TLS and networking base
core: add SPS package
extra: add graphics base
extra: add Wayland stack
```

Push regularly once the commits are valid.

---

# 86. Never Rewrite Published History Casually

Once package repositories are in use, treat their public history as useful administrative history.

Do not routinely force-push `main`.

Fix mistakes with new commits.

Git history is part of the value of this repository design.

---

# 87. What Success Looks Like

At the end of this work, there should be:

```text
sps
sps-core
sps-extra
```

as clean, independent GitHub repositories.

`sps-core` should contain a substantial, tested base package collection.

`sps-extra` should contain a useful tested collection beyond the base.

The repositories should be configured and usable through SPS.

SPS itself should be packaged in `sps-core`.

A local repository should be able to override official packages cleanly.

Repository indexing should remain fast.

Dependencies should resolve deterministically.

Package recipes should use real upstream sources and hashes.

There should be no placeholder packages.

There should be no fake test results.

There should be no giant generated framework surrounding the repositories.

---

# 88. Final Rule

Do not judge the repository by how many directories were generated.

Judge it by this:

> Can an administrator clone the package trees, read a recipe, understand where a package comes from, build it, install it, inspect it, modify it locally, and recover the repository state with ordinary Unix and Git tools?

If yes, SPS is following its purpose.

If adding a feature makes that significantly harder, reconsider the feature.

The package repositories are not a service sitting behind SPS.

They are the source code of the distribution.

Keep them readable.
