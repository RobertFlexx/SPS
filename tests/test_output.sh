#!/bin/sh
# Artifact handoff, live build output, and fetch command construction.

set -eu

case $0 in */*) test_dir=${0%/*} ;; *) test_dir=. ;; esac
project_dir=$(CDPATH= cd "$test_dir/.." 2>/dev/null && pwd) || exit 1
mkpkg=$project_dir/bin/mkpkg

fail()
{
	printf 'test_output: %s\n' "$*" >&2
	exit 1
}

contains()
{
	case $1 in
		*"$2"*) return 0 ;;
		*) fail "expected output to contain '$2'" ;;
	esac
}

omits()
{
	case $1 in
		*"$2"*) fail "output unexpectedly contained '$2'" ;;
	esac
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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sps-test-output.XXXXXX") || fail mktemp
trap 'rm -rf "$tmp"' 0 HUP INT TERM

export SPS_ROOT=$tmp/root
export SPS_DB=$tmp/db
export SPS_CACHE=$tmp/cache
export SPS_BUILD=$tmp/build
export SPS_CONFIG=/dev/null
export SPS_REPOS_CONFIG=/dev/null
export SPS_LIBDIR=$project_dir/lib
export SPS_COMPRESSION=none
PATH=$project_dir/bin:$PATH
export PATH
mkdir -p "$tmp/root" "$tmp/out" "$tmp/repo"

run_env()
{
	SPS_ROOT=$tmp/root SPS_DB=$tmp/db SPS_CACHE=$tmp/cache \
	SPS_BUILD=$tmp/build SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null \
	SPS_LIBDIR=$project_dir/lib SPS_COMPRESSION=none \
		"$@"
}

# --- mkpkg --artifact-file on success ---
mkdir -p "$tmp/ok"
cat >"$tmp/ok/recipe" <<'EOF'
name        stream-ok
version     1.0
release     1
arch        any
description Artifact handoff success
build       printf '%s\n' BUILD-LINE-ONE
build       printf '%s\n' BUILD-LINE-TWO
install     mkdir -p "$PKG/usr/share"
install     printf '%s\n' ok >"$PKG/usr/share/stream-ok"
EOF

printf 'stale-success\n' >"$tmp/out/result"
run_env "$mkpkg" --artifact-file "$tmp/out/result" --no-download \
	--output "$tmp/out" "$tmp/ok/recipe" \
	>"$tmp/ok.stdout" 2>"$tmp/ok.stderr" || fail 'successful mkpkg failed'
expected=$tmp/out/stream-ok-1.0-1-any.pkg.tar
[ -f "$expected" ] || fail 'package archive was not created'
[ "$(sed -n '1p' "$tmp/out/result")" = "$expected" ] ||
	fail "artifact file did not contain the package path"
[ "$(wc -l <"$tmp/out/result" | awk '{ print $1 }')" = 1 ] ||
	fail 'artifact file was not a single pathname'
omits "$(cat "$tmp/ok.stdout")" "$expected"
contains "$(cat "$tmp/ok.stdout")" BUILD-LINE-ONE
contains "$(cat "$tmp/ok.stdout")" BUILD-LINE-TWO
contains "$(cat "$tmp/ok.stderr")" 'mkpkg: stream-ok 1.0-1'
contains "$(cat "$tmp/ok.stderr")" 'mkpkg: running build phase'
contains "$(cat "$tmp/ok.stderr")" 'mkpkg: built stream-ok-1.0-1-any.pkg.tar'
omits "$(cat "$tmp/ok.stdout")" 'mkpkg:'

# Direct human mode must not require another frontend, and --print-artifact
# keeps the old stdout pathname contract when a script asks for it.
run_env "$mkpkg" --print-artifact --no-download --output "$tmp/out-print" \
	"$tmp/ok/recipe" >"$tmp/print.stdout" 2>"$tmp/print.stderr" ||
	fail '--print-artifact build failed'
print_path=$(awk 'NF { path = $0 } END { print path }' "$tmp/print.stdout")
[ "$print_path" = "$tmp/out-print/stream-ok-1.0-1-any.pkg.tar" ] ||
	fail '--print-artifact did not print the archive path'

# --- failed build does not commit a result ---
mkdir -p "$tmp/fail"
cat >"$tmp/fail/recipe" <<'EOF'
name        stream-fail
version     1.0
release     1
arch        any
description Artifact handoff failure
build       printf '%s\n' BUILD-FAIL-LINE
build       printf '%s\n' "runtime.c:381:17: error: 'struct context' has no member named 'state'" >&2
build       exit 1
install     mkdir -p "$PKG/usr/share"
install     printf '%s\n' fail >"$PKG/usr/share/stream-fail"
EOF

printf 'stale-failure\n' >"$tmp/out/fail-result"
set +e
run_env "$mkpkg" --artifact-file "$tmp/out/fail-result" --no-download \
	--output "$tmp/out" "$tmp/fail/recipe" \
	>"$tmp/fail.stdout" 2>"$tmp/fail.stderr"
fail_status=$?
set -e
[ "$fail_status" -eq 10 ] || fail "failed build returned $fail_status"
contains "$(cat "$tmp/fail.stdout")" BUILD-FAIL-LINE
contains "$(cat "$tmp/fail.stderr")" "has no member named 'state'"
contains "$(cat "$tmp/fail.stderr")" 'mkpkg: build phase failed'
[ ! -e "$tmp/out/fail-result" ] || [ ! -s "$tmp/out/fail-result" ] ||
	fail 'failed build left a successful artifact result'

# --- fetch command construction; no public network ---
mkdir -p "$tmp/fakebin" "$tmp/fetch"
payload=$tmp/payload.dat
printf 'downloaded-bytes\n' >"$payload"
payload_hash=$(sha256_file "$payload")
cat >"$tmp/fetch/recipe" <<EOF
name        fetchpkg
version     1.0
release     1
arch        any
description Download command construction
source      https://example.invalid/payload.dat
hash        sha256:$payload_hash
install     mkdir -p "\$PKG/usr/share"
install     cp "\$SRC/payload.dat" "\$PKG/usr/share/payload.dat"
EOF

cat >"$tmp/fakebin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_LOG"
out=
prev=
for arg
do
	if [ "$prev" = -o ]; then
		out=$arg
	fi
	prev=$arg
done
[ -n "$out" ] || exit 2
cp "$FAKE_PAYLOAD" "$out"
EOF
chmod +x "$tmp/fakebin/curl"

CURL_LOG=$tmp/curl.log
FAKE_PAYLOAD=$payload
export CURL_LOG FAKE_PAYLOAD
: >"$CURL_LOG"
PATH="$tmp/fakebin:$PATH" run_env "$mkpkg" --artifact-file "$tmp/out/fetch-result" \
	--output "$tmp/out" "$tmp/fetch/recipe" \
	>"$tmp/fetch.stdout" 2>"$tmp/fetch.stderr" || fail 'fake-curl fetch build failed'
contains "$(cat "$tmp/fetch.stderr")" 'mkpkg: fetching payload.dat'
contains "$(cat "$tmp/fetch.stderr")" 'mkpkg: checksum ok'
contains "$(cat "$CURL_LOG")" '-fL'
contains "$(cat "$CURL_LOG")" '-sS'
omits "$(cat "$CURL_LOG")" ' -# '
[ "$(sed -n '1p' "$tmp/out/fetch-result")" = \
	"$tmp/out/fetchpkg-1.0-1-any.pkg.tar" ] ||
	fail 'fetched package did not publish its artifact path'

# Cached source must not invoke the downloader again.
: >"$CURL_LOG"
PATH="$tmp/fakebin:$PATH" run_env "$mkpkg" --artifact-file "$tmp/out/fetch-result2" \
	--output "$tmp/out2" "$tmp/fetch/recipe" \
	>"$tmp/fetch2.stdout" 2>"$tmp/fetch2.stderr" || fail 'cached source rebuild failed'
[ ! -s "$CURL_LOG" ] || fail 'cached source rebuild invoked curl'
contains "$(cat "$tmp/fetch2.stderr")" 'mkpkg: source cache hit payload.dat'

# Download failure must stay visible and must not publish an artifact.
cat >"$tmp/fakebin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_LOG"
printf '%s\n' 'curl: (22) The requested URL returned error: 404' >&2
exit 22
EOF
chmod +x "$tmp/fakebin/curl"
printf 'stale-download\n' >"$tmp/out/dlfail-result"
rm -rf "$tmp/cache/sources"
mkdir -p "$tmp/cache/sources"
set +e
PATH="$tmp/fakebin:$PATH" run_env "$mkpkg" --artifact-file "$tmp/out/dlfail-result" \
	--output "$tmp/out-dlfail" "$tmp/fetch/recipe" \
	>"$tmp/dlfail.stdout" 2>"$tmp/dlfail.stderr"
dl_status=$?
set -e
[ "$dl_status" -eq 9 ] || fail "download failure returned $dl_status"
contains "$(cat "$tmp/dlfail.stderr")" 'download failed'
[ ! -e "$tmp/out/dlfail-result" ] || [ ! -s "$tmp/out/dlfail-result" ] ||
	fail 'download failure left a successful artifact result'

# --- sget live output, cache, quiet, verbose, dependencies ---
mkdir -p "$tmp/repo/libbar" "$tmp/repo/foo" "$tmp/repo/broken" "$tmp/repo/quietpkg"
cat >"$tmp/repo/libbar/recipe" <<'EOF'
name        libbar
version     2.1
release     1
arch        any
description Dependency with live build output
build       printf '%s\n' BUILD-LINE-ONE
build       printf '%s\n' BUILD-LINE-TWO
install     mkdir -p "$PKG/usr/share/sps-test"
install     printf '%s\n' libbar >"$PKG/usr/share/sps-test/libbar"
EOF
cat >"$tmp/repo/foo/recipe" <<'EOF'
name        foo
version     4.7
release     2
arch        any
description Root package with a dependency
depend      libbar
build       printf '%s\n' FOO-BUILD-LINE
install     mkdir -p "$PKG/usr/share/sps-test"
install     printf '%s\n' foo >"$PKG/usr/share/sps-test/foo"
EOF
cat >"$tmp/repo/quietpkg/recipe" <<'EOF'
name        quietpkg
version     1.0
release     1
arch        any
description Quiet-mode build output
build       printf '%s\n' QUIET-SHOULD-HIDE
install     mkdir -p "$PKG/usr/share/sps-test"
install     printf '%s\n' quiet >"$PKG/usr/share/sps-test/quietpkg"
EOF
cat >"$tmp/repo/broken/recipe" <<'EOF'
name        broken
version     1.0
release     1
arch        any
description Build failure through sget
build       printf '%s\n' BROKEN-BUILD-LINE
build       printf '%s\n' "runtime.c:381:17: error: 'struct context' has no member named 'state'" >&2
build       exit 1
install     mkdir -p "$PKG/usr/share/sps-test"
install     printf '%s\n' broken >"$PKG/usr/share/sps-test/broken"
EOF
printf 'repo test %s 10\n' "$tmp/repo" >"$tmp/repos.conf"
: >"$tmp/sps.conf"
export SPS_CONFIG=$tmp/sps.conf
export SPS_REPOS_CONFIG=$tmp/repos.conf
rm -rf "$tmp/db" "$tmp/cache/packages" "$tmp/root/usr"
mkdir -p "$tmp/db/installed" "$tmp/cache/packages" "$tmp/root"
: >"$tmp/db/owners"
: >"$tmp/db/world"
: >"$tmp/db/history"

src update >/dev/null
sget install foo >"$tmp/sget.stdout" 2>"$tmp/sget.stderr" ||
	fail 'sget install foo failed'
sget_all=$(cat "$tmp/sget.stdout"; cat "$tmp/sget.stderr")
contains "$sget_all" 'install libbar 2.1-1'
contains "$sget_all" 'install foo 4.7-2'
contains "$sget_all" BUILD-LINE-ONE
contains "$sget_all" BUILD-LINE-TWO
contains "$sget_all" FOO-BUILD-LINE
contains "$sget_all" 'mkpkg: built libbar-2.1-1-any.pkg.tar'
contains "$sget_all" 'pkin: installed libbar 2.1-1'
contains "$sget_all" 'pkin: installed foo 4.7-2'
[ "$(cat "$tmp/root/usr/share/sps-test/foo")" = foo ] || fail 'foo payload missing'

# Cached binary package: no build phases, no fake progress.
sget install --reinstall foo >"$tmp/cache.stdout" 2>"$tmp/cache.stderr" ||
	fail 'cached reinstall failed'
cache_all=$(cat "$tmp/cache.stdout"; cat "$tmp/cache.stderr")
contains "$cache_all" 'sget: using cached foo-4.7-2-any.pkg.tar'
omits "$cache_all" FOO-BUILD-LINE
omits "$cache_all" 'running build phase'

# Failed sget build keeps the compiler diagnostic and a nonzero status.
set +e
sget install broken >"$tmp/broken.stdout" 2>"$tmp/broken.stderr"
broken_status=$?
set -e
[ "$broken_status" -eq 10 ] || fail "sget failed build returned $broken_status"
broken_all=$(cat "$tmp/broken.stdout"; cat "$tmp/broken.stderr")
contains "$broken_all" BROKEN-BUILD-LINE
contains "$broken_all" "has no member named 'state'"
contains "$broken_all" 'mkpkg: build phase failed'
contains "$broken_all" 'sget: failed to build broken 1.0-1'

# Quiet mode hides routine build output; failure still dumps the log.
sget -q install quietpkg >"$tmp/quiet.stdout" 2>"$tmp/quiet.stderr" ||
	fail 'quiet install failed'
quiet_all=$(cat "$tmp/quiet.stdout"; cat "$tmp/quiet.stderr")
contains "$quiet_all" 'install quietpkg 1.0-1'
contains "$quiet_all" 'pkin: installed quietpkg 1.0-1'
omits "$quiet_all" QUIET-SHOULD-HIDE
omits "$quiet_all" 'running build phase'

set +e
sget -q install --reinstall --nodeps broken >"$tmp/qfail.stdout" 2>"$tmp/qfail.stderr"
qfail_status=$?
set -e
[ "$qfail_status" -eq 10 ] || fail "quiet failed build returned $qfail_status"
qfail_all=$(cat "$tmp/qfail.stdout"; cat "$tmp/qfail.stderr")
contains "$qfail_all" BROKEN-BUILD-LINE
contains "$qfail_all" 'sget: failed to build broken 1.0-1'

# Verbose mode reports cache and recipe decisions without wrapping compiler lines.
sget -v install --reinstall foo >"$tmp/verbose.stdout" 2>"$tmp/verbose.stderr" ||
	fail 'verbose reinstall failed'
contains "$(cat "$tmp/verbose.stderr")" 'sget: selected '
contains "$(cat "$tmp/verbose.stderr")" 'sget: binary cache hit'

# Interrupted mkpkg must not leave a successful artifact indication.
mkdir -p "$tmp/slow"
cat >"$tmp/slow/recipe" <<'EOF'
name        slowpkg
version     1.0
release     1
arch        any
description Interrupt during build
build       printf '%s\n' started >"$SPS_ROOT/build-started"
build       sleep 5
install     mkdir -p "$PKG/usr/share"
install     printf '%s\n' slow >"$PKG/usr/share/slowpkg"
EOF
printf 'stale-int\n' >"$tmp/out/int-result"
# Background jobs ignore SIGINT in some shells, so this uses TERM. mkpkg's
# TERM and INT traps both exit through the same cleanup path.
SPS_ROOT=$tmp/root SPS_DB=$tmp/db SPS_CACHE=$tmp/cache \
SPS_BUILD=$tmp/build SPS_CONFIG=/dev/null SPS_REPOS_CONFIG=/dev/null \
SPS_LIBDIR=$project_dir/lib SPS_COMPRESSION=none \
	"$mkpkg" --artifact-file "$tmp/out/int-result" --no-download \
	--output "$tmp/out-int" "$tmp/slow/recipe" \
	>"$tmp/int.stdout" 2>"$tmp/int.stderr" &
int_pid=$!
i=0
while [ "$i" -lt 20 ]; do
	if [ -f "$tmp/root/build-started" ]; then
		break
	fi
	sleep 1
	i=$((i + 1))
done
[ -f "$tmp/root/build-started" ] ||
	fail 'slow build did not start before interrupt'
kill -TERM "$int_pid" 2>/dev/null || :
set +e
wait "$int_pid"
int_status=$?
set -e
[ "$int_status" -ne 0 ] || fail 'interrupted mkpkg returned success'
[ ! -e "$tmp/out/int-result" ] || [ ! -s "$tmp/out/int-result" ] ||
	fail 'interrupted mkpkg left a successful artifact result'

printf '%s\n' 'test_output: ok'
