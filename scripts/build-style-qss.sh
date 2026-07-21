#!/bin/bash -e
# build-style-qss.sh — Concatenate modular QSS files into style.qss
# Source: style_qss/_*.qss → Output: style.qss

SKIN_DIR="$(cd "$(dirname "$0")/../mixxx-bundle/skins/roundcorners" && pwd)"
MODULES=(
    "_base.qss"
    "_library.qss"
    "_controls.qss"
    "_buttons.qss"
    "_deck2.qss"
)

echo "Building style.qss from ${#MODULES[@]} modules..."

# Concatenate all modules in order
{
    for mod in "${MODULES[@]}"; do
        cat "$SKIN_DIR/style_qss/$mod"
    done
} > "$SKIN_DIR/style.qss"

echo "  → $SKIN_DIR/style.qss ($(wc -l < "$SKIN_DIR/style.qss") lines)"
echo "Done."
