#!/bin/sh
# dev-test-bootstrap.sh — One-shot manual bootstrap for Phase 1 testing.
# Run on the device after inserting the SD card.
# Usage: ssh root@DEVICE 'sh /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/dev-test-bootstrap.sh'

set -e
echo "=== Phase 1: Manual Bootstrap Test ==="

# Mount SD card if not already mounted
if ! mountpoint -q /media/TKGL_BOOTSTRAP 2>/dev/null; then
    echo "Mounting SD card..."
    mkdir -p /media/TKGL_BOOTSTRAP
    mount -L TKGL_BOOTSTRAP /media/TKGL_BOOTSTRAP || {
        echo "ERROR: Cannot mount SD card. Check it's inserted."
        exit 1
    fi
fi

TKGL_ROOT=/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO

if [ ! -d "$TKGL_ROOT" ]; then
    echo "ERROR: TKGL bootstrap not found at $TKGL_ROOT"
    exit 1
fi

echo "SD card mounted. Running bootstrap..."
"$TKGL_ROOT/scripts/tkgl_bootstrap"
echo "=== Bootstrap complete ==="
