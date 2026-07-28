#!/bin/sh
# Minimal stub — mounts TKGL SD card, delegates to real launcher on SD.
# This is the ONLY file on internal eMMC (alongside engine.service).
# Everything else lives on the removable SD card.
#
# If the SD card is not present, exit gracefully so Engine OS can start.
mkdir -p /media/TKGL_BOOTSTRAP
mount -L TKGL_BOOTSTRAP /media/TKGL_BOOTSTRAP 2>/dev/null || true
LAUNCHER=/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/tkgl-bootstrap-launcher
if [ -x "$LAUNCHER" ]; then
    exec "$LAUNCHER" "$@"
fi
# SD card not present — exit 0 so engine.service proceeds to Engine OS
exit 0
