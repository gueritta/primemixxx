#!/bin/sh
# Minimal stub — mounts TKGL SD card, delegates to real launcher on SD.
# This is the ONLY file on internal eMMC (alongside engine.service).
# Everything else lives on the removable SD card.
mkdir -p /media/TKGL_BOOTSTRAP
mount -L TKGL_BOOTSTRAP /media/TKGL_BOOTSTRAP 2>/dev/null || true
exec /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/tkgl-bootstrap-launcher "$@"
