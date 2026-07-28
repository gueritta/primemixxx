#!/bin/sh
# install-device.sh — One-shot install of TKGL boot hook to internal eMMC.
# Run this ONCE on the device after extracting the SD card bundle.
# After this, MIXXX auto-launches on every boot when the SD card is inserted.
#
# Usage (from device, or via SSH from SD card):
#   sh /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/install-device.sh

set -e

SD_ROOT="/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO"

echo "=== Installing TKGL boot hook to internal eMMC ==="

# Remount rootfs read-write
mount -o remount,rw / 2>/dev/null || true

# Install stub to /data (internal eMMC)
echo "Installing bootstrap stub..."
cp "$SD_ROOT/tkgl-bootstrap-stub.sh" /data/tkgl-bootstrap-launcher
chmod +x /data/tkgl-bootstrap-launcher

# Install engine.service (back up original first)
echo "Installing engine.service..."
if [ -f /etc/systemd/system/engine.service ] && [ ! -f /etc/systemd/system/engine.service.orig ]; then
    cp /etc/systemd/system/engine.service /etc/systemd/system/engine.service.orig
    echo "  Backed up original: engine.service.orig"
fi
cp "$SD_ROOT/engine.service" /etc/systemd/system/engine.service
systemctl daemon-reload
systemctl enable engine.service

echo ""
echo "=== Done! ==="
echo "The device will now auto-launch MIXXX on boot when the SD card is inserted."
echo "Remove the SD card to boot into stock Engine OS."
echo ""

# ── Optional services ──────────────────────────────────────────────────────
echo "=== Optional device services ==="
echo ""
echo "These add convenience features that work with or without MIXXX:"

printf "Install USB Ethernet gadget? (SSH via USB cable, always-on connectivity) [Y/n] "
read -r ANS
if [ "$ANS" != "n" ] && [ "$ANS" != "N" ]; then
    echo "Installing USB Ethernet gadget..."
    cp "$SD_ROOT/usb-gadget-eth.sh" /usr/sbin/usb-gadget-eth.sh
    chmod +x /usr/sbin/usb-gadget-eth.sh
    cp "$SD_ROOT/usb-gadget-eth.service" /etc/systemd/system/usb-gadget-eth.service
    systemctl daemon-reload
    systemctl enable usb-gadget-eth.service
    echo "  USB Ethernet gadget: installed and enabled"
fi

printf "Install power button monitor? (graceful shutdown on power button press) [Y/n] "
read -r ANS
if [ "$ANS" != "n" ] && [ "$ANS" != "N" ]; then
    echo "Installing power button monitor..."
    cp "$SD_ROOT/powerbutton-monitor" /usr/sbin/powerbutton-monitor
    chmod +x /usr/sbin/powerbutton-monitor
    cp "$SD_ROOT/powerbutton-monitor.service" /etc/systemd/system/powerbutton-monitor.service
    systemctl daemon-reload
    systemctl enable powerbutton-monitor.service
    echo "  Power button monitor: installed and enabled"
fi

printf "Install mDNS fix? (advertises primego.local instead of buildroot.local) [Y/n] "
read -r ANS
if [ "$ANS" != "n" ] && [ "$ANS" != "N" ]; then
    echo "Installing mDNS fix..."
    cp "$SD_ROOT/fix-mdns.sh" /usr/sbin/fix-mdns.sh
    chmod +x /usr/sbin/fix-mdns.sh
    cp "$SD_ROOT/fix-mdns.service" /etc/systemd/system/fix-mdns.service
    systemctl daemon-reload
    systemctl enable fix-mdns.service
    echo "  mDNS fix: installed and enabled"
fi

printf "Install WiFi powersave off rule? (prevents SSH dropouts over WiFi) [Y/n] "
read -r ANS
if [ "$ANS" != "n" ] && [ "$ANS" != "N" ]; then
    echo "Installing WiFi powersave rule..."
    cp "$SD_ROOT/99-wifi-power-save.rules" /etc/udev/rules.d/99-wifi-power-save.rules
    udevadm control --reload-rules 2>/dev/null || true
    echo "  WiFi powersave rule: installed"
fi

echo ""
echo "Reboot now? Run: reboot"
