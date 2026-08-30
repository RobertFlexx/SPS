#!/bin/sh
set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd)
if [ ! -r "$project_dir/lib/common.sh" ]; then
    printf '%s\n' 'dependency tests skipped: lib/common.sh is not integrated'
    exit 0
fi

fail()
{
    printf 'test_dependencies: %s\n' "$*" >&2
    exit 1
}

contains()
{
    case $1 in
        *"$2"*) return 0 ;;
        *) fail "expected output to contain: $2" ;;
    esac
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-dependencies.XXXXXX")
trap 'rm -rf "$tmp"' 0 1 2 3 15

mkdir -p "$tmp/root" "$tmp/cache" "$tmp/db/installed" "$tmp/build" \
    "$tmp/repo/base" "$tmp/repo/lib" "$tmp/repo/tool" "$tmp/repo/app" \
    "$tmp/repo/broken" "$tmp/repo/cycle-a" "$tmp/repo/cycle-b" \
    "$tmp/fakebin"
: > "$tmp/sps.conf"
printf 'repo test %s 10\n' "$tmp/repo" > "$tmp/repos.conf"

make_recipe()
{
    recipe_dir=$1
    recipe_name=$2
    recipe_version=$3
    shift 3
    {
        printf 'name %s\n' "$recipe_name"
        printf 'version %s\n' "$recipe_version"
        printf '%s\n' 'release 1'
        printf 'description Test package %s\n' "$recipe_name"
        for recipe_record
        do
            printf '%s\n' "$recipe_record"
        done
        printf '%s\n' 'install true'
    } > "$recipe_dir/recipe"
}

make_recipe "$tmp/repo/base" base 1.0
make_recipe "$tmp/repo/lib" lib 2.1 'depend base>=1.0'
make_recipe "$tmp/repo/tool" tool 3.0
make_recipe "$tmp/repo/app" app 4.0 'depend lib>=2.0' 'builddep tool'
make_recipe "$tmp/repo/broken" broken 1.0 'depend unavailable'
make_recipe "$tmp/repo/cycle-a" cycle-a 1.0 'depend cycle-b'
make_recipe "$tmp/repo/cycle-b" cycle-b 1.0 'depend cycle-a'

SPS_ROOT=$tmp/root
SPS_DB=$tmp/db
SPS_CACHE=$tmp/cache
SPS_BUILD=$tmp/build
SPS_CONFIG=$tmp/sps.conf
SPS_REPOS_CONFIG=$tmp/repos.conf
export SPS_ROOT SPS_DB SPS_CACHE SPS_BUILD SPS_CONFIG SPS_REPOS_CONFIG

src=$project_dir/bin/src
sget=$project_dir/bin/sget
"$src" update >/dev/null

tree=$("$sget" depends app)
contains "$tree" 'app'
contains "$tree" 'lib'
contains "$tree" 'base'
case $tree in
    *tool*) fail 'ordinary depends output unexpectedly included build dependencies' ;;
esac

tree_with_build=$("$sget" depends app --build)
contains "$tree_with_build" 'tool'

plan=$("$sget" install --plan app)
plan_names=$(printf '%s\n' "$plan" |
    awk '/^  / { print $2 }')
expected_names=$(printf '%s\n' base lib tool app)
[ "$plan_names" = "$expected_names" ] ||
    fail "unexpected dependency order: $plan_names"

nodeps_plan=$("$sget" install --plan --nodeps app)
nodeps_names=$(printf '%s\n' "$nodeps_plan" |
    awk '/^  / { print $2 }')
[ "$nodeps_names" = app ] ||
    fail '--nodeps did not restrict the plan to the requested package'

if "$sget" install --plan broken > "$tmp/broken.out" 2> "$tmp/broken.err"; then
    fail 'missing dependency unexpectedly resolved'
fi
contains "$(sed -n '1,20p' "$tmp/broken.err")" "dependency 'unavailable'"

if "$sget" install --plan cycle-a > "$tmp/cycle.out" 2> "$tmp/cycle.err"; then
    fail 'dependency cycle unexpectedly resolved'
fi
contains "$(sed -n '1,20p' "$tmp/cycle.err")" 'dependency cycle:'

[ "$(awk -v version_action=compare -v version_a=1.10 -v version_b=1.9 \
    -f "$project_dir/lib/version.awk" /dev/null)" = 1 ] ||
    fail 'numeric version comparison is incorrect'
[ "$(awk -v version_action=compare -v version_a=1.0~rc1 -v version_b=1.0 \
    -f "$project_dir/lib/version.awk" /dev/null)" = -1 ] ||
    fail 'pre-release version comparison is incorrect'

mkdir -p "$tmp/db/installed/base"
{
    printf 'format\t1\n'
    printf 'name\tbase\n'
    printf 'version\t0.9\n'
    printf 'release\t1\n'
    printf 'arch\t%s\n' "$(uname -m)"
} >"$tmp/db/installed/base/meta"
: >"$tmp/db/installed/base/files"
: >"$tmp/db/installed/base/hashes"
outdated_plan=$("$sget" install --plan app)
case $outdated_plan in
    *'base 1.0-1'*) ;;
    *) fail 'outdated installed dependency was incorrectly skipped' ;;
esac
sed 's/version\t0.9/version\t1.0/' "$tmp/db/installed/base/meta" >"$tmp/base.meta"
mv "$tmp/base.meta" "$tmp/db/installed/base/meta"
skipped_plan=$("$sget" install --plan app)
case $skipped_plan in
    *'base 1.0-1'*) fail 'exact installed package was not skipped from the build plan' ;;
esac
if "$sget" install --plan base > "$tmp/explicit.out" \
    2> "$tmp/explicit.err"; then
    :
else
    fail 'planning an already-installed package failed'
fi
contains "$(cat "$tmp/explicit.out")" 'explicit'

cat > "$tmp/fakebin/mkpkg" <<'EOF_FAKE_MKPKG'
#!/bin/sh
printf "mkpkg\t%s\n" "$PWD" >> "$TEST_LOG"
name=$(awk '$1=="name" {print $2; exit}' recipe)
version=$(awk '$1=="version" {print $2; exit}' recipe)
release=$(awk '$1=="release" {print $2; exit}' recipe)
arch=$(awk '$1=="arch" {print $2; exit}' recipe)
[ -n "$arch" ] || arch=$(uname -m)
work=$PWD/.fakepkg.$$
mkdir -p "$work/.SPS"
printf "format\t1\nname\t%s\nversion\t%s\nrelease\t%s\narch\t%s\n" \
    "$name" "$version" "$release" "$arch" > "$work/.SPS/meta"
: > "$work/.SPS/files"
: > "$work/.SPS/hashes"
artifact=$PWD/$name-$version-$release-$arch.pkg.tar
tar -cf "$artifact" -C "$work" .
rm -rf "$work"
printf "%s\n" "$artifact"
EOF_FAKE_MKPKG
cat > "$tmp/fakebin/pkin" <<'EOF_FAKE_PKIN'
#!/bin/sh
printf "pkin\t%s\t%s\n" "$SPS_INSTALL_REASON" "$1" >> "$TEST_LOG"
exit 0
EOF_FAKE_PKIN
chmod +x "$tmp/fakebin/mkpkg" "$tmp/fakebin/pkin"

TEST_LOG=$tmp/install.log
export TEST_LOG
: > "$TEST_LOG"
PATH="$tmp/fakebin:$PATH" "$sget" install app > "$tmp/install.out"

[ "$(awk -F '	' '$1 == "mkpkg" { count++ } END { print count + 0 }' \
    "$TEST_LOG")" = 3 ] ||
    fail 'sget did not build exactly the unresolved packages'
[ "$(awk -F '	' '$1 == "pkin" && $2 == "dependency" { count++ }
                  END { print count + 0 }' "$TEST_LOG")" = 2 ] ||
    fail 'dependencies were not passed to pkin with dependency reason'
[ "$(awk -F '	' '$1 == "pkin" && $2 == "explicit" { count++ }
                  END { print count + 0 }' "$TEST_LOG")" = 1 ] ||
    fail 'requested package was not passed to pkin with explicit reason'

old_log_lines=$(wc -l < "$TEST_LOG" | awk '{ print $1 }')
printf '%s\n' '# changed after indexing' >> "$tmp/repo/app/recipe"
if PATH="$tmp/fakebin:$PATH" "$sget" install --nodeps app \
    > "$tmp/stale.out" 2> "$tmp/stale.err"; then
    fail 'sget built a recipe that changed after indexing'
fi
contains "$(sed -n '1,20p' "$tmp/stale.err")" 'changed since indexing'
[ "$(wc -l < "$TEST_LOG" | awk '{ print $1 }')" = "$old_log_lines" ] ||
    fail 'mkpkg or pkin ran after stale recipe detection'

printf '%s\n' 'dependency resolution and install orchestration tests passed'
