# --- Configuration ---
# Install to user's local directory (no sudo required)
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man/man1
COMPLETION_DIR = $(PREFIX)/share/bash-completion/completions


# Files
SCRIPT_SRC = k8s-image-auditor.sh
BINARY_NAME = k8s-image-auditor
MAN_SRC = k8s-image-auditor.1.md
MAN_OUT = k8s-image-auditor.1
COMPLETION_SRC = completions.bash

# --- Targets ---

.PHONY: all clean install uninstall check lint

all: $(MAN_OUT)

# Compile Markdown to Manpage (requires pandoc)
$(MAN_OUT): $(MAN_SRC)
	@echo "Building man page..."
	pandoc $(MAN_SRC) -s -t man -o $(MAN_OUT)

# Check for dependencies
check:
	@command -v pandoc >/dev/null 2>&1 || { echo >&2 "Error: pandoc is required for docs. Run 'brew install pandoc'"; exit 1; }

# Install (User Local)
install: check all
	@echo "Installing binary to $(BINDIR)..."
	@mkdir -p $(BINDIR)
	@install -m 755 $(SCRIPT_SRC) $(BINDIR)/$(BINARY_NAME)

	@echo "Installing man page to $(MANDIR)..."
	@mkdir -p $(MANDIR)
	@install -m 644 $(MAN_OUT) $(MANDIR)/$(MAN_OUT)
	@echo "Installing shell completions..."
	@mkdir -p $(COMPLETION_DIR)
	# We rename it to match the binary name exactly so the shell finds it
	@install -m 644 $(COMPLETION_SRC) $(COMPLETION_DIR)/$(BINARY_NAME)
	@echo "✅ Installation complete!"
	@# Check if the bin directory is in the user's PATH
	@case ":$$PATH:" in \
		*":$(BINDIR):"*) ;; \
		*) echo "⚠️  WARNING: $(BINDIR) is not in your \$$PATH. Add it to your shell profile (e.g., .zshrc or .bashrc)." ;; \
	esac

# Uninstall
uninstall:
	@echo "Removing binary..."
	@rm -f $(BINDIR)/$(BINARY_NAME)
	@echo "Removing man page..."
	@rm -f $(MANDIR)/$(MAN_OUT)
	@rm -f $(COMPLETION_DIR)/$(BINARY_NAME)
	@echo "🗑️  Uninstalled successfully."

lint:
	@echo "Running ShellCheck..."
	@command -v shellcheck >/dev/null 2>&1 || { echo >&2 "Error: shellcheck not found. Run 'brew install shellcheck'"; exit 1; }
	shellcheck $(SCRIPT_SRC)
	@echo "✅ Code looks clean!"

# Clean build artifacts
clean:
	@rm -f $(MAN_OUT)