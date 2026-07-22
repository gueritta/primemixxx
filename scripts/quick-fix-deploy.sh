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
SCP_CMD="setsid scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -r"

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

# Step 4: Clean stale settings/controllers/ copies and fix config path
# CRITICAL: MIXXX loads controller XML from the path in mixxx.cfg, NOT auto-discovery.
# Having TWO copies (controllers/ + settings/controllers/) causes confusion:
#   - If config points to settings/controllers/ but files are in controllers/ → 0 mappings
#   - If we bloat settings/controllers/ with extra files → MIXXX treats these as its own
# RULE: Controller files go ONLY in controllers/. Config always points there.
#        settings/controllers/ is for MIXXX built-in controller definitions.
#        Our custom Prime Go mapping must NOT be mixed into settings/controllers/.
echo "--- Cleaning stale settings/controllers/ copies and fixing config ---"
$SSH_CMD '
CTRL_DIR="/media/az01-internal/mixxx/controllers"
SETTINGS_DIR="/media/az01-internal/mixxx/settings/controllers"
# Remove any stray Denon Prime Go files from the built-in controller directory
rm -f "$SETTINGS_DIR"/Denon-Prime-Go-scripts.js "$SETTINGS_DIR"/Denon-Prime-Go.midi.xml "$SETTINGS_DIR"/Denon-Prime-Go-jog-wheel-scripts.js "$SETTINGS_DIR"/Denon-Prime-Go-Jog-Wheels.midi.xml "$SETTINGS_DIR"/midi-components-0.0.js
# Fix MIXXX config to point to controllers/ (not settings/controllers/)
sed -i "s|/media/az01-internal/mixxx/settings/controllers/Denon-Prime-Go.midi.xml|/media/az01-internal/mixxx/controllers/Denon-Prime-Go.midi.xml|" /media/az01-internal/mixxx/settings/mixxx.cfg
echo "  Stale copies removed, config fixed"
# Verify no duplication
[ -f "$SETTINGS_DIR/Denon-Prime-Go.midi.xml" ] && echo "  WARNING: still in settings/controllers!" || echo "  Verified: no duplicate in settings/controllers/"
'

echo ""
echo "Run on device: cd /media/az01-internal/mixxx && ./mixxx_launcher.sh"

# Step 5: Deploy profiling/measurement tools
echo ""
echo "--- Deploying profiling tools ---"
DEVICE_SCRIPTS_DIR="$(cd "$(dirname "$0")/device" && pwd)"
for f in profiler.sh cpu-latency.sh xrun-monitor.sh bench-harness.sh; do
    if [ -f "$DEVICE_SCRIPTS_DIR/$f" ]; then
        cat "$DEVICE_SCRIPTS_DIR/$f" | $SSH_CMD "cat > /data/$f && chmod +x /data/$f" && echo "  $f deployed to /data/"
    fi
done
echo "  Done."
