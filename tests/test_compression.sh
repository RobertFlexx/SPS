#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
mkpkg=$project_dir/bin/mkpkg
pkin=$project_dir/bin/pkin
pkdel=$project_dir/bin/pkdel

fail()
{
    printf 'test_compression: %s\n' "$*" >&2
    exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-compression.XXXXXX") ||
    fail 'cannot create temporary directory'
trap 'rm -rf "$tmp"' 0 HUP INT TERM

mkdir -p "$tmp/recipe"
cp "$project_dir/examples/hello/recipe" "$tmp/recipe/recipe"
cp "$project_dir/examples/hello/hello.sh" "$tmp/recipe/hello.sh"

for compression in gzip xz zstd; do
    command -v "$compression" >/dev/null 2>&1 || continue

    case $compression in
        gzip) suffix=.gz ;;
        xz) suffix=.xz ;;
        zstd) suffix=.zst ;;
    esac

    root=$tmp/root-$compression
    db=$tmp/db-$compression
    cache=$tmp/cache-$compression
    build=$tmp/build-$compression
    out=$tmp/out-$compression
    mkdir -p "$root" "$out"

    SPS_ROOT=$root \
    SPS_DB=$db \
    SPS_CACHE=$cache \
    SPS_BUILD=$build \
    SPS_CONFIG=/dev/null \
    SPS_REPOS_CONFIG=/dev/null \
    SPS_LIBDIR=$project_dir/lib \
        "$mkpkg" --artifact-file "$out/artifact" --no-download \
            --compression "$compression" \
            --output "$out" "$tmp/recipe/recipe" ||
        fail "$compression package build failed"
    artifact=$(sed -n '1p' "$out/artifact")

    expected=$out/hello-sps-1.0-1-any.pkg.tar$suffix
    [ "$artifact" = "$expected" ] ||
        fail "$compression build returned unexpected artifact '$artifact'"
    [ -f "$artifact" ] || fail "$compression package archive was not created"

    SPS_ROOT=$root \
    SPS_DB=$db \
    SPS_CACHE=$cache \
    SPS_BUILD=$build \
    SPS_CONFIG=/dev/null \
    SPS_REPOS_CONFIG=/dev/null \
    SPS_LIBDIR=$project_dir/lib \
        "$pkin" "$artifact" >/dev/null ||
        fail "pkin could not install $compression package"

    [ "$(sh "$root/usr/bin/hello-sps")" = 'hello from SPS' ] ||
        fail "$compression package payload is incorrect"

    SPS_ROOT=$root \
    SPS_DB=$db \
    SPS_CACHE=$cache \
    SPS_BUILD=$build \
    SPS_CONFIG=/dev/null \
    SPS_REPOS_CONFIG=/dev/null \
    SPS_LIBDIR=$project_dir/lib \
        "$pkdel" hello-sps >/dev/null ||
        fail "pkdel could not remove $compression package"
done

printf '%s\n' 'test_compression: ok'
