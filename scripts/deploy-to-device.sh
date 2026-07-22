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

# ── Step 4: Install device services (systemd, udev, switchers, etc.) ────────
echo ""
echo "--- Installing device services ---"
bash "$SCRIPT_DIR/install-device-services.sh" || {
  echo "ERROR: Device service installation failed." >&2
  exit 1
}
echo "Device services installed successfully."

# ── Step 5: Verify deployment ────────────────────────────────────────────────
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
'
