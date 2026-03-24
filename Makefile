PREFIX    ?= /usr/local
DESTDIR   ?=
BINDIR     = $(DESTDIR)$(PREFIX)/bin
SHARE_DIR  = $(DESTDIR)$(PREFIX)/share/vokun
BASH_COMP  = $(DESTDIR)$(PREFIX)/share/bash-completion/completions
ZSH_COMP   = $(DESTDIR)$(PREFIX)/share/zsh/site-functions
FISH_COMP  = $(DESTDIR)$(PREFIX)/share/fish/vendor_completions.d
LICENSEDIR = $(DESTDIR)$(PREFIX)/share/licenses/vokun

.PHONY: install uninstall test lint clean

install:
	@echo ":: Installing vokun to $(PREFIX)..."
	install -Dm755 vokun                     "$(BINDIR)/vokun"
	@for f in lib/*.sh; do \
		install -Dm644 "$$f" "$(SHARE_DIR)/$$f"; \
	done
	@for f in bundles/*.toml; do \
		install -Dm644 "$$f" "$(SHARE_DIR)/$$f"; \
	done
	install -Dm644 completions/vokun.bash    "$(BASH_COMP)/vokun"
	install -Dm644 completions/_vokun         "$(ZSH_COMP)/_vokun"
	install -Dm644 completions/vokun.fish    "$(FISH_COMP)/vokun.fish"
	install -Dm644 LICENSE                   "$(LICENSEDIR)/LICENSE"
	@echo ":: vokun installed successfully."

uninstall:
	@echo ":: Removing vokun from $(PREFIX)..."
	rm -f  "$(BINDIR)/vokun"
	rm -rf "$(SHARE_DIR)"
	rm -f  "$(BASH_COMP)/vokun"
	rm -f  "$(ZSH_COMP)/_vokun"
	rm -f  "$(FISH_COMP)/vokun.fish"
	rm -rf "$(LICENSEDIR)"
	@echo ":: vokun removed."

test:
	@echo ":: Running tests..."
	@if [ -d tests ] && ls tests/*.sh 1>/dev/null 2>&1; then \
		for t in tests/*.sh; do \
			echo "  -> $$t"; \
			bash "$$t" || exit 1; \
		done; \
		echo ":: All tests passed."; \
	else \
		echo ":: No test files found in tests/."; \
	fi

lint:
	@echo ":: Running shellcheck..."
	shellcheck -x -s bash vokun lib/*.sh
	@echo ":: All files pass shellcheck."

clean:
	@echo ":: Nothing to clean."
