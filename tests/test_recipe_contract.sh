#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
mkpkg=$project_dir/bin/mkpkg
recipe_parser=$project_dir/lib/recipe.awk

fail()
{
    printf 'test_recipe_contract: %s\n' "$*" >&2
    exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-recipe-contract.XXXXXX") ||
    fail 'cannot create temporary directory'
trap 'rm -rf "$tmp"' 0 1 2 3 15

recipe_digest=0000000000000000000000000000000000000000000000000000000000000000

parse_recipe()
{
    parse_path=$1
    awk -v recipe_repo=test -v recipe_priority=10 \
        -v recipe_path="$parse_path" -v recipe_sha256="$recipe_digest" \
        -v recipe_default_arch=testarch -f "$recipe_parser" "$parse_path"
}

expect_parse_failure()
{
    parse_label=$1
    parse_expected=$2
    parse_path=$3
    set +e
    parse_recipe "$parse_path" >"$tmp/$parse_label.out" 2>"$tmp/$parse_label.err"
    parse_status=$?
    set -e
    [ "$parse_status" -eq 2 ] ||
        fail "$parse_label returned $parse_status instead of 2"
    grep -F "$parse_expected" "$tmp/$parse_label.err" >/dev/null ||
        fail "$parse_label did not report '$parse_expected'"
}

run_builder()
{
    build_label=$1
    build_recipe=$2
    mkdir -p "$tmp/out-$build_label"
    result=$tmp/out-$build_label/artifact
    rm -f "$result"
    SPS_ROOT=$tmp/root \
    SPS_DB=$tmp/db \
    SPS_CACHE=$tmp/cache \
    SPS_BUILD=$tmp/build \
    SPS_CONFIG=/dev/null \
    SPS_REPOS_CONFIG=/dev/null \
    SPS_COMPRESSION=none \
    SPS_ARCH=testarch \
        "$mkpkg" --artifact-file "$result" --no-download \
            --output "$tmp/out-$build_label" "$build_recipe" || return $?
    sed -n '1p' "$result"
}

expect_builder_failure()
{
    build_label=$1
    build_expected=$2
    build_recipe=$3
    set +e
    run_builder "$build_label" "$build_recipe" \
        >"$tmp/$build_label.out" 2>"$tmp/$build_label.err"
    build_status=$?
    set -e
    [ "$build_status" -eq 4 ] ||
        fail "$build_label returned $build_status instead of 4"
    grep -F "$build_expected" "$tmp/$build_label.err" >/dev/null ||
        fail "$build_label did not report '$build_expected'"
}

mkdir -p "$tmp/valid"
cat >"$tmp/valid/recipe" <<'EOF_VALID'
name contract-valid
version 1.0
release 1
arch any
source source.tar
hash sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
install true
EOF_VALID
valid_record=$(parse_recipe "$tmp/valid/recipe") ||
    fail 'complete recipe was rejected by the index parser'
printf '%s\n' "$valid_record" | awk -F '\t' '
    NF == 12 && $1 == "contract-valid" && $2 == "1.0" &&
    $3 == "1" && $4 == "any" { valid=1 }
    END { exit !valid }
' || fail 'complete recipe produced the wrong index identity'

mkdir -p "$tmp/missing-install"
cat >"$tmp/missing-install/recipe" <<'EOF_MISSING_INSTALL'
name missing-install
version 1.0
release 1
arch any
EOF_MISSING_INSTALL
expect_parse_failure missing-install "missing required 'install' command" \
    "$tmp/missing-install/recipe"

mkdir -p "$tmp/missing-hash"
cat >"$tmp/missing-hash/recipe" <<'EOF_MISSING_HASH'
name missing-hash
version 1.0
release 1
arch any
source source.tar
install true
EOF_MISSING_HASH
expect_parse_failure missing-hash 'each source must have one corresponding hash' \
    "$tmp/missing-hash/recipe"

mkdir -p "$tmp/skip-hash"
cat >"$tmp/skip-hash/recipe" <<'EOF_SKIP_HASH'
name skip-hash
version 1.0
release 1
arch any
source source.tar
hash skip
install true
EOF_SKIP_HASH
expect_parse_failure skip-hash 'expected sha256:<64 hex digits>' \
    "$tmp/skip-hash/recipe"
expect_builder_failure skip-hash-builder 'unsupported source hash' \
    "$tmp/skip-hash/recipe"

mkdir -p "$tmp/duplicate-name"
cat >"$tmp/duplicate-name/recipe" <<'EOF_DUPLICATE_NAME'
name duplicate-name
name duplicate-name-again
version 1.0
release 1
arch any
install true
EOF_DUPLICATE_NAME
expect_parse_failure duplicate-name "duplicate 'name' field" \
    "$tmp/duplicate-name/recipe"

mkdir -p "$tmp/bad-arch"
cat >"$tmp/bad-arch/recipe" <<'EOF_BAD_ARCH'
name bad-arch
version 1.0
release 1
arch bad~arch
install mkdir -p "$PKG/usr/share"
install printf '%s\n' bad > "$PKG/usr/share/bad-arch"
EOF_BAD_ARCH
expect_parse_failure bad-arch "invalid architecture 'bad~arch'" \
    "$tmp/bad-arch/recipe"
expect_builder_failure bad-arch-builder "invalid arch 'bad~arch'" \
    "$tmp/bad-arch/recipe"

# Keep metadata substitution behavior identical between indexing and building,
# including a value which introduces an earlier substitution token.
mkdir -p "$tmp/expanded"
cat >"$tmp/expanded/recipe" <<'EOF_EXPANDED'
name expanded
version ${arch}
release 1
arch ${name}
install mkdir -p "$PKG/usr/share"
install printf '%s\n' expanded > "$PKG/usr/share/expanded"
EOF_EXPANDED
expanded_record=$(parse_recipe "$tmp/expanded/recipe") ||
    fail 'expanded identity was rejected by the index parser'
printf '%s\n' "$expanded_record" | awk -F '\t' '
    $1 == "expanded" && $2 == "expanded" && $3 == "1" &&
    $4 == "expanded" { valid=1 }
    END { exit !valid }
' || fail 'index-time metadata expansion is incorrect'
expanded_artifact=$(run_builder expanded "$tmp/expanded/recipe") ||
    fail 'builder disagreed with the index parser about expanded identity'
[ "$expanded_artifact" = "$tmp/out-expanded/expanded-expanded-1-expanded.pkg.tar" ] ||
    fail "builder produced an unexpected expanded identity: $expanded_artifact"

# `any` is canonical for official recipes, while `noarch` remains an accepted
# compatibility spelling in both parsers.
mkdir -p "$tmp/noarch"
cat >"$tmp/noarch/recipe" <<'EOF_NOARCH'
name noarch-compatible
version 1.0
release 1
arch noarch
install mkdir -p "$PKG/usr/share"
install printf '%s\n' noarch > "$PKG/usr/share/noarch-compatible"
EOF_NOARCH
noarch_record=$(parse_recipe "$tmp/noarch/recipe") ||
    fail 'index parser rejected the noarch compatibility spelling'
[ "$(printf '%s\n' "$noarch_record" | awk -F '\t' '{ print $4 }')" = noarch ] ||
    fail 'index parser changed the noarch compatibility spelling'
noarch_artifact=$(run_builder noarch "$tmp/noarch/recipe") ||
    fail 'builder rejected the noarch compatibility spelling'
[ "$noarch_artifact" = \
  "$tmp/out-noarch/noarch-compatible-1.0-1-noarch.pkg.tar" ] ||
    fail "builder produced an unexpected noarch identity: $noarch_artifact"

# Support trees and hook directories are visible package inputs. Refuse unsafe
# top-level forms rather than following or silently ignoring them.
mkdir -p "$tmp/support-target" "$tmp/support-link"
cat >"$tmp/support-link/recipe" <<'EOF_SUPPORT_LINK'
name support-link
version 1.0
release 1
arch any
install mkdir -p "$PKG/usr/share"
install printf '%s\n' support > "$PKG/usr/share/support-link"
EOF_SUPPORT_LINK
ln -s "$tmp/support-target" "$tmp/support-link/files"
expect_builder_failure support-link 'recipe files must be a real directory' \
    "$tmp/support-link/recipe"

mkdir -p "$tmp/bad-hook/hooks"
cat >"$tmp/bad-hook/recipe" <<'EOF_BAD_HOOK'
name bad-hook
version 1.0
release 1
arch any
install mkdir -p "$PKG/usr/share"
install printf '%s\n' hook > "$PKG/usr/share/bad-hook"
EOF_BAD_HOOK
printf '%s\n' true >"$tmp/bad-hook/hooks/not-a-hook"
expect_builder_failure bad-hook "unsupported recipe hook 'not-a-hook'" \
    "$tmp/bad-hook/recipe"

printf '%s\n' 'test_recipe_contract: ok'
