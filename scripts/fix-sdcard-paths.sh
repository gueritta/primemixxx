#!/bin/sh
# fix-sdcard-paths.sh — Patch SD card launcher and TKGL module for SD-only deployment.
# Run after extracting bundle to SD card.
# Usage: sudo ./scripts/fix-sdcard-paths.sh /run/media/$USER/TKGL_BOOTSTRAP

set -e
SD_ROOT="${1:-/run/media/kevin/TKGL_BOOTSTRAP}"
SD="$SD_ROOT/tkgl_bootstrap_DenonPrimeGO"
LAUNCHER="$SD/mixxx-bundle/mixxx_launcher.sh"
MOD_MIXXX="$SD/modules/mod_mixxx/tkgl_mod_mixxx.sh"

[ -f "$LAUNCHER" ] || { echo "ERROR: Launcher not found at $LAUNCHER"; exit 1; }
[ -f "$MOD_MIXXX" ] || { echo "ERROR: TKGL module not found at $MOD_MIXXX"; exit 1; }

echo "Patching launcher BUNDLE path..."
sed -i 's|^BUNDLE=/media/az01-internal/mixxx|BUNDLE=/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle|' "$LAUNCHER"

echo "Patching TKGL module..."
sed -i 's|MIXDIR=/data/mixxx|MIXDIR=/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle|' "$MOD_MIXXX"
sed -i 's|ENTRYPOINT=$MIXDIR/mixxx|ENTRYPOINT=$MIXDIR/mixxx_launcher.sh|' "$MOD_MIXXX"

echo "=== Verify ==="
grep "^BUNDLE=" "$LAUNCHER"
grep "MIXDIR\|ENTRYPOINT" "$MOD_MIXXX" | head -2
echo "DONE"
