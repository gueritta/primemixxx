#!/bin/sh
# install-boot-hook.sh — One-shot install of TKGL boot hook to internal eMMC.
# Run this ONCE on the device after extracting the SD card bundle.
# After this, MIXXX auto-launches on every boot when the SD card is inserted.
#
# Usage (from device, or via SSH from SD card):
#   sh /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/install-boot-hook.sh

set -e

SD_ROOT="/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO"

echo "=== Installing TKGL boot hook to internal eMMC ==="

# Remount rootfs read-write
mount -o remount,rw / 2>/dev/null || true

# Install stub to /data (internal eMMC)
echo "Installing bootstrap stub..."
cp "$SD_ROOT/tkgl-bootstrap-stub.sh" /data/tkgl-bootstrap-launcher
chmod +x /data/tkgl-bootstrap-launcher

# Install engine.service
echo "Installing engine.service..."
cp "$SD_ROOT/engine.service" /etc/systemd/system/engine.service
systemctl daemon-reload
systemctl enable engine.service

echo ""
echo "=== Done! ==="
echo "The device will now auto-launch MIXXX on boot when the SD card is inserted."
echo "Remove the SD card to boot into stock Engine OS."
echo ""
echo "Reboot now? Run: reboot"
