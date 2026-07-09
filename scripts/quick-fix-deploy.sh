#!/bin/bash -e
# quick-fix-deploy.sh — Redeploy only the changed files to device
# Run after the device reconnects. Assumes SSH_ASKPASS is set up.

DEVICE_IP="${1:-10.109.235.244}"
BUNDLE_DIR="$(cd "$(dirname "$0")/../mixxx-bundle" && pwd)"
TARGET_DIR="/media/az01-internal/mixxx"

echo "=== Quick-fix deploy to $DEVICE_IP ==="
echo "This will:"
echo "  1. Remove old system libs from device bundle"
echo "  2. Deploy updated lib/ + launcher"
echo ""

SSH_CMD="setsid ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no root@$DEVICE_IP"

# Step 1: Remove system libs on device
echo "--- Removing system libs from device bundle ---"
$SSH_CMD '
BUNDLE_LIB="/media/az01-internal/mixxx/lib"
SYSTEM_LIBS="libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 libstdc++.so.6 libgcc_s.so.1 ld-linux-armhf.so.3 libatomic.so.1 libresolv.so.2 libnss_dns.so.2 libnss_files.so.2 libutil.so.1 libcrypt.so.1 libnsl.so.1 libanl.so.1"
for lib in $SYSTEM_LIBS; do
  [ -f "$BUNDLE_LIB/$lib" ] && rm -f "$BUNDLE_LIB/$lib" && echo "  removed $lib"
done
echo "  Done. Remaining: $(ls -1 $BUNDLE_LIB 2>/dev/null | wc -l) libs"
'

# Step 2: Deploy updated lib/ directory (without system libs)
echo "--- Deploying fixed lib/ directory ---"
tar cf - -C "$BUNDLE_DIR/lib" . | $SSH_CMD "cd $TARGET_DIR/lib && tar xf - && echo '  Libs deployed'"

# Step 3: Deploy updated launcher
echo "--- Deploying launcher ---"
cat "$BUNDLE_DIR/mixxx_launcher.sh" | $SSH_CMD "cat > $TARGET_DIR/mixxx_launcher.sh && chmod +x $TARGET_DIR/mixxx_launcher.sh && echo '  Launcher deployed'"

echo ""
echo "=== Fix deployed! ==="
echo "Run on device: cd /media/az01-internal/mixxx && ./mixxx_launcher.sh"
