#!/bin/bash
# Masque plugin postinstall - install prebuilt binaries
set -e

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/.masque/bin"

# Detect platform
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Normalize architecture
case "$ARCH" in
    x86_64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="arm64" ;;
esac

PLATFORM="${OS}-${ARCH}"
BIN_DIR="$PLUGIN_DIR/bin/$PLATFORM"

if [ ! -d "$BIN_DIR" ]; then
    echo "Warning: No prebuilt binaries for $PLATFORM"
    echo "Available platforms:"
    ls -1 "$PLUGIN_DIR/bin/" 2>/dev/null || echo "  (none)"
    echo ""
    echo "You can build from source with: cd $PLUGIN_DIR && zig build"
    exit 0
fi

# Create install directory
mkdir -p "$INSTALL_DIR"

# Install binaries
echo "Installing masque binaries to $INSTALL_DIR..."
for binary in "$BIN_DIR"/*; do
    if [ -f "$binary" ] && [ -x "$binary" ]; then
        name=$(basename "$binary")
        cp "$binary" "$INSTALL_DIR/$name"
        chmod +x "$INSTALL_DIR/$name"
        echo "  ✓ $name"
    fi
done

# Create sessions directory
mkdir -p "$HOME/.masque/sessions"

echo ""
echo "Masque installed successfully!"
echo "Commands: /don, /doff, /whoami"
