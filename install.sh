#!/bin/sh
# install.sh — install gitop and gitc to ~/.local/bin (or $INSTALL_DIR)
#
# Usage:
#   ./install.sh
#   INSTALL_DIR=/usr/local/bin sudo ./install.sh
#
# One-liner from a release tarball or cloned repo:
#   curl -fsSL https://raw.githubusercontent.com/pike00/git-flock/main/install.sh | sh

set -e

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# Check dependencies.
if ! command -v flock >/dev/null 2>&1; then
    printf 'error: flock(1) is required but not found.\n' >&2
    printf '  Linux:  usually ships with util-linux (already present on most distros)\n' >&2
    printf '  macOS:  brew install util-linux\n' >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    printf 'error: git is required but not found.\n' >&2
    exit 1
fi

# Locate bin/ relative to this script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"

if [ ! -d "$BIN_DIR" ]; then
    printf 'error: bin/ directory not found at %s\n' "$BIN_DIR" >&2
    printf 'Run this script from the git-flock repo root.\n' >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"

for tool in gitop gitc; do
    src="$BIN_DIR/$tool"
    if [ ! -f "$src" ]; then
        printf 'error: %s not found at %s\n' "$tool" "$src" >&2
        exit 1
    fi
    cp "$src" "$INSTALL_DIR/$tool"
    chmod +x "$INSTALL_DIR/$tool"
    printf 'installed %s -> %s/%s\n' "$tool" "$INSTALL_DIR" "$tool"
done

# Warn if INSTALL_DIR is not in PATH.
case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        printf '\nNote: %s is not in your PATH.\n' "$INSTALL_DIR"
        printf 'Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):\n'
        printf '  export PATH="$HOME/.local/bin:$PATH"\n'
        ;;
esac

printf '\nDone. Try: gitop --help\n'
