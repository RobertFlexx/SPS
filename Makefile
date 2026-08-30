POSIX_SHELL = /bin/sh
PREFIX = /usr
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib/sps
MANDIR = $(PREFIX)/share/man
SYSCONFDIR = /etc/sps
DESTDIR =

PROGRAMS = src sget mkpkg pkin pkdel pkstat pkcheck pkmark
AWK_LIBS = common.awk config.awk db.awk deps.awk index.awk package.awk recipe.awk repository.awk relations.awk version.awk

.PHONY: all check lint install install-config clean

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
	@# Pure library modules can be parsed without an action or fixture.  The
	@# executable AWK modules validate their input in END rules, so the test
	@# suite below is their syntax + behavior check rather than invoking them
	@# against an intentionally invalid empty stream.
	@awk -f lib/common.awk </dev/null >/dev/null
	@awk -f lib/common.awk -f lib/config.awk </dev/null >/dev/null
	@awk -f lib/version.awk </dev/null >/dev/null

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

# Configuration is separate so installation never overwrites administrator
# policy. Existing files are deliberately left untouched.
install-config:
	install -d "$(DESTDIR)$(SYSCONFDIR)"
	@test -e "$(DESTDIR)$(SYSCONFDIR)/sps.conf" || \
		install -m 0644 examples/sps.conf "$(DESTDIR)$(SYSCONFDIR)/sps.conf"
	@test -e "$(DESTDIR)$(SYSCONFDIR)/repos.conf" || \
		install -m 0644 examples/repos.conf "$(DESTDIR)$(SYSCONFDIR)/repos.conf"

clean:
	@find . -type f \( -name '*.pkg.tar' -o -name '*.pkg.tar.gz' -o \
		-name '*.pkg.tar.xz' -o -name '*.pkg.tar.zst' \) -exec rm -f {} \;

