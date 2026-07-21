#!/bin/sh
# Verifies no duplicate content across the three mapping locations.
# Exit 1 if any duplicates found (excluding symlinks).
set -e

CANONICAL="mixxx-bundle/mixxx-mapping/prime-go"
LOCATIONS="$CANONICAL mixxx-bundle/controllers tkgl-bootstrap/modules/mod_mixxx"

failures=0

for canonical_file in "$CANONICAL"/*; do
    [ -f "$canonical_file" ] || continue
    fname=$(basename "$canonical_file")

    for loc in mixxx-bundle/controllers tkgl-bootstrap/modules/mod_mixxx; do
        candidate="$loc/$fname"
        if [ -f "$candidate" ] && [ ! -L "$candidate" ]; then
            echo "FAIL: $candidate is a regular file (should be a symlink to canonical)"
            failures=$((failures + 1))
        elif [ -L "$candidate" ]; then
            target=$(readlink "$candidate")
            expected="../mixxx-mapping/prime-go/$fname"
            case "$loc" in
                mixxx-bundle/controllers)
                    expected="../mixxx-mapping/prime-go/$fname"
                    ;;
                tkgl-bootstrap/modules/mod_mixxx)
                    expected="../../../mixxx-bundle/mixxx-mapping/prime-go/$fname"
                    ;;
            esac
            if [ "$target" != "$expected" ]; then
                echo "FAIL: $candidate -> $target (expected -> $expected)"
                failures=$((failures + 1))
            fi
        fi
    done
done

# Also check for stray regular files in tkgl-bootstrap that should be symlinks
for f in tkgl-bootstrap/modules/mod_mixxx/*.js tkgl-bootstrap/modules/mod_mixxx/*.midi.xml; do
    [ -f "$f" ] || continue
    if [ ! -L "$f" ]; then
        echo "FAIL: $f is a regular file in tkgl-bootstrap (mappings should only be canonical)"
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    echo "ERROR: $failures duplicate(s) found"
    exit 1
fi

echo "OK: No duplicate mapping files"
exit 0
