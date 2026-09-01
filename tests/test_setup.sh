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
contains "$sets" 'drivers'
contains "$sets" 'flatpak'

plan=$("$setup" --plan --target /mnt --profile minimal --disable qol-cli --enable flatpak)
contains "$plan" 'flatpak'
contains "$plan" 'json-glib'
contains "$plan" 'libseccomp'
contains "$plan" 'gpgme'
contains "$plan" 'appstream'

plan=$("$setup" --plan --target /mnt --profile minimal --disable qol-cli)
contains "$plan" 'Profile:    minimal'
contains "$plan" 'base-system'
contains "$plan" 'splux-base'
contains "$plan" 'fastfetch'
contains "$plan" 'Init:       none'

plan=$("$setup" --plan --target /mnt --profile minimal --init systemd --disable qol-cli)
contains "$plan" 'Init:       systemd'
contains "$plan" 'init-systemd'

plan=$("$setup" --plan --target /mnt --profile minimal --init openrc --disable qol-cli)
contains "$plan" 'Init:       openrc'
contains "$plan" 'init-openrc'

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
mkdir -p "$tmp/nolive-fixture"
: >"$tmp/sps.conf"
printf 'dir test %s 10\n' "$repo" >"$tmp/repos.conf"
export SPS_ROOT=$root SPS_DB=$db SPS_CACHE=$cache SPS_BUILD=$build
export SPS_CONFIG=$tmp/sps.conf SPS_REPOS_CONFIG=$tmp/repos.conf
export SPS_LIVE_ROOT=$tmp/nolive-fixture

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
awk -F: '$1=="tester" && $2=="!" { found=1 } END { exit !found }' \
	"$root/etc/shadow" || fail 'user without password flags must stay locked'
awk -F: '$1=="root" && $2=="!" { found=1 } END { exit !found }' \
	"$root/etc/shadow" || fail 'root without password flags must stay locked'
if grep -q 'password-hash' "$root/etc/sps/setup-answers"; then
	fail 'setup-answers must not store password hashes'
fi
[ -f "$root/etc/sps/setup-answers" ] || fail 'setup-answers missing'
[ -f "$root/root/sps-bootloader.txt" ] || fail 'bootloader notes missing'
[ -f "$root/root/sps-network.txt" ] || fail 'network notes missing'
[ -f "$root/root/sps-fstab.txt" ] || fail 'fstab notes missing'
[ -f "$root/root/sps-services.txt" ] || fail 'services notes missing'
grep -q 'Init is none' "$root/root/sps-services.txt" ||
	fail 'fixture with init none should not pretend to enable services'
grep -q 'grub-install' "$root/root/sps-bootloader.txt" ||
	fail 'bootloader notes omitted grub-install warning'

printf '%s\n' 'test-user-pw' >"$tmp/user.pw"
printf '%s\n' 'test-root-pw' >"$tmp/root.pw"
chmod 600 "$tmp/user.pw" "$tmp/root.pw"
root_pw=$tmp/root-pw
mkdir -p "$root_pw"
"$setup" --non-interactive --no-update --target "$root_pw" --profile tiny \
	--hostname pwtest --timezone UTC --keymap us --user tester \
	--enable extra --user-gecos 'PW User' \
	--user-password-file "$tmp/user.pw" \
	--root-password-file "$tmp/root.pw" >/dev/null
awk -F: '$1=="tester" && $2!="" && $2!="!" && $2!="*" { found=1 }
	END { exit !found }' "$root_pw/etc/shadow" ||
	fail 'user password file did not update shadow'
awk -F: '$1=="root" && $2!="" && $2!="!" && $2!="*" { found=1 }
	END { exit !found }' "$root_pw/etc/shadow" ||
	fail 'root password file did not update shadow'
if grep -q 'password-hash' "$root_pw/etc/sps/setup-answers"; then
	fail 'setup-answers must not store password hashes'
fi
grep -q 'wheel:.*tester' "$root_pw/etc/group" ||
	fail 'first user should be in wheel when that group exists'

printf '%s\n' 'setup fixture tests passed'

# Bundled live recipes: copy into the target and index locally (no Git clone).
live=$tmp/live
mkdir -p "$live/usr/src/sps/core/hello" "$live/usr/src/sps/extra/placeholder"
cat >"$live/usr/src/sps/core/hello/recipe" <<'EOF'
name        hello
version     1.0
release     1
arch        any
description bundled hello
install     mkdir -p "$PKG/usr/share/sps-test"
install     printf '%s\n' bundled >"$PKG/usr/share/sps-test/hello"
EOF
cat >"$live/usr/src/sps/extra/placeholder/recipe" <<'EOF'
name        placeholder
version     1.0
release     1
arch        any
description bundled extra placeholder
install     true
EOF

root_seed=$tmp/root-seed
db_seed=$tmp/db-seed
cache_seed=$tmp/cache-seed
build_seed=$tmp/build-seed
mkdir -p "$root_seed" "$db_seed" "$cache_seed" "$build_seed"
(
	unset SPS_ROOT SPS_DB SPS_CACHE SPS_BUILD SPS_CONFIG SPS_REPOS_CONFIG
	export SPS_LIVE_ROOT=$live
	export SPS_SETUP_DIR=$project_dir/tests/setup-fixture
	export SPS_LIBDIR=$project_dir/lib
	export PATH=$project_dir/bin:$PATH
	"$setup" --non-interactive --target "$root_seed" --profile tiny \
		--hostname seeded --timezone UTC --keymap us --user tester \
		--user-gecos 'Seed User'
) || fail 'bundled-recipe setup failed'

[ "$(cat "$root_seed/usr/share/sps-test/hello")" = bundled ] ||
	fail 'bundled hello was not installed'
[ -f "$root_seed/usr/src/sps/core/hello/recipe" ] ||
	fail 'live recipe tree was not copied into the target'
grep -qx 'dir core /usr/src/sps/core 100' "$root_seed/etc/sps/repos.conf" ||
	fail 'installed repos.conf must use /usr/src/sps paths'
grep -qx 'dir extra /usr/src/sps/extra 80' "$root_seed/etc/sps/repos.conf" ||
	fail 'installed repos.conf must keep bundled extra as a dir repo'
if grep -q 'git ' "$root_seed/etc/sps/repos.conf"; then
	fail 'bundled live trees must not fall back to git'
fi

# No bundled trees: repos.conf is git clones, and --no-update must not
# require the network.
nolive=$tmp/nolive
mkdir -p "$nolive"
root_git=$tmp/root-git
mkdir -p "$root_git"
(
	unset SPS_ROOT SPS_DB SPS_CACHE SPS_BUILD SPS_CONFIG SPS_REPOS_CONFIG
	export SPS_LIVE_ROOT=$nolive
	export SPS_SETUP_DIR=$project_dir/tests/setup-fixture
	export SPS_LIBDIR=$project_dir/lib
	export PATH=$project_dir/bin:$PATH
	export SPS_ROOT=$root SPS_DB=$db SPS_CACHE=$cache SPS_BUILD=$build
	export SPS_CONFIG=$tmp/sps.conf SPS_REPOS_CONFIG=$tmp/repos.conf
	"$setup" --non-interactive --no-update --target "$root_git" \
		--profile tiny --hostname gitfallback --timezone UTC \
		--keymap us --user tester
) || fail 'git-fallback --no-update setup failed'
grep -q 'git core https://github.com/RobertFlexx/sps-core.git' \
	"$root_git/etc/sps/repos.conf" ||
	fail 'empty live root should write git core'
grep -q 'git extra https://github.com/RobertFlexx/sps-extra.git' \
	"$root_git/etc/sps/repos.conf" ||
	fail 'empty live root should write git extra'

# Later plans use the real profiles, not the fixture directory.
unset SPS_SETUP_DIR

# Guided layouts: --plan does not need --format yes; a real run does.
plan=$("$setup" --plan --target /mnt --profile minimal --disable qol-cli \
	--partition efi-root --disk /dev/vda)
contains "$plan" 'Partition:  efi-root'
contains "$plan" 'Format:     no'
contains "$plan" 'Disk:       /dev/vda'

plan=$("$setup" --plan --target /mnt --profile minimal --disable qol-cli \
	--partition efi-root --disk /dev/vda --format yes)
contains "$plan" 'Format:     yes'

set +e
"$setup" --plan --target /mnt --profile minimal --disable qol-cli \
	--install-bootloader >/dev/null 2>"$tmp/err"
st=$?
set -e
[ "$st" -eq 2 ] || fail "--install-bootloader without --disk returned $st"
contains "$(cat "$tmp/err")" '--disk'

set +e
"$setup" --non-interactive --no-update --target "$tmp/noformat" \
	--profile minimal --disable qol-cli --partition efi-root --disk /dev/vda \
	>/dev/null 2>"$tmp/err"
st=$?
set -e
[ "$st" -eq 2 ] || fail "guided without --format yes returned $st"
contains "$(cat "$tmp/err")" '--format yes'

grep -q 'remount,rw,exec' "$project_dir/lib/setup/partition.sh" ||
	fail 'setup must remount the target exec so autoconf can run conftest'
grep -q 'live gcc cannot create executables' "$setup" ||
	fail 'setup must probe live gcc before sget install'

plan=$("$setup" --plan --target /mnt --profile plasma-desktop --init systemd \
	--disable qol-cli --disable power --disable firmware)
contains "$plan" 'Init:       systemd'
contains "$plan" 'sddm'
contains "$plan" 'init-systemd'
contains "$plan" 'Services:   yes'
case $plan in
	*elogind*) fail 'plasma + systemd must not pull elogind' ;;
esac

# Power is on by default for Plasma. polkit must come from that set
# without naming elogind; sget resolves polkit's optional logind later.
plan=$("$setup" --plan --target /mnt --profile plasma-desktop --init systemd \
	--disable qol-cli --disable firmware)
contains "$plan" 'polkit'
contains "$plan" 'init-systemd'
case $plan in
	*elogind*) fail 'plasma + systemd + power must not list elogind' ;;
esac

plan=$("$setup" --plan --target /mnt --profile plasma-desktop --init openrc \
	--disable qol-cli)
contains "$plan" 'init-openrc'

set +e
"$setup" --plan --target /mnt --profile minimal --init systemd \
	--disable qol-cli --extra elogind >/dev/null 2>"$tmp/err"
st=$?
set -e
[ "$st" -eq 7 ] || fail "systemd + extra elogind returned $st"
contains "$(cat "$tmp/err")" 'elogind'

plan=$("$setup" --plan --target /mnt --profile minimal --init systemd \
	--disable qol-cli --extra sddm --services no)
contains "$plan" 'sddm'
contains "$plan" 'Services:   no'

"$setup" --plan --target /mnt --profile minimal --disable qol-cli \
	--write-answers "$tmp/svc-answers" >/dev/null
grep -qx 'services yes' "$tmp/svc-answers" || fail 'answers missing services'
grep -qx 'install-bootloader no' "$tmp/svc-answers" ||
	fail 'answers missing install-bootloader'

printf '%s\n' 'setup tests passed'
