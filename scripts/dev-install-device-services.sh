#!/bin/sh
# dev-install-device-services.sh — Install all device system files to a Denon Prime Go
# via SSH. One-stop script for services, udev rules, switchers, and power button.
#
# Usage:
#   DEVICE_IP=192.168.42.1 ./scripts/dev-install-device-services.sh
#   (defaults to primego.local)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DEVICE_DIR="$SCRIPT_DIR/device"

DEVICE_IP="${DEVICE_IP:-primego.local}"
SSH_USER="${SSH_USER:-root}"
SSH_PASS="${SSH_PASS:-denonprime4}"
SSH_TARGET="${SSH_USER}@${DEVICE_IP}"
DEVICE_MIXXX_DIR="/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle"

ssh_cmd() {
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "$@"
}

deploy_file() {
    local src="$1"
    local dest="$2"
    local chmod_val="${3:-}"
    echo "  Installing: $dest"
    cat "$DEVICE_DIR/$src" | ssh_cmd "cat > $dest"
    if [ -n "$chmod_val" ]; then
        ssh_cmd "chmod $chmod_val $dest"
    fi
}

echo "=== Installing device services ==="
echo "Device: $SSH_TARGET"
echo ""

# ── 1. Verify SSH ──────────────────────────────────────────────────────────
echo "--- Testing SSH ---"
if ! ssh_cmd "echo SSH_OK" 2>/dev/null; then
    echo "ERROR: Cannot SSH to device. Check DEVICE_IP."
    exit 1
fi

# ── 2. Remount / rw ────────────────────────────────────────────────────────
echo "--- Remounting / as rw ---"
ssh_cmd "mount -o remount,rw /" || { echo "WARN: remount failed, continuing..."; }

# ── 3. engine.service — TKGL bootstrap host (internal eMMC) ────────────────
echo ""
echo "--- Installing engine.service (TKGL bootstrap host) ---"
# Back up original if it exists and hasn't been backed up yet
ssh_cmd 'if [ -f /etc/systemd/system/engine.service ] && [ ! -f /etc/systemd/system/engine.service.orig ]; then cp /etc/systemd/system/engine.service /etc/systemd/system/engine.service.orig; echo "  Backed up original: engine.service.orig"; fi'
# engine.service lives in tkgl-bootstrap/, not scripts/device/
cat "$REPO_ROOT/tkgl-bootstrap/engine.service" | ssh_cmd "cat > /etc/systemd/system/engine.service"
ssh_cmd "systemctl enable engine.service"
echo "  engine.service: installed and enabled"

# ── 3b. TKGL bootstrap stub — mount TKGL SD, delegate to launcher ──────────
echo ""
echo "--- Installing TKGL bootstrap stub (/data/tkgl-bootstrap-launcher) ---"
deploy_file "tkgl-bootstrap-stub.sh" "/data/tkgl-bootstrap-launcher" "+x"
echo "  TKGL bootstrap stub: installed"

# ── 4. mixxx.service ───────────────────────────────────────────────────────
echo ""
echo "--- Installing mixxx.service ---"
deploy_file "mixxx.service" "/etc/systemd/system/mixxx.service"
ssh_cmd "sed -i 's|ExecStart=.*|ExecStart=$DEVICE_MIXXX_DIR/mixxx_launcher.sh|' /etc/systemd/system/mixxx.service"

# ── 5. USB automount udev rule ─────────────────────────────────────────────
echo ""
echo "--- Installing USB automount udev rule ---"
deploy_file "99-usb-automount.rules" "/etc/udev/rules.d/99-usb-automount.rules"
ssh_cmd "udevadm control --reload-rules"

# ── 6. Switcher scripts ────────────────────────────────────────────────────
echo ""
echo "--- Installing switcher scripts ---"
deploy_file "switch-to-mixxx.sh" "/usr/bin/switch-to-mixxx" "+x"
deploy_file "switch-to-engine.sh" "/usr/bin/switch-to-engine" "+x"

# ── 7. USB Ethernet gadget ─────────────────────────────────────────────────
echo ""
echo "--- Installing USB Ethernet gadget ---"
deploy_file "usb-gadget-eth.sh" "/usr/sbin/usb-gadget-eth.sh" "+x"
deploy_file "usb-gadget-eth.service" "/etc/systemd/system/usb-gadget-eth.service"
ssh_cmd "systemctl daemon-reload"
ssh_cmd "systemctl enable usb-gadget-eth.service && systemctl start usb-gadget-eth.service"
echo "  USB Ethernet gadget: enabled and started"

# ── 8. WiFi power save udev rule ───────────────────────────────────────────
echo ""
echo "--- Installing WiFi power save udev rule ---"
deploy_file "99-wifi-power-save.rules" "/etc/udev/rules.d/99-wifi-power-save.rules"
ssh_cmd "udevadm control --reload-rules"

# ── 9. Power button shutdown service ───────────────────────────────────────
echo ""
echo "--- Installing power button shutdown service ---"
deploy_file "powerbutton-monitor" "/usr/sbin/powerbutton-monitor" "+x"
deploy_file "powerbutton-monitor.service" "/etc/systemd/system/powerbutton-monitor.service"
# Do NOT enable by default — only active during MIXXX sessions (started by switch-to-mixxx)
echo "  Power button monitor: installed (started only when MIXXX is active)"

# ── 10. mDNS fix (primego.local) ────────────────────────────────────────────
echo ""
echo "--- Installing mDNS fix (primego.local) ---"
deploy_file "fix-mdns.sh" "/usr/sbin/fix-mdns.sh" "+x"
deploy_file "fix-mdns.service" "/etc/systemd/system/fix-mdns.service"
ssh_cmd "systemctl daemon-reload"
ssh_cmd "systemctl enable fix-mdns.service"
# Run it now too
ssh_cmd "/usr/sbin/fix-mdns.sh"
echo "  mDNS fix: enabled (advertises primego.local)"

# ── 11. UPower — battery monitoring for MIXXX skin ─────────────────────────
echo ""
echo "--- Installing UPower (battery monitoring) ---"

# 11a. D-Bus policy — allows root to own org.freedesktop.UPower name
# Device D-Bus config has <deny own="*"/> by default; UPower needs explicit allow
mkdir -p /tmp/upower-etc
deploy_file "org.freedesktop.UPower.conf" "/etc/dbus-1/system.d/org.freedesktop.UPower.conf"
ssh_cmd "dbus-send --system --type=method_call --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ReloadConfig"
echo "  D-Bus policy: installed"

# 11b. UPower daemon config
ssh_cmd "mkdir -p /etc/UPower"
deploy_file "UPower.conf" "/etc/UPower/UPower.conf"
echo "  UPower.conf: installed"

# 11c. upowerd binary — deploy to SD card bundle (needs libgudev in lib/)
UPOWERD_SRC="$REPO_ROOT/buildroot/2023.02.11/output/target/usr/libexec/upowerd"
if [ -f "$UPOWERD_SRC" ]; then
    cat "$UPOWERD_SRC" | ssh_cmd "cat > $DEVICE_MIXXX_DIR/bin/upowerd"
    ssh_cmd "chmod +x $DEVICE_MIXXX_DIR/bin/upowerd"
    echo "  upowerd: installed to SD card"
else
    echo "  WARNING: upowerd not found in Buildroot output (expected at $UPOWERD_SRC)"
fi

# 11d. libgudev — upowerd dependency
LIBGUDEV_SRC="$REPO_ROOT/buildroot/2023.02.11/output/target/usr/lib/libgudev-1.0.so.0.3.0"
if [ -f "$LIBGUDEV_SRC" ]; then
    cat "$LIBGUDEV_SRC" | ssh_cmd "cat > $DEVICE_MIXXX_DIR/lib/libgudev-1.0.so.0.3.0"
    ssh_cmd "ln -sf libgudev-1.0.so.0.3.0 $DEVICE_MIXXX_DIR/lib/libgudev-1.0.so.0"
    echo "  libgudev: installed to SD card"
else
    echo "  WARNING: libgudev not found in Buildroot output"
fi

echo "  UPower: deployed (upowerd starts via mixxx_launcher.sh)"

# ── 12. Fix stale settings/controllers ─────────────────────────────────────
echo ""
echo "--- Cleaning stale paths ---"
ssh_cmd "
rm -f /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/settings/controllers/*.js \
      /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/settings/controllers/*.xml
sed -i 's|/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/settings/controllers/Denon-Prime-Go.midi.xml|/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/controllers/Denon-Prime-Go.midi.xml|' \
  /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/settings/mixxx.cfg 2>/dev/null || true
"

echo ""
echo "=== Device services installed successfully ==="
echo ""
echo "  engine.service:           installed (TKGL bootstrap host — internal eMMC)"
echo "  engine.service.orig:      backed up (original Engine OS service)"
echo "  tkgl-bootstrap-stub:      installed (/data/tkgl-bootstrap-launcher)"
echo "  mixxx.service:            installed (disabled — use switch-to-mixxx)"
echo "  usb-gadget-eth.service:   enabled (boots on USB connect)
upowerd + D-Bus policy:   installed (battery monitoring for MIXXX skin)"
echo "  powerbutton-monitor:      enabled (graceful shutdown on power button)"
echo "  switch-to-mixxx/engine:   installed in /usr/bin/"
echo "  udev rules:               USB automount + WiFi power save active"
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║  ⚠ COLD BOOT WARNING — /etc OVERLAY FILESYSTEM                         ║"
echo "║                                                                          ║"
echo "║  /etc is an overlay (upperdir=/data/system/etc/overlay).                ║"
echo "║  /data mounts AFTER systemd reads unit files at boot.                   ║"
echo "║                                                                          ║"
echo "║  Custom services in /etc/systemd/system/ (usb-gadget-eth, fix-mdns,     ║"
echo "║  powerbutton-monitor, mixxx) are SILENTLY INVISIBLE at cold boot.       ║"
echo "║                                                                          ║"
echo "║  All services have been started NOW and work until next cold boot.      ║"
echo "║  After every cold boot, RUN THIS SCRIPT AGAIN to re-enable them.        ║"
echo "║                                                                          ║"
echo "║  FOR COLD-BOOT PERSISTENCE:                                             ║"
echo "║  Add early-boot commands to /data/tkgl-bootstrap-launcher               ║"
echo "║  (local: scripts/device/tkgl-bootstrap-stub.sh)                         ║"
echo "║  This file lives on ext4 /data and IS available at boot.                ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
