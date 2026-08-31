#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
. "$project_dir/lib/common.sh"
sps_program=test_definition_digest

fail()
{
    printf 'test_definition_digest: %s\n' "$*" >&2
    exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-definition-digest.XXXXXX") ||
    fail 'cannot create temporary directory'
trap 'rm -rf "$tmp"' 0 1 2 3 15

make_definition()
{
    definition_dir=$1
    mkdir -p "$definition_dir/files/nested" "$definition_dir/patches" \
        "$definition_dir/hooks"
    printf '%s\n' 'name digest-test' 'version 1.0' 'release 1' \
        'install true' >"$definition_dir/recipe"
    printf '%s\n' 'setting=true' >"$definition_dir/files/nested/config"
    printf '%s\n' 'patch contents' >"$definition_dir/patches/fix.patch"
    printf '%s\n' 'exit 0' >"$definition_dir/hooks/post-install"
    chmod 0750 "$definition_dir/files/nested"
    chmod 0640 "$definition_dir/files/nested/config"
}

reset_copy()
{
    rm -rf "$tmp/copy"
    cp -R "$tmp/original" "$tmp/copy"
}

expect_invalid_definition()
{
    invalid_label=$1
    if sps_definition_sha256 "$tmp/copy/recipe" \
        >"$tmp/$invalid_label.out" 2>"$tmp/$invalid_label.err"; then
        fail "$invalid_label package definition unexpectedly hashed"
    fi
}

make_definition "$tmp/original"
reset_copy
original_digest=$(sps_definition_sha256 "$tmp/original/recipe") ||
    fail 'could not hash original package definition'
copy_digest=$(sps_definition_sha256 "$tmp/copy/recipe") ||
    fail 'could not hash copied package definition'
[ "$original_digest" = "$copy_digest" ] ||
    fail 'digest embeds or otherwise depends on the absolute package path'
case $original_digest in
    [0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef]*) ;;
    *) fail 'definition digest is not lowercase hexadecimal' ;;
esac
[ "${#original_digest}" -eq 64 ] || fail 'definition digest is not SHA-256'

printf '%s\n' changed >>"$tmp/copy/files/nested/config"
[ "$(sps_definition_sha256 "$tmp/copy/recipe")" != "$original_digest" ] ||
    fail 'support file content did not affect the digest'

reset_copy
mv "$tmp/copy/patches/fix.patch" "$tmp/copy/patches/renamed.patch"
[ "$(sps_definition_sha256 "$tmp/copy/recipe")" != "$original_digest" ] ||
    fail 'support file relative path did not affect the digest'

reset_copy
chmod 0600 "$tmp/copy/files/nested/config"
[ "$(sps_definition_sha256 "$tmp/copy/recipe")" != "$original_digest" ] ||
    fail 'copied support file mode did not affect the digest'

reset_copy
ln -s ../recipe "$tmp/copy/files/recipe-link"
expect_invalid_definition symlink
grep -F 'symlink or special file' "$tmp/symlink.err" >/dev/null ||
    fail 'symlink rejection was not explained'

reset_copy
mkfifo "$tmp/copy/patches/input.fifo"
expect_invalid_definition special
grep -F 'symlink or special file' "$tmp/special.err" >/dev/null ||
    fail 'special-file rejection was not explained'

reset_copy
tab=$(printf '\tX')
tab=${tab%X}
printf '%s\n' bad >"$tmp/copy/files/bad${tab}name"
expect_invalid_definition tab
grep -F 'tab or newline' "$tmp/tab.err" >/dev/null ||
    fail 'tab-containing path rejection was not explained'

reset_copy
newline=$(printf '\nX')
newline=${newline%X}
printf '%s\n' bad >"$tmp/copy/files/bad${newline}name"
expect_invalid_definition newline
grep -F 'tab or newline' "$tmp/newline.err" >/dev/null ||
    fail 'newline-containing path rejection was not explained'

printf '%s\n' 'package definition digest tests passed'
