POSIX_SHELL = /bin/sh
PREFIX = /usr
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib/sps
MANDIR = $(PREFIX)/share/man
SYSCONFDIR = /etc/sps
DESTDIR =

PROGRAMS = src sget mkpkg pkin pkdel pkstat pkcheck pkmark setup mkiso
AWK_LIBS = common.awk config.awk db.awk deps.awk index.awk package.awk recipe.awk repository.awk relations.awk version.awk

.PHONY: all check lint check-version source-archive release-check \
	install install-config clean iso iso-slim iso-plasma

all:
	@printf '%s\n' "SPS is interpreted; run 'make check' or 'make install'."

check: lint
	$(POSIX_SHELL) tests/run

lint:
	@set -e; for program in $(PROGRAMS); do \
		$(POSIX_SHELL) -n bin/$$program; \
	done
	@set -e; for library in lib/*.sh; do \
		$(POSIX_SHELL) -n $$library; \
	done
	@set -e; for library in lib/setup/*.sh; do \
		[ -f $$library ] || continue; \
		$(POSIX_SHELL) -n $$library; \
	done
	@set -e; for script in lib/mkiso/initrd-init lib/mkiso/live-rc \
		lib/mkiso/live-plasma lib/mkiso/live-init lib/mkiso/udhcpc-script; do \
		[ -f $$script ] || continue; \
		$(POSIX_SHELL) -n $$script; \
	done
	@# Pure library modules can be parsed without an action or fixture.  The
	@# executable AWK modules validate their input in END rules, so the test
	@# suite below is their syntax + behavior check rather than invoking them
	@# against an intentionally invalid empty stream.
	@awk -f lib/common.awk </dev/null >/dev/null
	@awk -f lib/common.awk -f lib/config.awk </dev/null >/dev/null
	@awk -f lib/version.awk </dev/null >/dev/null

check-version:
	@LC_ALL=C awk '\
		NR == 1 && $$0 ~ /^[0-9]+\.[0-9]+\.[0-9]+$$/ { valid = 1 } \
		END { exit !(NR == 1 && valid) } \
	' VERSION || { \
		printf '%s\n' 'VERSION must contain one X.Y.Z release number' >&2; \
		exit 1; \
	}

# Build from the committed tree so untracked files and local edits can never
# enter a published source archive. gzip -n omits its timestamp and filename.
source-archive: check-version
	@set -eu; \
	version=$$(sed -n '1p' VERSION); \
	for tool in git gzip mktemp; do \
		command -v "$$tool" >/dev/null 2>&1 || { \
			printf 'source-archive: required tool not found: %s\n' "$$tool" >&2; \
			exit 1; \
		}; \
	done; \
	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { \
		printf '%s\n' 'source-archive: not inside a Git work tree' >&2; \
		exit 1; \
	}; \
	mkdir -p dist; \
	archive="dist/sps-$$version.tar.gz"; \
	tmp_tar=$$(mktemp "$${TMPDIR:-/tmp}/sps-source.XXXXXX"); \
	tmp_archive="$$archive.tmp"; \
	trap 'rm -f "$$tmp_tar" "$$tmp_archive"' 0 HUP INT TERM; \
	git archive --format=tar --prefix="sps-$$version/" \
		--output="$$tmp_tar" HEAD; \
	gzip -n -9 -c "$$tmp_tar" >"$$tmp_archive"; \
	mv "$$tmp_archive" "$$archive"; \
	printf '%s\n' "$$archive"

# Run this after creating vVERSION and before pushing the tag. It verifies
# that the tag, committed VERSION, work tree, and reproducible archive agree.
release-check: check source-archive
	@set -eu; \
	version=$$(sed -n '1p' VERSION); \
	tag="v$$version"; \
	archive="dist/sps-$$version.tar.gz"; \
	prefix="sps-$$version/"; \
	if [ -n "$$(git status --porcelain --untracked-files=normal)" ]; then \
		printf '%s\n' 'release-check: Git work tree is not clean' >&2; \
		exit 1; \
	fi; \
	git diff --check; \
	tag_commit=$$(git rev-parse -q --verify "$$tag^{commit}") || { \
		printf 'release-check: tag %s does not exist\n' "$$tag" >&2; \
		exit 1; \
	}; \
	[ "$$(git cat-file -t "$$tag")" = tag ] || { \
		printf 'release-check: tag %s is not annotated\n' "$$tag" >&2; \
		exit 1; \
	}; \
	head_commit=$$(git rev-parse HEAD); \
	[ "$$tag_commit" = "$$head_commit" ] || { \
		printf 'release-check: tag %s does not point to HEAD\n' "$$tag" >&2; \
		exit 1; \
	}; \
	gzip -t "$$archive"; \
	members=$$(mktemp "$${TMPDIR:-/tmp}/sps-members.XXXXXX"); \
	repro_tar=$$(mktemp "$${TMPDIR:-/tmp}/sps-repro.XXXXXX"); \
	repro_archive=$$(mktemp "$${TMPDIR:-/tmp}/sps-repro-gz.XXXXXX"); \
	trap 'rm -f "$$members" "$$repro_tar" "$$repro_archive"' \
		0 HUP INT TERM; \
	tar -tzf "$$archive" >"$$members"; \
	awk -v prefix="$$prefix" '\
		index($$0, prefix) != 1 { bad = 1 } \
		END { exit bad || NR == 0 } \
	' "$$members" || { \
		printf '%s\n' 'release-check: archive has an invalid member path' >&2; \
		exit 1; \
	}; \
	for required in VERSION Makefile bin/src; do \
		grep -F -x "$$prefix$$required" "$$members" >/dev/null || { \
			printf 'release-check: archive is missing %s\n' "$$required" >&2; \
			exit 1; \
		}; \
	done; \
	archive_version=$$(tar -xOzf "$$archive" "$$prefix"VERSION); \
	[ "$$archive_version" = "$$version" ] || { \
		printf '%s\n' 'release-check: archive VERSION does not match' >&2; \
		exit 1; \
	}; \
	git archive --format=tar --prefix="$$prefix" \
		--output="$$repro_tar" HEAD; \
	gzip -n -9 -c "$$repro_tar" >"$$repro_archive"; \
	cmp "$$archive" "$$repro_archive" >/dev/null || { \
		printf '%s\n' 'release-check: source archive is not reproducible' >&2; \
		exit 1; \
	}; \
	printf 'release-check: %s is ready\n' "$$archive"

install:
	install -d "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(LIBDIR)" \
		"$(DESTDIR)$(MANDIR)/man1" "$(DESTDIR)$(MANDIR)/man5"
	@set -e; for program in $(PROGRAMS); do \
		if [ -d "$(DESTDIR)$(BINDIR)/$$program" ]; then \
			printf '%s: error: %s is a directory; %s command would be shadowed\n' \
				"$0" "$(DESTDIR)$(BINDIR)/$$program" "$$program" >&2; \
			exit 1; \
		fi; \
		install -m 0755 bin/$$program "$(DESTDIR)$(BINDIR)/$$program"; \
	done
	@set -e; for library in lib/*.awk lib/*.sh; do \
		install -m 0644 $$library "$(DESTDIR)$(LIBDIR)/$${library##*/}"; \
	done
	@set -e; for page in man/*.1; do \
		install -m 0644 $$page "$(DESTDIR)$(MANDIR)/man1/$${page##*/}"; \
	done
	@set -e; for page in man/*.5; do \
		install -m 0644 $$page "$(DESTDIR)$(MANDIR)/man5/$${page##*/}"; \
	done
	install -d "$(DESTDIR)$(LIBDIR)/setup/profiles" \
		"$(DESTDIR)$(LIBDIR)/setup/sets"
	install -m 0644 lib/setup/keymaps lib/setup/timezones \
		lib/setup/locales lib/setup/shells lib/setup/extras \
		lib/setup/services \
		"$(DESTDIR)$(LIBDIR)/setup/"
	@set -e; for f in lib/setup/profiles/*.profile; do \
		install -m 0644 $$f "$(DESTDIR)$(LIBDIR)/setup/profiles/"; \
	done
	@set -e; for f in lib/setup/sets/*.set; do \
		install -m 0644 $$f "$(DESTDIR)$(LIBDIR)/setup/sets/"; \
	done
	install -d "$(DESTDIR)$(LIBDIR)/mkiso"
	@set -e; for f in lib/mkiso/*; do \
		[ -f "$$f" ] || continue; \
		case $$f in \
			*/live-init|*/initrd-init|*/live-rc|*/live-plasma|*/udhcpc-script) \
				install -m 0755 $$f "$(DESTDIR)$(LIBDIR)/mkiso/" ;; \
			*) \
				install -m 0644 $$f "$(DESTDIR)$(LIBDIR)/mkiso/" ;; \
		esac; \
	done
	install -d "$(DESTDIR)$(LIBDIR)/mkiso/systemd"
	@set -e; for f in lib/mkiso/systemd/*; do \
		[ -f "$$f" ] || continue; \
		install -m 0644 $$f "$(DESTDIR)$(LIBDIR)/mkiso/systemd/"; \
	done
	install -d "$(DESTDIR)$(LIBDIR)/setup"
	@set -e; for f in lib/setup/*.sh; do \
		[ -f "$$f" ] || continue; \
		install -m 0644 $$f "$(DESTDIR)$(LIBDIR)/setup/"; \
	done

# Configuration is separate so installation never overwrites administrator
# policy. Existing files are deliberately left untouched.
install-config:
	install -d "$(DESTDIR)$(SYSCONFDIR)"
	@test -e "$(DESTDIR)$(SYSCONFDIR)/sps.conf" || \
		install -m 0644 examples/sps.conf "$(DESTDIR)$(SYSCONFDIR)/sps.conf"
	@test -e "$(DESTDIR)$(SYSCONFDIR)/repos.conf" || \
		install -m 0644 examples/repos.conf "$(DESTDIR)$(SYSCONFDIR)/repos.conf"

# SPS Linux (Splux) live images. busybox must be a static binary; the host
# copy is usually dynamically linked and will not survive in an initramfs.
ISO_BUSYBOX ?= /tmp/sps-wave/busybox.static
ISO_CORE ?= /usr/src/sps/core
ISO_EXTRA ?= /usr/src/sps/extra
ISO_DIR ?= dist

iso:
	@test -x "$(ISO_BUSYBOX)" || { \
		printf '%s\n' "iso: static busybox not found: $(ISO_BUSYBOX)" >&2; \
		exit 1; \
	}
	mkdir -p "$(ISO_DIR)"
	bin/mkiso --output "$(ISO_DIR)/sps-live.iso" --init systemd \
		--busybox "$(ISO_BUSYBOX)" --core "$(ISO_CORE)" --extra "$(ISO_EXTRA)"

iso-slim:
	@test -x "$(ISO_BUSYBOX)" || { \
		printf '%s\n' "iso-slim: static busybox not found: $(ISO_BUSYBOX)" >&2; \
		exit 1; \
	}
	mkdir -p "$(ISO_DIR)"
	bin/mkiso --output "$(ISO_DIR)/sps-live-slim.iso" --init systemd \
		--no-seed --no-modules --busybox "$(ISO_BUSYBOX)"

iso-plasma:
	@test -x "$(ISO_BUSYBOX)" || { \
		printf '%s\n' "iso-plasma: static busybox not found: $(ISO_BUSYBOX)" >&2; \
		exit 1; \
	}
	mkdir -p "$(ISO_DIR)"
	bin/mkiso --output "$(ISO_DIR)/sps-live-plasma.iso" \
		--session plasma --init systemd \
		--busybox "$(ISO_BUSYBOX)" --core "$(ISO_CORE)" --extra "$(ISO_EXTRA)"

clean:
	@find . -type f \( -name '*.pkg.tar' -o -name '*.pkg.tar.gz' -o \
		-name '*.pkg.tar.xz' -o -name '*.pkg.tar.zst' \) -exec rm -f {} \;
