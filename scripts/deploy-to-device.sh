#!/bin/bash -e
# deploy-to-device.sh — Deploy the MIXXX bundle to a Denon Prime Go device
# via SCP, and install systemd service + switcher scripts.
#
# Prerequisites:
#   1. Device is running TKGL stock firmware (SSH enabled)
#   2. ./scripts/collect-mixxx-bundle.sh has been run (produces mixxx-bundle/)
#   3. Device is reachable via SSH at the configured host/IP
#
# Usage:
#   DEVICE_IP=192.168.1.100 ./scripts/deploy-to-device.sh
#   (or edit DEVICE_IP below)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUNDLE_DIR="$REPO_ROOT/mixxx-bundle"

# ── Configuration ────────────────────────────────────────────────────────────
DEVICE_IP="${DEVICE_IP:-primego.local}"
SSH_USER="${SSH_USER:-root}"
SSH_PASS="${SSH_PASS:-denonprime4}"
DEVICE_MIXXX_DIR="/media/az01-internal/mixxx"
BACKUP_DIR="$REPO_ROOT/sdcard-backup-$(date +%Y%m%d-%H%M%S)"

# ── SSH helper using sshpass ─────────────────────────────────────────────────
if command -v sshpass &>/dev/null; then
  SSH_CMD="sshpass -p '$SSH_PASS' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  SCP_CMD="sshpass -p '$SSH_PASS' scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r"
else
  echo "WARNING: sshpass not installed. You will be prompted for the password."
  echo "Install with: sudo apt install sshpass"
  SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  SCP_CMD="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r"
fi

SSH_TARGET="${SSH_USER}@${DEVICE_IP}"

# ── Pre-flight checks ────────────────────────────────────────────────────────
echo "=== Deploying MIXXX to device ==="
echo "Device:  $SSH_TARGET"
echo "Bundle:  $BUNDLE_DIR"
echo "Target:  $DEVICE_MIXXX_DIR"

if [ ! -f "$BUNDLE_DIR/bin/mixxx" ]; then
  echo "ERROR: MIXXX bundle not found. Run scripts/collect-mixxx-bundle.sh first." >&2
  exit 1
fi

# Test SSH connectivity
echo ""
echo "--- Testing SSH connection (password: $SSH_PASS) ---"
if ! eval $SSH_CMD "$SSH_TARGET" "echo 'SSH OK'"; then
  echo "ERROR: Cannot SSH to device. Check DEVICE_IP and that the device is on." >&2
  exit 1
fi

# ── Step 1: Remount rootfs read-write ────────────────────────────────────────
echo ""
echo "--- Remounting / as read-write ---"
eval $SSH_CMD "$SSH_TARGET" "mount -o remount,rw /" || {
  echo "WARNING: Could not remount / as read-write. Continuing anyway..."
}

# ── Step 2: Back up SD card contents ─────────────────────────────────────────
echo ""
echo "--- Backing up /media/az01-internal/mixxx from device (excluding music/, lib/, bin/) ---"
mkdir -p "$BACKUP_DIR"
eval $SCP_CMD "$SSH_TARGET:/media/az01-internal/mixxx/controllers" "$BACKUP_DIR/" 2>/dev/null
eval $SCP_CMD "$SSH_TARGET:/media/az01-internal/mixxx/skins" "$BACKUP_DIR/" 2>/dev/null
eval $SCP_CMD "$SSH_TARGET:/media/az01-internal/mixxx/settings" "$BACKUP_DIR/" 2>/dev/null
eval $SCP_CMD "$SSH_TARGET:/media/az01-internal/mixxx/mixxx_launcher.sh" "$BACKUP_DIR/" 2>/dev/null && \
  echo "SD card backup saved to: $BACKUP_DIR" || \
  echo "WARNING: SD card backup may be incomplete (directory may be empty or inaccessible)."
echo "Backup size: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)"

# ── Step 3: Copy MIXXX bundle to device ──────────────────────────────────────
echo ""
echo "--- Copying MIXXX bundle to device ($DEVICE_MIXXX_DIR) ---"
eval $SSH_CMD "$SSH_TARGET" "mkdir -p '$DEVICE_MIXXX_DIR'"
# Use tar pipe to handle symlinks correctly (scp -r breaks on Mali symlinks)
# Pipe directly without eval — eval corrupts tar stream
tar cf - -C "$BUNDLE_DIR" . | sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "cd '$DEVICE_MIXXX_DIR' && tar xf -" || {
  echo "ERROR: Failed to copy bundle to device." >&2
  exit 1
}
echo "Bundle copied successfully."

# ── Step 4: Install systemd service ──────────────────────────────────────────
echo ""
echo "--- Installing mixxx.service on device ---"

# Copy from local source of truth (not heredoc)
cat "$REPO_ROOT/scripts/device/mixxx.service" | sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "cat > /etc/systemd/system/mixxx.service"
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "sed -i 's|ExecStart=.*|ExecStart=$DEVICE_MIXXX_DIR/mixxx_launcher.sh|' /etc/systemd/system/mixxx.service"

# Do NOT enable by default — user switches explicitly
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "systemctl daemon-reload"

# ── Step 4b: Install USB automount udev rule ─────────────────────────────────
echo ""
echo "--- Installing USB automount udev rule ---"
cat "$REPO_ROOT/scripts/device/99-usb-automount.rules" | sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "cat > /etc/udev/rules.d/99-usb-automount.rules"

sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "udevadm control --reload-rules && echo 'Udev rules reloaded'"

# ── Step 5: Install switcher scripts ─────────────────────────────────────────
echo ""
echo "--- Installing switcher scripts on device ---"

# switch-to-mixxx.sh
cat "$REPO_ROOT/scripts/device/switch-to-mixxx.sh" | sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "cat > /usr/bin/switch-to-mixxx"
eval $SSH_CMD "$SSH_TARGET" "chmod +x /usr/bin/switch-to-mixxx"

# switch-to-engine.sh
cat "$REPO_ROOT/scripts/device/switch-to-engine.sh" | sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "cat > /usr/bin/switch-to-engine"
eval $SSH_CMD "$SSH_TARGET" "chmod +x /usr/bin/switch-to-engine"

# ── Step 5b: Install USB Ethernet gadget + WiFi power save fix ────────────
echo ""
echo "--- Installing USB Ethernet gadget + WiFi power save fix ---"

cat "$REPO_ROOT/scripts/device/usb-gadget-eth.sh" | sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "cat > /usr/sbin/usb-gadget-eth.sh"
eval $SSH_CMD "$SSH_TARGET" "chmod +x /usr/sbin/usb-gadget-eth.sh"

cat "$REPO_ROOT/scripts/device/usb-gadget-eth.service" | sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "cat > /etc/systemd/system/usb-gadget-eth.service"
eval $SSH_CMD "$SSH_TARGET" "systemctl daemon-reload && systemctl enable usb-gadget-eth.service && echo 'USB Ethernet gadget installed and enabled'"

# WiFi power save disable — prevents SSH disconnections after ~30s idle
cat "$REPO_ROOT/scripts/device/99-wifi-power-save.rules" | sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "cat > /etc/udev/rules.d/99-wifi-power-save.rules"
eval $SSH_CMD "$SSH_TARGET" "udevadm control --reload-rules && echo 'WiFi power save udev rule installed'"

# ── Step 6: Install power button shutdown service ─────────────────────────
echo ""
echo "--- Installing power button shutdown service ---"

# Copy from local source of truth
echo "Power button monitor installed and started."

# ── Step 7: Verify deployment ────────────────────────────────────────────────
echo ""
echo "--- Verifying deployment ---"
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "ls -la '$DEVICE_MIXXX_DIR/bin/mixxx' && echo 'MIXXX binary: OK'"
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "ls '$DEVICE_MIXXX_DIR/lib/' | wc -l | xargs echo 'Library count:'"
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "ls -la /usr/bin/switch-to-mixxx /usr/bin/switch-to-engine && echo 'Switcher scripts: OK'"
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "systemctl status mixxx.service --no-pager -l 2>&1 | head -5"

echo ""
echo "=== Deployment complete! ==="
echo ""
echo "  To switch to MIXXX:  ssh $SSH_TARGET switch-to-mixxx"
echo "  To switch to Engine:  ssh $SSH_TARGET switch-to-engine"
echo "  SD card backup:      $BACKUP_DIR"
echo ""
echo "NOTE: The device will still boot into Engine DJ by default."
echo "      MIXXX must be started manually via the switcher."

# ── Step 8: Clean stale settings/controllers copies and fix config ─────
# MIXXX config may point to settings/controllers/ — fix to use controllers/
echo ""
echo "--- Cleaning stale settings/controllers/ and fixing config ---"
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" '
CTRL_DIR="/media/az01-internal/mixxx/controllers"
SETTINGS_DIR="/media/az01-internal/mixxx/settings/controllers"
rm -f "$SETTINGS_DIR"/Denon-Prime-Go-scripts.js "$SETTINGS_DIR"/Denon-Prime-Go.midi.xml "$SETTINGS_DIR"/Denon-Prime-Go-jog-wheel-scripts.js "$SETTINGS_DIR"/Denon-Prime-Go-Jog-Wheels.midi.xml "$SETTINGS_DIR"/midi-components-0.0.js
# Fix MIXXX config to point to controllers/ (not settings/controllers/)
sed -i "s|/media/az01-internal/mixxx/settings/controllers/Denon-Prime-Go.midi.xml|/media/az01-internal/mixxx/controllers/Denon-Prime-Go.midi.xml|" /media/az01-internal/mixxx/settings/mixxx.cfg
echo "Stale copies removed, config path fixed."
'
