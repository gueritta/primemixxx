#!/bin/sh
# uninstall-device.sh — Inverse of install-device.sh.
# Removes TKGL boot hook from internal eMMC, restores original engine.service.
# Run this ONCE on the device when you want to return to stock Engine OS.
#
# Usage (from device):
#   sh /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/uninstall-device.sh

set -e

echo "=============================================="
echo "  TKGL BOOT HOOK UNINSTALL"
echo "=============================================="
echo ""
echo "This will remove the MIXXX boot hook from internal eMMC"
echo "and restore the original Engine OS service."
echo ""
echo "⚠  MIXXX will no longer auto-start on boot."
echo "   Remove the SD card to boot into stock Engine OS."
echo ""

printf "Are you sure you want to uninstall the boot hook? [y/N] "
read -r CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

echo ""

# ── Optional services ──────────────────────────────────────────────────────
KEEP_USB_GADGET="n"
KEEP_POWERBUTTON="n"
KEEP_MDNS="n"
KEEP_WIFI_RULES="n"

printf "Keep USB Ethernet gadget? (SSH access via USB, useful for recovery) [Y/n] "
read -r ANS
[ "$ANS" != "n" ] && [ "$ANS" != "N" ] && KEEP_USB_GADGET="y"

printf "Keep power button monitor? (graceful shutdown on power button press) [Y/n] "
read -r ANS
[ "$ANS" != "n" ] && [ "$ANS" != "N" ] && KEEP_POWERBUTTON="y"

printf "Keep mDNS fix? (primego.local hostname advertisement) [Y/n] "
read -r ANS
[ "$ANS" != "n" ] && [ "$ANS" != "N" ] && KEEP_MDNS="y"

printf "Keep WiFi powersave off rule? (prevents SSH dropouts over WiFi) [Y/n] "
read -r ANS
[ "$ANS" != "n" ] && [ "$ANS" != "N" ] && KEEP_WIFI_RULES="y"

echo ""
echo "=== Uninstalling TKGL boot hook ==="

# Remount rootfs read-write
mount -o remount,rw / 2>/dev/null || true

# ── 1. Stop MIXXX if running ───────────────────────────────────────────────
echo "Stopping MIXXX..."
systemctl stop mixxx-app.service 2>/dev/null || true
systemctl stop mixxx.service 2>/dev/null || true

# ── 2. Remove TKGL bootstrap stub ──────────────────────────────────────────
echo "Removing bootstrap stub..."
rm -f /data/tkgl-bootstrap-launcher
echo "  Removed: /data/tkgl-bootstrap-launcher"

# ── 3. Restore original engine.service ─────────────────────────────────────
echo "Restoring engine.service..."
if [ -f /etc/systemd/system/engine.service.orig ]; then
    cp /etc/systemd/system/engine.service.orig /etc/systemd/system/engine.service
    echo "  Restored: engine.service.orig → engine.service"
else
    echo "  WARN: No engine.service.orig found!"
    echo "  Removing TKGL engine.service — Engine OS will fall back to default."
    rm -f /etc/systemd/system/engine.service
    echo "  Removed: /etc/systemd/system/engine.service"
fi

# ── 4. Reload systemd ──────────────────────────────────────────────────────
systemctl daemon-reload

# ── 5. Remove optional services (if user chose) ────────────────────────────
if [ "$KEEP_USB_GADGET" != "y" ]; then
    echo "Removing USB Ethernet gadget..."
    rm -f /usr/sbin/usb-gadget-eth.sh
    rm -f /etc/systemd/system/usb-gadget-eth.service
    echo "  Removed"
fi

if [ "$KEEP_POWERBUTTON" != "y" ]; then
    echo "Removing power button monitor..."
    rm -f /usr/sbin/powerbutton-monitor
    rm -f /etc/systemd/system/powerbutton-monitor.service
    echo "  Removed"
fi

if [ "$KEEP_MDNS" != "y" ]; then
    echo "Removing mDNS fix..."
    rm -f /usr/sbin/fix-mdns.sh
    rm -f /etc/systemd/system/fix-mdns.service
    echo "  Removed"
fi

if [ "$KEEP_WIFI_RULES" != "y" ]; then
    echo "Removing WiFi powersave rule..."
    rm -f /etc/udev/rules.d/99-wifi-power-save.rules
    echo "  Removed"
fi

systemctl daemon-reload
udevadm control --reload-rules 2>/dev/null || true

# ── 6. Restart engine.service ──────────────────────────────────────────────
echo "Restarting Engine OS..."
systemctl restart engine.service 2>/dev/null || true

echo ""
echo "=============================================="
echo "  UNINSTALL COMPLETE"
echo "=============================================="
echo ""
echo "  TKGL boot hook removed. Engine OS will boot normally."
echo ""
if [ "$KEEP_USB_GADGET" = "y" ]; then echo "  ✅ USB Ethernet gadget KEPT"; fi
if [ "$KEEP_POWERBUTTON" = "y" ]; then echo "  ✅ Power button monitor KEPT"; fi
if [ "$KEEP_MDNS" = "y" ]; then echo "  ✅ mDNS fix KEPT"; fi
if [ "$KEEP_WIFI_RULES" = "y" ]; then echo "  ✅ WiFi powersave rule KEPT"; fi
echo ""
echo "  SD card bundle (/media/az01-internal/mixxx/) is NOT removed — you can delete it manually."
