#!/bin/sh
# setup: plan, answers, validation, and a fixture install.

set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
fail() { printf 'test_setup: %s\n' "$*" >&2; exit 1; }
contains() { case $1 in *"$2"*) : ;; *) fail "expected output to contain '$2'" ;; esac; }

setup=$project_dir/bin/setup
export SPS_LIBDIR=$project_dir/lib
export PATH=$project_dir/bin:$PATH

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-setup.XXXXXX") || fail mktemp
trap 'rm -rf "$tmp"' 0 HUP INT TERM

profiles=$("$setup" --list-profiles)
contains "$profiles" 'minimal'
contains "$profiles" 'plasma-desktop'
contains "$profiles" 'plasma-full'
contains "$profiles" 'server'

sets=$("$setup" --list-sets)
contains "$sets" 'printing'
contains "$sets" 'browsers'
contains "$sets" 'shells-extra'
contains "$sets" 'ssh'
contains "$sets" 'storage'
contains "$sets" 'wifi'
contains "$sets" 'firmware'
contains "$sets" 'bluetooth'

plan=$("$setup" --plan --target /mnt --profile minimal --disable qol-cli)
contains "$plan" 'Profile:    minimal'
contains "$plan" 'base-system'
contains "$plan" 'dialog'
contains "$plan" 'Locale:     C.UTF-8'

plan=$("$setup" --plan --target /mnt --profile plasma-desktop --user alex \
	--hostname darkstar --timezone UTC --keymap us --nvidia yes \
	--locale en_US.UTF-8 --shell /bin/bash --extra neovim,htop \
	--ssh yes --printing yes)
contains "$plan" 'Hostname:   darkstar'
contains "$plan" 'User:       alex'
contains "$plan" 'Locale:     en_US.UTF-8'
contains "$plan" 'Shell:      /bin/bash'
contains "$plan" 'plasma-desktop'
contains "$plan" 'nvidia-open'
contains "$plan" 'qol-cli'
contains "$plan" 'neovim'
contains "$plan" 'htop'
contains "$plan" 'openssh'
contains "$plan" 'cups'

"$setup" --plan --target /mnt --profile server \
	--write-answers "$tmp/answers" >/dev/null
grep -qx 'profile server' "$tmp/answers" || fail 'answers missing profile'
grep -qx 'target /mnt' "$tmp/answers" || fail 'answers missing target'

plan=$("$setup" --plan --read-answers "$tmp/answers" --hostname other)
contains "$plan" 'Hostname:   other'
contains "$plan" 'Profile:    server'

set +e
"$setup" --plan --target /mnt --profile no-such-profile >/dev/null 2>"$tmp/err"
st=$?
set -e
[ "$st" -eq 3 ] || fail "unknown profile returned $st"
contains "$(cat "$tmp/err")" 'unknown profile'

set +e
"$setup" --plan --target mnt --profile minimal >/dev/null 2>"$tmp/err"
st=$?
set -e
[ "$st" -eq 2 ] || fail "relative target returned $st"

set +e
"$setup" --plan --target /mnt --profile minimal --hostname 'bad host' \
	>/dev/null 2>"$tmp/err"
st=$?
set -e
[ "$st" -eq 2 ] || fail "bad hostname returned $st"

# Fixture profile install into a disposable root.
export SPS_SETUP_DIR=$project_dir/tests/setup-fixture
root=$tmp/root
db=$tmp/db
cache=$tmp/cache
build=$tmp/build
repo=$tmp/repo
mkdir -p "$root" "$db" "$cache" "$build" "$repo/hello" "$repo/extra-pkg"
: >"$tmp/sps.conf"
printf 'dir test %s 10\n' "$repo" >"$tmp/repos.conf"
export SPS_ROOT=$root SPS_DB=$db SPS_CACHE=$cache SPS_BUILD=$build
export SPS_CONFIG=$tmp/sps.conf SPS_REPOS_CONFIG=$tmp/repos.conf

cat >"$repo/hello/recipe" <<'EOF'
name        hello
version     1.0
release     1
arch        any
description fixture hello
install     mkdir -p "$PKG/usr/share/sps-test"
install     printf '%s\n' hello >"$PKG/usr/share/sps-test/hello"
EOF
cat >"$repo/extra-pkg/recipe" <<'EOF'
name        extra-pkg
version     1.0
release     1
arch        any
description fixture extra
install     mkdir -p "$PKG/usr/share/sps-test"
install     printf '%s\n' extra >"$PKG/usr/share/sps-test/extra"
EOF

src update >/dev/null
"$setup" --non-interactive --no-update --target "$root" --profile tiny \
	--hostname fixture --timezone UTC --keymap us --user tester \
	--enable extra --user-gecos 'Test User' >/dev/null

[ "$(cat "$root/usr/share/sps-test/hello")" = hello ] || fail 'hello missing'
[ "$(cat "$root/usr/share/sps-test/extra")" = extra ] || fail 'extra missing'
[ "$(cat "$root/etc/hostname")" = fixture ] || fail 'hostname not written'
[ "$(cat "$root/etc/locale.conf")" = 'LANG=C.UTF-8' ] || fail 'locale not written'
grep -q '^tester:x:1000:1000:Test User:/home/tester:/bin/sh$' \
	"$root/etc/passwd" || fail 'user not recorded'
[ -f "$root/etc/sps/setup-answers" ] || fail 'setup-answers missing'
[ -f "$root/root/sps-bootloader.txt" ] || fail 'bootloader notes missing'
[ -f "$root/root/sps-network.txt" ] || fail 'network notes missing'
[ -f "$root/root/sps-fstab.txt" ] || fail 'fstab notes missing'
grep -q 'grub-install' "$root/root/sps-bootloader.txt" ||
	fail 'bootloader notes omitted grub-install warning'
