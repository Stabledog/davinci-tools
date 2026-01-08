#!/bin/bash
# setup-kb.sh - Environment preparation for davinci-tools knowledge base

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="${REPO_ROOT}/docs"

echo "Setting up davinci-tools knowledge base..."

# Create docs directory if it doesn't exist
mkdir -p "$DOCS_DIR"

# Symlink DaVinci Resolve manual
RESOLVE_MANUAL="/c/Program Files/Blackmagic Design/DaVinci Resolve/Documents/DaVinci Resolve.pdf"
MANUAL_LINK="${DOCS_DIR}/DaVinci_Resolve_Manual.pdf"

if [ -f "$RESOLVE_MANUAL" ]; then
    if [ -L "$MANUAL_LINK" ]; then
        echo "Manual symlink already exists: $MANUAL_LINK"
    else
        ln -s "$RESOLVE_MANUAL" "$MANUAL_LINK"
        echo "Created symlink: $MANUAL_LINK -> $RESOLVE_MANUAL"
    fi
else
    echo "Warning: DaVinci Resolve manual not found at: $RESOLVE_MANUAL"
    echo "Please verify your DaVinci Resolve installation path."
fi

echo "Knowledge base setup complete."
