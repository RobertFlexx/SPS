#!/bin/sh

set -eu

test_dir=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 1
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
mkpkg=$project_dir/bin/mkpkg

fail()
{
	printf 'test_build: %s\n' "$*" >&2
	exit 1
}

assert_equal()
{
	assert_expected=$1
	assert_actual=$2
	assert_message=$3
	[ "$assert_expected" = "$assert_actual" ] ||
		fail "$assert_message (expected '$assert_expected', got '$assert_actual')"
}

sha256_file()
{
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{ print $1 }'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{ print $1 }'
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -sha256 "$1" | awk '{ print $NF }'
	else
		fail "no SHA-256 utility available for test fixture"
	fi
}

run_mkpkg()
{
	result=$tmp/artifact.path
	rm -f "$result"
	SPS_ROOT=$tmp/root \
	SPS_DB=$tmp/db \
	SPS_CACHE=$tmp/cache \
	SPS_BUILD=$tmp/build \
	SPS_CONFIG=/dev/null \
	SPS_REPOS_CONFIG=/dev/null \
	SPS_COMPRESSION=none \
		"$mkpkg" --artifact-file "$result" "$@" || return $?
	sed -n '1p' "$result"
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-build.XXXXXX") ||
	fail "cannot create temporary directory"
trap 'rm -rf "$tmp"' 0 HUP INT TERM

mkdir -p "$tmp/recipe" "$tmp/out" "$tmp/root"
cp "$project_dir/examples/hello/recipe" "$tmp/recipe/recipe"
cp "$project_dir/examples/hello/hello.sh" "$tmp/recipe/hello.sh"

artifact=$(run_mkpkg --no-download --output "$tmp/out" "$tmp/recipe/recipe") ||
	fail "offline hello package build failed"

expected_artifact=$tmp/out/hello-sps-1.0-1-any.pkg.tar
assert_equal "$expected_artifact" "$artifact" "mkpkg did not print the artifact path"
[ -f "$artifact" ] || fail "package archive was not created"

tar -tf "$artifact" | sed 's#^\./##' >"$tmp/members"
for member in .SPS/meta .SPS/files .SPS/hashes usr/bin/hello-sps; do
	grep -qx "$member" "$tmp/members" || fail "archive is missing $member"
done
[ ! -s "$tmp/duplicates" ] || fail "internal test error"
LC_ALL=C sort "$tmp/members" | uniq -d >"$tmp/duplicates"
[ ! -s "$tmp/duplicates" ] || fail "archive contains duplicate members"

mkdir "$tmp/extract"
tar -xf "$artifact" -C "$tmp/extract"

hello_output=$(sh "$tmp/extract/usr/bin/hello-sps")
assert_equal "hello from SPS" "$hello_output" "installed hello program returned unexpected output"

awk -F '\t' '
$1 == "format" && $2 == "1" { format = 1 }
$1 == "name" && $2 == "hello-sps" { name = 1 }
$1 == "version" && $2 == "1.0" { version = 1 }
$1 == "release" && $2 == "1" { release = 1 }
$1 == "arch" && $2 == "any" { arch = 1 }
$1 == "definition_sha256" && $2 ~ /^[0-9a-f]+$/ && length($2) == 64 {
	definition = 1
}
END { exit !(format && name && version && release && arch && definition) }
' "$tmp/extract/.SPS/meta" || fail "package metadata is incomplete"

cat >"$tmp/expected-files" <<'EOF'
usr/
usr/bin/
usr/bin/hello-sps
EOF
cmp "$tmp/expected-files" "$tmp/extract/.SPS/files" >/dev/null 2>&1 ||
	fail "package manifest is not normalized and deterministic"

expected_hash=25576de85c3f0b4dc3e7847956daf896c450318a00bb1b818869accf8fdc7268
awk -F '\t' -v expected="$expected_hash" '
$1 == "sha256" && $2 == expected && $3 == "usr/bin/hello-sps" { found = 1 }
END { exit !found }
' "$tmp/extract/.SPS/hashes" || fail "payload hash record is incorrect"

# A build must stay in its staging tree, never SPS_ROOT.
[ ! -e "$tmp/root/usr/bin/hello-sps" ] || fail "builder modified the target root"

# Bad source hashes have their own stable exit status.
mkdir "$tmp/bad-recipe" "$tmp/bad-out"
cp "$tmp/recipe/hello.sh" "$tmp/bad-recipe/hello.sh"
sed 's/sha256:2/sha256:3/' "$tmp/recipe/recipe" >"$tmp/bad-recipe/recipe"
set +e
printf 'stale\n' >"$tmp/bad-artifact"
SPS_ROOT=$tmp/root \
SPS_DB=$tmp/db \
SPS_CACHE=$tmp/cache \
SPS_BUILD=$tmp/build \
SPS_CONFIG=/dev/null \
SPS_REPOS_CONFIG=/dev/null \
SPS_COMPRESSION=none \
"$mkpkg" --artifact-file "$tmp/bad-artifact" --no-download --output "$tmp/bad-out" \
	"$tmp/bad-recipe/recipe" \
	>"$tmp/bad.stdout" 2>"$tmp/bad.stderr"
bad_status=$?
set -e
assert_equal 6 "$bad_status" "checksum failure returned the wrong status"
grep -q 'checksum mismatch' "$tmp/bad.stderr" ||
	fail "checksum diagnostic did not explain the failure"
grep -q 'expected ' "$tmp/bad.stderr" ||
	fail "checksum diagnostic omitted the expected digest"
grep -q 'got      ' "$tmp/bad.stderr" ||
	fail "checksum diagnostic omitted the actual digest"
[ ! -s "$tmp/bad.stdout" ] || fail "failed build wrote artifact path to stdout"
[ ! -e "$tmp/bad-artifact" ] || [ ! -s "$tmp/bad-artifact" ] ||
	fail "failed build left a successful artifact result"

# Local tar sources unpack below WORK. Recipe variables expand as data and
# missing arch falls back to uname -m.
mkdir -p "$tmp/tar-source/archive-hello-1.0" "$tmp/tar-recipe" "$tmp/tar-out"
cp "$tmp/recipe/hello.sh" "$tmp/tar-source/archive-hello-1.0/hello.sh"
tar -cf "$tmp/tar-recipe/archive-hello-1.0.tar" \
	-C "$tmp/tar-source" archive-hello-1.0
archive_hash=$(sha256_file "$tmp/tar-recipe/archive-hello-1.0.tar")
cat >"$tmp/tar-recipe/recipe.in" <<'EOF'
name        archive-hello
version     1.0
release     1
description Exercises local tar extraction and default architecture
source      ${name}-${version}.tar
hash        sha256:SOURCE_HASH
install     mkdir -p "$PKG/usr/bin"
install     cp hello.sh "$PKG/usr/bin/archive-hello"
install     chmod 755 "$PKG/usr/bin/archive-hello"
EOF
sed "s/SOURCE_HASH/$archive_hash/" "$tmp/tar-recipe/recipe.in" >"$tmp/tar-recipe/recipe"

tar_artifact=$(run_mkpkg --no-download --output "$tmp/tar-out" "$tmp/tar-recipe/recipe") ||
	fail "local tar source build failed"
default_arch=$(uname -m)
assert_equal "$tmp/tar-out/archive-hello-1.0-1-$default_arch.pkg.tar" \
	"$tar_artifact" "default architecture or metadata expansion is incorrect"
tar -xOf "$tar_artifact" ./usr/bin/archive-hello >"$tmp/archive-hello.out" 2>/dev/null ||
	tar -xOf "$tar_artifact" usr/bin/archive-hello >"$tmp/archive-hello.out" ||
	fail "archive-source payload is missing"
assert_equal "hello from SPS" "$(sh "$tmp/archive-hello.out")" \
	"archive-source payload returned unexpected output"

# --build-root must expose the root as SYSROOT and put its bin dirs first on
# PATH for every build phase.
mkdir -p "$tmp/sysroot-recipe" "$tmp/sysroot-out" "$tmp/buildroot/usr/bin" \
	"$tmp/buildroot/bin"
touch "$tmp/buildroot/usr/bin/sysroot-marker" "$tmp/buildroot/bin/bin-marker"
cat >"$tmp/sysroot-recipe/recipe" <<'EOF'
name        sysroot-probe
version     1.0
release     1
arch        any
description Confirms --build-root env isolation
install     mkdir -p "$PKG/usr/share/sysroot-probe"
install     printf '%s\n' "${SYSROOT-}" >"$PKG/usr/share/sysroot-probe/sysroot"
install     printf '%s\n' "$PATH" >"$PKG/usr/share/sysroot-probe/path"
EOF
sysroot_artifact=$(run_mkpkg --no-download --build-root "$tmp/buildroot" \
	--output "$tmp/sysroot-out" "$tmp/sysroot-recipe/recipe") ||
	fail "sysroot build failed"
mkdir "$tmp/sysroot-extract"
tar -xf "$sysroot_artifact" -C "$tmp/sysroot-extract"
assert_equal "$tmp/buildroot" \
	"$(cat "$tmp/sysroot-extract/usr/share/sysroot-probe/sysroot")" \
	"SYSROOT was not set to the build root"
sysroot_path=$(cat "$tmp/sysroot-extract/usr/share/sysroot-probe/path")
case $sysroot_path in
	"$tmp/buildroot/usr/bin:$tmp/buildroot/bin:"*|*/run:"$tmp/buildroot/usr/bin:$tmp/buildroot/bin:"*) : ;;
	*) fail "build root bin dirs were not on PATH ahead of the host ($sysroot_path)" ;;
esac

[ ! -e "$tmp/buildroot/usr/share/sysroot-probe" ] ||
	fail "build root was modified by the build"

[ ! -e "$tmp/root/usr/share/sysroot-probe" ] ||
	fail "builder modified the target root with a build root"

# When SPS_ROOT is a target disk, gcc must find libraries pkin already
# installed there. Copying host libasound onto the live ISO would only
# paper over alsa-utils; the next package would fail the same way.
if command -v gcc >/dev/null 2>&1; then
	mkdir -p "$tmp/root/usr/include" "$tmp/root/usr/lib64/ossl-modules" \
		"$tmp/link-recipe" "$tmp/link-out"
	cat >"$tmp/root/usr/include/spsprobe.h" <<'EOF'
int sps_probe_lib(void);
EOF
	cat >"$tmp/spsprobe.c" <<'EOF'
int sps_probe_lib(void) { return 0; }
EOF
	gcc -shared -fPIC -o "$tmp/root/usr/lib64/libspsprobe.so" \
		"$tmp/spsprobe.c" ||
		fail "could not build the target-root probe library"
	cat >"$tmp/link-recipe/recipe" <<'EOF'
name        target-sysroot-probe
version     1.0
release     1
arch        any
description Confirms SPS_ROOT is searched for headers and libraries
configure   printf '%s\n' "${PKG_CONFIG_SYSROOT_DIR-}" >"$WORK/sysroot"
configure   printf '%s\n' "$LIBRARY_PATH" >"$WORK/libpath"
configure   printf '%s\n' '#include <spsprobe.h>' 'int main(void){return sps_probe_lib();}' >"$WORK/probe.c"
configure   gcc "$WORK/probe.c" -lspsprobe -o "$WORK/probe"
install     mkdir -p "$PKG/usr/share/target-sysroot-probe" "$PKG/usr/bin"
install     cp "$WORK/sysroot" "$WORK/libpath" "$PKG/usr/share/target-sysroot-probe/"
install     cp "$WORK/probe" "$PKG/usr/bin/target-sysroot-probe"
install     chmod 755 "$PKG/usr/bin/target-sysroot-probe"
EOF
	link_artifact=$(run_mkpkg --no-download --output "$tmp/link-out" \
		"$tmp/link-recipe/recipe") ||
		fail "target-root library probe failed to build"
	mkdir "$tmp/link-extract"
	tar -xf "$link_artifact" -C "$tmp/link-extract"
	assert_equal "$tmp/root" \
		"$(cat "$tmp/link-extract/usr/share/target-sysroot-probe/sysroot")" \
		"PKG_CONFIG_SYSROOT_DIR was not set to SPS_ROOT"
	case "$(cat "$tmp/link-extract/usr/share/target-sysroot-probe/libpath")" in
		"$tmp/root/usr/lib64:"*) : ;;
		*) fail "LIBRARY_PATH did not start with the target libdir" ;;
	esac
	[ -x "$tmp/link-extract/usr/bin/target-sysroot-probe" ] ||
		fail "probe binary was not staged"
	# The .so lives only under SPS_ROOT, so a successful link means gcc
	# searched the target rather than the live /usr/lib64.

	# Autoconf AC_CHECK_LIB often unsets LDFLAGS and invokes `gcc`
	# from PATH. The wrapper named gcc must still find the target lib.
	mkdir -p "$tmp/wrap-recipe" "$tmp/wrap-out"
	cat >"$tmp/wrap-recipe/recipe" <<'EOF'
name        target-cc-wrapper-probe
version     1.0
release     1
arch        any
description Confirms PATH gcc injects SPS_ROOT -L even without LDFLAGS
configure   unset LDFLAGS CFLAGS CPPFLAGS LIBRARY_PATH
configure   printf '%s\n' '#include <spsprobe.h>' 'int main(void){return sps_probe_lib();}' >"$WORK/probe.c"
configure   gcc "$WORK/probe.c" -lspsprobe -o "$WORK/probe"
configure   sed -n '1,20p' "$CC" >"$WORK/ccwrap"
install     mkdir -p "$PKG/usr/bin" "$PKG/usr/share/target-cc-wrapper-probe"
install     cp "$WORK/probe" "$PKG/usr/bin/target-cc-wrapper-probe"
install     cp "$WORK/ccwrap" "$PKG/usr/share/target-cc-wrapper-probe/gcc"
install     chmod 755 "$PKG/usr/bin/target-cc-wrapper-probe"
EOF
	wrap_artifact=$(run_mkpkg --no-download --output "$tmp/wrap-out" \
		"$tmp/wrap-recipe/recipe") ||
		fail "target-root gcc wrapper probe failed to build"
	mkdir "$tmp/wrap-extract"
	tar -xf "$wrap_artifact" -C "$tmp/wrap-extract"
	[ -x "$tmp/wrap-extract/usr/bin/target-cc-wrapper-probe" ] ||
		fail "wrapper probe binary was not staged"
	grep -q SPS_HOST_LD_LIBRARY_PATH \
		"$tmp/wrap-extract/usr/share/target-cc-wrapper-probe/gcc" ||
		fail "gcc wrapper must restore the host LD_LIBRARY_PATH"

	# CPython's check_extension_modules *runs* _sqlite3.so. Linking is
	# not enough: the loader must find the sqlite in SPS_ROOT, not the
	# live disc. Host gcc must not see that LD_LIBRARY_PATH.
	mkdir -p "$tmp/run-recipe" "$tmp/run-out"
	cat >"$tmp/run-recipe/recipe" <<'EOF'
name        target-runtime-lib-probe
version     1.0
release     1
arch        any
description Confirms just-built binaries load libraries from SPS_ROOT
configure   printf '%s\n' "$LD_LIBRARY_PATH" >"$WORK/ldpath"
configure   printf '%s\n' "$SPS_TARGET_LIBRARY_PATH" >"$WORK/targetld"
configure   printf '%s\n' "${OPENSSL_MODULES-}" >"$WORK/osslmod"
configure   printf '%s\n' '#include <spsprobe.h>' 'int main(void){return sps_probe_lib();}' >"$WORK/probe.c"
configure   gcc "$WORK/probe.c" -lspsprobe -o "$WORK/probe"
configure   "$WORK/probe"
install     mkdir -p "$PKG/usr/share/target-runtime-lib-probe" "$PKG/usr/bin"
install     cp "$WORK/ldpath" "$WORK/targetld" "$WORK/osslmod" "$PKG/usr/share/target-runtime-lib-probe/"
install     cp "$WORK/probe" "$PKG/usr/bin/target-runtime-lib-probe"
install     chmod 755 "$PKG/usr/bin/target-runtime-lib-probe"
EOF
	run_artifact=$(run_mkpkg --no-download --output "$tmp/run-out" \
		"$tmp/run-recipe/recipe") ||
		fail "target-root runtime library probe failed (just-built binaries must load SPS_ROOT libs)"
	mkdir "$tmp/run-extract"
	tar -xf "$run_artifact" -C "$tmp/run-extract"
	case "$(cat "$tmp/run-extract/usr/share/target-runtime-lib-probe/ldpath")" in
		"$tmp/root/usr/lib64:"*) : ;;
		*) fail "LD_LIBRARY_PATH did not start with the target libdir" ;;
	esac
	assert_equal "$tmp/root/usr/lib64:$tmp/root/usr/lib:$tmp/root/lib64:$tmp/root/lib" \
		"$(cat "$tmp/run-extract/usr/share/target-runtime-lib-probe/targetld")" \
		"SPS_TARGET_LIBRARY_PATH was not the target libdirs"
	assert_equal "$tmp/root/usr/lib64/ossl-modules" \
		"$(cat "$tmp/run-extract/usr/share/target-runtime-lib-probe/osslmod")" \
		"OPENSSL_MODULES was not the target OpenSSL provider directory"
	[ -x "$tmp/run-extract/usr/bin/target-runtime-lib-probe" ] ||
		fail "runtime probe binary was not staged"
fi

# Autoconf configure requires GNU m4 on PATH. sget installs m4 into
# SPS_ROOT first; mkpkg must search that /usr/bin ahead of the live disc.
mkdir -p "$tmp/root/usr/bin" "$tmp/m4-recipe" "$tmp/m4-out"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$tmp/root/usr/bin/m4"
chmod 755 "$tmp/root/usr/bin/m4"
cat >"$tmp/m4-recipe/recipe" <<'EOF'
name        target-m4-path-probe
version     1.0
release     1
arch        any
description Confirms SPS_ROOT/usr/bin is on PATH so autoconf can find m4
configure   command -v m4 >"$WORK/m4"
configure   printf '%s\n' "$PATH" >"$WORK/path"
configure   m4 >/dev/null
install     mkdir -p "$PKG/usr/share/target-m4-path-probe"
install     cp "$WORK/m4" "$WORK/path" "$PKG/usr/share/target-m4-path-probe/"
EOF
m4_artifact=$(run_mkpkg --no-download --output "$tmp/m4-out" \
	"$tmp/m4-recipe/recipe") ||
	fail "target-root m4 PATH probe failed (autoconf needs GNU m4 on PATH)"
mkdir "$tmp/m4-extract"
tar -xf "$m4_artifact" -C "$tmp/m4-extract"
assert_equal "$tmp/root/usr/bin/m4" \
	"$(cat "$tmp/m4-extract/usr/share/target-m4-path-probe/m4")" \
	"configure did not find m4 from SPS_ROOT/usr/bin"
case "$(cat "$tmp/m4-extract/usr/share/target-m4-path-probe/path")" in
	"$tmp/root/usr/bin:"*|*/run:"$tmp/root/usr/bin:"*) : ;;
	*) fail "SPS_ROOT/usr/bin was not on PATH ahead of the host" ;;
esac

printf '%s\n' 'test_build: ok'
