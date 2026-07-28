#!/bin/sh
# Verifies no duplicate mapping file content across locations.
# Device reality (2026-07-21): mappings live in flat controllers/ on device,
# organized under mixxx-mapping/prime-go/ locally. TKGL is on a separate SD card.
# Symlinks to canonical are OK. Regular file copies are not.
set -e

CANONICAL="mixxx-bundle/mixxx-mapping/prime-go"
failures=0

# Check: if files exist in tkgl-bootstrap that mirror canonical, they must be symlinks
for canonical_file in "$CANONICAL"/*; do
    [ -f "$canonical_file" ] || continue
    fname=$(basename "$canonical_file")

    # Check mixxx-bundle/controllers/ (same filesystem as canonical — can be symlink)
    candidate="mixxx-bundle/controllers/$fname"
    if [ -f "$candidate" ] && [ ! -L "$candidate" ]; then
        echo "FAIL: $candidate is a regular file (should be symlink to ../mixxx-mapping/prime-go/$fname)"
        failures=$((failures + 1))
    fi

    # Check tkgl-bootstrap (separate filesystem on device — symlink may not resolve)
    # Symlink is still correct structure; flag only if regular file dupe exists
    tkgl_candidate="tkgl-bootstrap/modules/mod_mixxx/$fname"
    if [ -f "$tkgl_candidate" ] && [ ! -L "$tkgl_candidate" ]; then
        echo "WARN: $tkgl_candidate is a regular file — device has separate TKGL SD card"
        echo "      If TKGL SD card can't follow symlinks across filesystems, this is MANDATORY COPY"
        # Not a hard failure — TKGL is on a separate SD card
    elif [ -L "$tkgl_candidate" ]; then
        echo "OK: $tkgl_candidate is a symlink"
    fi
done

# Check for stray mapping regular files in tkgl-bootstrap (any .js or .midi.xml)
for f in tkgl-bootstrap/modules/mod_mixxx/*.js tkgl-bootstrap/modules/mod_mixxx/*.midi.xml; do
    [ -f "$f" ] || continue
    if [ ! -L "$f" ]; then
        fname=$(basename "$f")
        if [ -f "$CANONICAL/$fname" ]; then
            echo "INFO: $f is a regular file — may be MANDATORY COPY (separate TKGL SD card)"
        fi
    fi
done

if [ "$failures" -gt 0 ]; then
    echo "ERROR: $failures duplicate(s) found that should be symlinks (same filesystem)"
    exit 1
fi

echo "OK: No problematic duplicate mapping files"
exit 0
