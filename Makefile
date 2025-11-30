# --- Configuration ---
# Install to user's local directory (no sudo required)
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man/man1

# Bash Completion Configuration (XDG)
BASH_COMPLETION_DIR ?= $(PREFIX)/share/bash-completion/completions
BASH_COMPLETION_SRC = completions.bash

# Zsh Completion Configuration (XDG)
ZSH_COMPLETION_DIR ?= $(PREFIX)/share/zsh/site-functions
ZSH_COMPLETION_SRC = _k8s-image-auditor

# Files
SCRIPT_SRC = k8s-image-auditor.sh
BINARY_NAME = k8s-image-auditor
MAN_SRC = k8s-image-auditor.1.md
MAN_OUT = k8s-image-auditor.1

# --- Targets ---

.PHONY: all clean install uninstall check lint test

all: $(MAN_OUT)

# Compile Markdown to Manpage (requires pandoc)
$(MAN_OUT): $(MAN_SRC)
	@echo "Building man page..."
	pandoc $(MAN_SRC) -s -t man -o $(MAN_OUT)

# Check for dependencies
check:
	@command -v pandoc >/dev/null 2>&1 || { echo >&2 "Error: pandoc is required for docs. Run 'brew install pandoc'"; exit 1; }

# Linting (ShellCheck)
lint:
	@echo "Running ShellCheck..."
	@command -v shellcheck >/dev/null 2>&1 || { echo >&2 "Error: shellcheck not found. Run 'brew install shellcheck'"; exit 1; }
	shellcheck $(SCRIPT_SRC)
	@echo "✅ Code looks clean!"

# Testing (Bats)
test:
	@echo "Running Unit Tests..."
	@command -v bats >/dev/null 2>&1 || { echo >&2 "Error: bats not found. Run 'brew install bats-core'"; exit 1; }
	bats tests/

# Install
install: check all
	@echo "Installing binary to $(BINDIR)..."
	@mkdir -p $(BINDIR)
	@install -m 755 $(SCRIPT_SRC) $(BINDIR)/$(BINARY_NAME)

	@echo "Installing man page to $(MANDIR)..."
	@mkdir -p $(MANDIR)
	@install -m 644 $(MAN_OUT) $(MANDIR)/$(MAN_OUT)

	@echo "Detecting shell to install appropriate completions..."
	@CUR_SHELL=$$(basename $$SHELL); \
	if [ "$$CUR_SHELL" = "zsh" ]; then \
		echo "🐚 Detected Zsh. Installing Zsh completions..."; \
		mkdir -p $(ZSH_COMPLETION_DIR); \
		install -m 644 $(ZSH_COMPLETION_SRC) $(ZSH_COMPLETION_DIR)/$(ZSH_COMPLETION_SRC); \
		echo "ℹ️  Zsh users: Ensure $(ZSH_COMPLETION_DIR) is in your \$$fpath."; \
	elif [ "$$CUR_SHELL" = "bash" ]; then \
		echo "🐚 Detected Bash. Installing Bash completions..."; \
		mkdir -p $(BASH_COMPLETION_DIR); \
		install -m 644 $(BASH_COMPLETION_SRC) $(BASH_COMPLETION_DIR)/$(BINARY_NAME); \
	else \
		echo "⚠️  Unknown shell ($$CUR_SHELL). Installing BOTH completions to be safe."; \
		mkdir -p $(BASH_COMPLETION_DIR); \
		install -m 644 $(BASH_COMPLETION_SRC) $(BASH_COMPLETION_DIR)/$(BINARY_NAME); \
		mkdir -p $(ZSH_COMPLETION_DIR); \
		install -m 644 $(ZSH_COMPLETION_SRC) $(ZSH_COMPLETION_DIR)/$(ZSH_COMPLETION_SRC); \
	fi

	@echo "✅ Installation complete!"
	@# Check if the bin directory is in the user's PATH (Handle trailing slash)
	@case ":$$PATH:" in \
		*":$(BINDIR):"*|*":$(BINDIR)/:"*) ;; \
		*) echo "⚠️  WARNING: $(BINDIR) is not in your \$$PATH. Add it to your shell profile." ;; \
	esac

# Uninstall
uninstall:
	@echo "Removing binary..."
	@rm -f $(BINDIR)/$(BINARY_NAME)
	@echo "Removing man page..."
	@rm -f $(MANDIR)/$(MAN_OUT)
	@echo "Removing bash completions..."
	@rm -f $(BASH_COMPLETION_DIR)/$(BINARY_NAME)
	@echo "Removing zsh completions..."
	@rm -f $(ZSH_COMPLETION_DIR)/$(ZSH_COMPLETION_SRC)
	@echo "🗑️  Uninstalled successfully."

# Clean build artifacts
clean:
	@rm -f $(MAN_OUT)