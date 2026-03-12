#!/bin/bash

# Claude Code Session Manager Installer
# Quick installation script with PATH integration
# Author: Shikamaru <shikamarunaraclaw@gmail.com>

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="claude-session-manager"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🤖 Claude Code Session Manager Installer"
echo "======================================="

# Check if running as root for system-wide install
if [[ $EUID -eq 0 ]]; then
    echo "Installing system-wide to $INSTALL_DIR..."
    INSTALL_TARGET="$INSTALL_DIR/$SCRIPT_NAME"
    USER_INSTALL=false
else
    # Install to user's local bin
    LOCAL_BIN="$HOME/.local/bin"
    mkdir -p "$LOCAL_BIN"
    INSTALL_TARGET="$LOCAL_BIN/$SCRIPT_NAME"
    USER_INSTALL=true
    echo "Installing to user directory: $INSTALL_TARGET"
fi

# Copy the main script
cp "$REPO_DIR/$SCRIPT_NAME" "$INSTALL_TARGET"
chmod +x "$INSTALL_TARGET"

# Create symlink to source directory for scripts
LINK_TARGET="$INSTALL_TARGET.d"
if [[ -L "$LINK_TARGET" ]]; then
    rm "$LINK_TARGET"
fi
ln -sf "$REPO_DIR" "$LINK_TARGET"

echo "✅ Installed to: $INSTALL_TARGET"
echo "✅ Source linked: $LINK_TARGET"

# Check if installation directory is in PATH
if [[ $USER_INSTALL == true ]]; then
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        echo ""
        echo "⚠️  Warning: $HOME/.local/bin is not in your PATH"
        echo "Add this to your ~/.bashrc or ~/.zshrc:"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
    fi
fi

# Run the installation setup
echo ""
echo "Running setup..."
if command -v "$SCRIPT_NAME" >/dev/null 2>&1 || [[ -x "$INSTALL_TARGET" ]]; then
    "$INSTALL_TARGET" install
else
    echo "❌ Installation failed - command not found in PATH"
    echo "Try running: $INSTALL_TARGET install"
    exit 1
fi

echo ""
echo "🎉 Installation complete!"
echo ""
echo "Usage examples:"
echo "  $SCRIPT_NAME sidebar show     # Show the Claude Code sidebar"
echo "  $SCRIPT_NAME jump waiting     # Jump to sessions needing input"
echo "  $SCRIPT_NAME list             # List all Claude Code sessions"
echo ""
echo "For help: $SCRIPT_NAME help"