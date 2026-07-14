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
echo "--- Backing up /media/az01-internal/ from device ---"
mkdir -p "$BACKUP_DIR"
eval $SCP_CMD "$SSH_TARGET:/media/az01-internal/*" "$BACKUP_DIR/" 2>/dev/null && \
  echo "SD card backup saved to: $BACKUP_DIR" || \
  echo "WARNING: SD card backup may be incomplete (directory may be empty or inaccessible)."
echo "Backup size: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)"

# ── Step 3: Copy MIXXX bundle to device ──────────────────────────────────────
echo ""
echo "--- Copying MIXXX bundle to device ($DEVICE_MIXXX_DIR) ---"
eval $SSH_CMD "$SSH_TARGET" "mkdir -p '$DEVICE_MIXXX_DIR'"
eval $SCP_CMD "$BUNDLE_DIR"/* "$SSH_TARGET:$DEVICE_MIXXX_DIR/" || {
  echo "ERROR: Failed to copy bundle to device." >&2
  exit 1
}
echo "Bundle copied successfully."

# ── Step 4: Install systemd service ──────────────────────────────────────────
echo ""
echo "--- Installing mixxx.service on device ---"

# Read the service file template and substitute the SD card path
SERVICE_FILE="$REPO_ROOT/scripts/device/mixxx.service"

eval $SSH_CMD "$SSH_TARGET" "cat > /etc/systemd/system/mixxx.service << 'SERVICEOF'
[Unit]
Description=MIXXX DJ Software (SD Card)
After=sound.target multi-user.target
Conflicts=engine.service
Before=engine.service

[Service]
Type=simple
ExecStart=$DEVICE_MIXXX_DIR/mixxx_launcher.sh
Restart=on-failure
RestartSec=2
Environment=HOME=/root

# Environment is set by mixxx_launcher.sh, not duplicated here.
# Key env: LD_LIBRARY_PATH (SD card Qt 5.15.8), QT_QPA_EGLFS_INTEGRATION=eglfs_mali

# Real-time audio
LimitRTPRIO=99
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
SERVICEOF"

# Do NOT enable by default — user switches explicitly
eval $SSH_CMD "$SSH_TARGET" "systemctl daemon-reload"

# ── Step 4b: Install USB automount udev rule ─────────────────────────────────
echo ""
echo "--- Installing USB automount udev rule ---"
eval $SSH_CMD "$SSH_TARGET" "cat > /etc/udev/rules.d/99-usb-automount.rules << 'RULESEOF'
# Auto-mount USB storage for MIXXX music library
ACTION==\"add\", SUBSYSTEMS==\"usb\", SUBSYSTEM==\"block\", KERNEL==\"sd[a-z][0-9]\", ENV{ID_FS_USAGE}==\"filesystem\", \
  RUN{program}+=\"/usr/bin/systemd-mount --no-block --automount=yes --collect \$devnode /media/usb-%k\"

ACTION==\"remove\", SUBSYSTEMS==\"usb\", SUBSYSTEM==\"block\", KERNEL==\"sd[a-z][0-9]\", \
  RUN{program}+=\"/usr/bin/systemd-umount /media/usb-%k\", \
  RUN{program}+=\"/bin/rmdir /media/usb-%k\"
RULESEOF"

eval $SSH_CMD "$SSH_TARGET" "udevadm control --reload-rules && echo 'Udev rules reloaded'"

# ── Step 5: Install switcher scripts ─────────────────────────────────────────
echo ""
echo "--- Installing switcher scripts on device ---"

# switch-to-mixxx.sh
eval $SSH_CMD "$SSH_TARGET" "cat > /usr/bin/switch-to-mixxx << 'SWEOF'
#!/bin/bash
# Switch from Engine DJ to MIXXX
set -e

echo \"Switching to MIXXX...\"

# Remount rootfs read-write if needed
mount -o remount,rw / 2>/dev/null || true

# Stop Engine
echo \"Stopping engine.service...\"
systemctl stop engine.service 2>/dev/null || true
sleep 1

# Ensure MIXXX launcher is executable
chmod +x $DEVICE_MIXXX_DIR/mixxx_launcher.sh

# Start MIXXX
echo \"Starting mixxx.service...\"
systemctl start mixxx.service
echo \"MIXXX is now running. Use 'switch-to-engine' to go back.\"
SWEOF"
eval $SSH_CMD "$SSH_TARGET" "chmod +x /usr/bin/switch-to-mixxx"

# switch-to-engine.sh
eval $SSH_CMD "$SSH_TARGET" "cat > /usr/bin/switch-to-engine << 'SWEOF'
#!/bin/bash
# Switch from MIXXX back to Engine DJ
set -e

echo \"Switching to Engine DJ...\"

# Stop MIXXX
echo \"Stopping mixxx.service...\"
systemctl stop mixxx.service 2>/dev/null || true
sleep 1

# Start Engine
echo \"Starting engine.service...\"
systemctl start engine.service
echo \"Engine DJ is now running. Use 'switch-to-mixxx' to go back.\"
SWEOF"
eval $SSH_CMD "$SSH_TARGET" "chmod +x /usr/bin/switch-to-engine"

# ── Step 5b: Install USB Ethernet gadget ──────────────────────────────────
echo ""
echo "--- Installing USB Ethernet gadget ---"

eval $SSH_CMD "$SSH_TARGET" "cat > /usr/sbin/usb-gadget-eth.sh << 'GADGETEOF'
#!/bin/sh
GADGET_DIR=/sys/kernel/config/usb_gadget/g_ether
if [ -d \"\$GADGET_DIR\" ]; then exit 0; fi
mkdir -p \"\$GADGET_DIR\" || exit 1
echo 0x1d6b > \"\$GADGET_DIR/idVendor\"
echo 0x0104 > \"\$GADGET_DIR/idProduct\"
echo 0x0200 > \"\$GADGET_DIR/bcdDevice\"
mkdir -p \"\$GADGET_DIR/strings/0x409\"
echo \"DenonDJ\" > \"\$GADGET_DIR/strings/0x409/manufacturer\"
echo \"PRIME GO USB Ethernet\" > \"\$GADGET_DIR/strings/0x409/product\"
mkdir -p \"\$GADGET_DIR/configs/c.1/strings/0x409\"
echo \"USB Ethernet\" > \"\$GADGET_DIR/configs/c.1/strings/0x409/configuration\"
echo 500 > \"\$GADGET_DIR/configs/c.1/MaxPower\"
mkdir -p \"\$GADGET_DIR/functions/ecm.usb0\"
echo \"02:00:42:00:00:01\" > \"\$GADGET_DIR/functions/ecm.usb0/dev_addr\"
echo \"02:00:42:00:00:02\" > \"\$GADGET_DIR/functions/ecm.usb0/host_addr\"
ln -s \"\$GADGET_DIR/functions/ecm.usb0\" \"\$GADGET_DIR/configs/c.1/\"
UDC=\$(ls /sys/class/udc/ 2>/dev/null | head -1)
[ -n \"\$UDC\" ] && echo \"\$UDC\" > \"\$GADGET_DIR/UDC\"
GADGETEOF"

eval $SSH_CMD "$SSH_TARGET" "chmod +x /usr/sbin/usb-gadget-eth.sh"

eval $SSH_CMD "$SSH_TARGET" "cat > /etc/systemd/network/usb0.network << 'NETEOF'
[Match]
Name=usb0
[Network]
Address=192.168.42.1/24
DHCPServer=yes
[DHCPserver]
PoolOffset=10
PoolSize=50
EmitDNS=yes
DNS=192.168.42.1
NETEOF"

eval $SSH_CMD "$SSH_TARGET" "cat > /etc/systemd/system/usb-gadget-eth.service << 'SERVEOF'
[Unit]
Description=USB Ethernet Gadget
After=sys-kernel-config.mount
Before=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/usb-gadget-eth.sh
[Install]
WantedBy=multi-user.target
SERVEOF"

eval $SSH_CMD "$SSH_TARGET" "systemctl daemon-reload && systemctl enable usb-gadget-eth.service && echo 'USB Ethernet gadget installed and enabled'"

# ── Step 6: Deploy VDJ-Pro skin ──────────────────────────────────────────────
echo ""
echo "--- Deploying VDJ-Pro skin ---"
eval $SSH_CMD "$SSH_TARGET" "mkdir -p '$DEVICE_MIXXX_DIR/settings/skins/vdj-pro'"
eval $SCP_CMD "$BUNDLE_DIR/skins/vdj-pro/." "$SSH_TARGET:$DEVICE_MIXXX_DIR/settings/skins/vdj-pro/" || {
  echo "ERROR: Failed to copy VDJ-Pro skin to device." >&2
  exit 1
}
echo "VDJ-Pro skin deployed successfully."

# ── Step 7: Verify deployment ────────────────────────────────────────────────
echo ""
echo "--- Verifying deployment ---"
eval $SSH_CMD "$SSH_TARGET" "ls -la '$DEVICE_MIXXX_DIR/bin/mixxx' && echo 'MIXXX binary: OK'"
eval $SSH_CMD "$SSH_TARGET" "ls '$DEVICE_MIXXX_DIR/lib/' | wc -l | xargs echo 'Library count:'"
eval $SSH_CMD "$SSH_TARGET" "ls -la /usr/bin/switch-to-mixxx /usr/bin/switch-to-engine && echo 'Switcher scripts: OK'"
eval $SSH_CMD "$SSH_TARGET" "ls -la '$DEVICE_MIXXX_DIR/settings/skins/vdj-pro' && echo 'VDJ-Pro skin: OK'"
eval $SSH_CMD "$SSH_TARGET" "systemctl status mixxx.service --no-pager -l 2>&1 | head -5"

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
eval $SSH_CMD "$SSH_TARGET" '
CTRL_DIR="/media/az01-internal/mixxx/controllers"
SETTINGS_DIR="/media/az01-internal/mixxx/settings/controllers"
rm -f "$SETTINGS_DIR"/Denon-Prime-Go-scripts.js "$SETTINGS_DIR"/Denon-Prime-Go.midi.xml "$SETTINGS_DIR"/Denon-Prime-Go-jog-wheel-scripts.js "$SETTINGS_DIR"/Denon-Prime-Go-Jog-Wheels.midi.xml "$SETTINGS_DIR"/midi-components-0.0.js
# Fix MIXXX config to point to controllers/ (not settings/controllers/)
sed -i "s|/media/az01-internal/mixxx/settings/controllers/Denon-Prime-Go.midi.xml|/media/az01-internal/mixxx/controllers/Denon-Prime-Go.midi.xml|" /media/az01-internal/mixxx/settings/mixxx.cfg
echo "Stale copies removed, config path fixed."
'
