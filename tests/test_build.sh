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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-build.XXXXXX") ||
	fail "cannot create temporary directory"
trap 'rm -rf "$tmp"' 0 HUP INT TERM

mkdir -p "$tmp/recipe" "$tmp/out" "$tmp/root"
cp "$project_dir/examples/hello/recipe" "$tmp/recipe/recipe"
cp "$project_dir/examples/hello/hello.sh" "$tmp/recipe/hello.sh"

artifact=$(
	SPS_ROOT=$tmp/root \
	SPS_DB=$tmp/db \
	SPS_CACHE=$tmp/cache \
	SPS_BUILD=$tmp/build \
	SPS_CONFIG=/dev/null \
	SPS_REPOS_CONFIG=/dev/null \
	SPS_COMPRESSION=none \
	"$mkpkg" --no-download --output "$tmp/out" "$tmp/recipe/recipe"
) || fail "offline hello package build failed"

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
END { exit !(format && name && version && release && arch) }
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
SPS_ROOT=$tmp/root \
SPS_DB=$tmp/db \
SPS_CACHE=$tmp/cache \
SPS_BUILD=$tmp/build \
SPS_CONFIG=/dev/null \
SPS_REPOS_CONFIG=/dev/null \
SPS_COMPRESSION=none \
"$mkpkg" --no-download --output "$tmp/bad-out" "$tmp/bad-recipe/recipe" \
	>"$tmp/bad.stdout" 2>"$tmp/bad.stderr"
bad_status=$?
set -e
assert_equal 6 "$bad_status" "checksum failure returned the wrong status"
grep -q 'checksum failure' "$tmp/bad.stderr" ||
	fail "checksum diagnostic did not explain the failure"

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

tar_artifact=$(
	SPS_ROOT=$tmp/root \
	SPS_DB=$tmp/db \
	SPS_CACHE=$tmp/cache \
	SPS_BUILD=$tmp/build \
	SPS_CONFIG=/dev/null \
	SPS_REPOS_CONFIG=/dev/null \
	SPS_COMPRESSION=none \
	"$mkpkg" --no-download --output "$tmp/tar-out" "$tmp/tar-recipe/recipe"
) || fail "local tar source build failed"
default_arch=$(uname -m)
assert_equal "$tmp/tar-out/archive-hello-1.0-1-$default_arch.pkg.tar" \
	"$tar_artifact" "default architecture or metadata expansion is incorrect"
tar -xOf "$tar_artifact" ./usr/bin/archive-hello >"$tmp/archive-hello.out" 2>/dev/null ||
	tar -xOf "$tar_artifact" usr/bin/archive-hello >"$tmp/archive-hello.out" ||
	fail "archive-source payload is missing"
assert_equal "hello from SPS" "$(sh "$tmp/archive-hello.out")" \
	"archive-source payload returned unexpected output"

printf '%s\n' 'test_build: ok'
