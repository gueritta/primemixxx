#!/bin/sh
# dev-sync-all-back.sh — Pull ALL runtime-modifiable files from device back to local repo.
# Covers: controller mappings, skin files, runtime configs, system files, launcher,
# profiling tools. Run after any on-device editing session before committing.
#
# Usage: DEVICE_IP=10.128.54.244 ./scripts/dev-sync-all-back.sh
#        ./scripts/dev-sync-all-back.sh root@192.168.42.1

set -e

DEV="${1:-root@${DEVICE_IP:-primego.local}}"
BUNDLE="/media/az01-internal/mixxx"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_DEVICE="$REPO_ROOT/scripts/device"
LOCAL_BUNDLE="$REPO_ROOT/mixxx-bundle"
LOCAL_MAPPINGS="$REPO_ROOT/mixxx-bundle/mixxx-mapping"
LOCAL_SKINS="$REPO_ROOT/mixxx-bundle/skins"
LOCAL_SETTINGS="$REPO_ROOT/mixxx-bundle/settings"

scp_cmd() { scp $SSH_OPTS "$@"; }

echo "=== Pulling all runtime files from $DEV ==="
echo ""

# ── 1. Controller mappings (most frequently edited at runtime) ──
echo "--- Controller mappings ---"
for f in \
    Denon-Prime-Go-scripts.js \
    Denon-Prime-Go.midi.xml \
    Denon-Prime-Go-Jog-Wheels.midi.xml \
    Denon-Prime-Go-jog-wheel-scripts.js \
    LateNightMini_toggle_helper.js \
    common-hid-packet-parser.js \
    common-controller-scripts.js \
    midi-components-0.0.js; do
    echo -n "  $f ... "
    scp_cmd "$DEV:$BUNDLE/controllers/$f" "$LOCAL_MAPPINGS/$f" 2>/dev/null && echo "OK" || echo "N/A"
done

# ── 2. Skin files (LateNightMini is canonical) ──
echo "--- Skin: LateNightMini ---"
SKIN_DEV="/tmp/device-LateNightMini-$$"
mkdir -p "$SKIN_DEV"
if scp_cmd -r "$DEV:$BUNDLE/skins/LateNightMini/." "$SKIN_DEV/" 2>/dev/null; then
    # Show what's different without overwriting yet
    changes=$(diff -rq "$LOCAL_SKINS/LateNightMini" "$SKIN_DEV" 2>/dev/null | grep -v "\.bak" || true)
    if [ -n "$changes" ]; then
        echo "  Changed files (diff then apply manually):"
        echo "$changes" | while read -r line; do echo "    $line"; done
        echo "  To apply: cp $SKIN_DEV/\$file $LOCAL_SKINS/LateNightMini/\$file"
    else
        echo "  No changes"
    fi
    rm -rf "$SKIN_DEV"
else
    echo "  LateNightMini not found on device"
fi

# ── 3. Skin QSS (style.qss can be edited on-device) ──
echo "--- Skin QSS ---"
echo -n "  style.qss ... "
scp_cmd "$DEV:$BUNDLE/skins/LateNightMini/style.qss" "$LOCAL_SKINS/LateNightMini/style.qss" 2>/dev/null && echo "OK" || echo "N/A"

# ── 4. Runtime configs (rewritten by MIXXX on every run) ──
echo "--- Runtime configs ---"
for f in mixxx.cfg effects.xml samplers.xml soundconfig.xml; do
    echo -n "  $f ... "
    scp_cmd "$DEV:$BUNDLE/settings/$f" "$LOCAL_SETTINGS/$f" 2>/dev/null && echo "OK" || echo "N/A"
done

# ── 5. Launcher and entry point ──
echo "--- Launcher & entry point ---"
echo -n "  mixxx_launcher.sh ... "
scp_cmd "$DEV:$BUNDLE/mixxx_launcher.sh" "$LOCAL_BUNDLE/mixxx_launcher.sh" 2>/dev/null && echo "OK" || echo "N/A"

echo -n "  /data/mixxx/mixxx (entry point) ... "
scp_cmd "$DEV:/data/mixxx/mixxx" "$LOCAL_BUNDLE/mixxx.entry" 2>/dev/null && echo "OK" || echo "N/A"

# ── 6. System files (service units, udev rules, scripts) ──
echo "--- System files ---"
for pair in \
    "/etc/systemd/system/mixxx.service:mixxx.service" \
    "/usr/sbin/powerbutton-monitor:powerbutton-monitor" \
    "/etc/systemd/system/powerbutton-monitor.service:powerbutton-monitor.service" \
    "/usr/sbin/usb-gadget-eth.sh:usb-gadget-eth.sh" \
    "/etc/systemd/system/usb-gadget-eth.service:usb-gadget-eth.service" \
    "/etc/udev/rules.d/99-wifi-power-save.rules:99-wifi-power-save.rules" \
    "/usr/bin/switch-to-mixxx:switch-to-mixxx" \
    "/usr/bin/switch-to-engine:switch-to-engine" \
    "/usr/bin/fix-mdns.sh:fix-mdns.sh" \
    "/etc/systemd/system/fix-mdns.service:fix-mdns.service"; do
    remote="${pair%%:*}"
    localf="${pair##*:}"
    echo -n "  $localf ... "
    scp_cmd "$DEV:$remote" "$LOCAL_DEVICE/$localf" 2>/dev/null && echo "OK" || echo "N/A"
done

# ── 7. Profiling tools ──
echo "--- Profiling tools ---"
for f in profiler.sh cpu-latency.sh xrun-monitor.sh bench-harness.sh; do
    echo -n "  $f ... "
    scp_cmd "$DEV:/data/$f" "$LOCAL_DEVICE/$f" 2>/dev/null && echo "OK" || echo "N/A"
done

# ── 8. Storage backup (SD card, no USB content) ──
echo ""
echo "=== Creating SD card backup snapshot ==="
BACKUP_DIR="$REPO_ROOT/sdcard-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
# Controllers (flat, mix of symlinks and real files on device)
scp_cmd -r "$DEV:$BUNDLE/controllers" "$BACKUP_DIR/" 2>/dev/null || echo "  controllers: N/A"
# Skins
scp_cmd -r "$DEV:$BUNDLE/skins" "$BACKUP_DIR/" 2>/dev/null || echo "  skins: N/A"
# Settings
scp_cmd -r "$DEV:$BUNDLE/settings" "$BACKUP_DIR/" 2>/dev/null || echo "  settings: N/A"
# Launcher
scp_cmd "$DEV:$BUNDLE/mixxx_launcher.sh" "$BACKUP_DIR/" 2>/dev/null || echo "  launcher: N/A"

echo "  Backup saved to $BACKUP_DIR"
echo ""

# ── Verification ──
echo "=== Post-sync checks ==="
echo ""
echo "# 1. Controller path in mixxx.cfg (must NOT point to settings/controllers/):"
if grep -q "settings/controllers/" "$LOCAL_SETTINGS/mixxx.cfg" 2>/dev/null; then
    echo "   FAIL: mixxx.cfg points to settings/controllers/ — FIX THIS"
else
    echo "   OK: points to controllers/"
fi

echo ""
echo "# 2. Changed files:"
cd "$REPO_ROOT"
git status --short 2>/dev/null || echo "  (not a git repo or no changes)"

echo ""
echo "# 3. Next steps:"
echo "   - Review git diff for each changed file"
echo "   - Run: ./scripts/dev-verify-launcher.sh"
echo "   - Run: ./scripts/dev-check-duplicates.sh"
echo "   - Commit with: git commit -m 'sync: pull runtime changes from device'"
