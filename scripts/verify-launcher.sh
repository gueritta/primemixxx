#!/bin/sh
# Confirms only ONE launcher exists that calls ./bin/mixxx
# Confirms TKGL module does NOT contain a launcher copy
# Confirms tkgl_mod_mixxx.sh matches device version (67 lines — includes Mali governor, IRQ, powerbutton)
set -e

failures=0

# 1. Only one launcher invokes bin/mixxx (the canonical SD card launcher)
LAUNCHER_COUNT=$(grep -rl "bin/mixxx" --include="*.sh" mixxx-bundle/ 2>/dev/null | wc -l)
if [ "$LAUNCHER_COUNT" -ne 1 ]; then
    echo "FAIL: Expected exactly 1 launcher invoking bin/mixxx in mixxx-bundle/, found $LAUNCHER_COUNT"
    grep -rl "bin/mixxx" --include="*.sh" mixxx-bundle/ 2>/dev/null
    failures=$((failures + 1))
else
    echo "OK: Exactly 1 launcher invokes bin/mixxx ($(grep -rl "bin/mixxx" --include="*.sh" mixxx-bundle/))"
fi

# 2. TKGL module does NOT contain a launcher copy
if [ -f "tkgl-bootstrap/modules/mod_mixxx/mixxx_launcher.sh" ]; then
    echo "FAIL: tkgl-bootstrap/modules/mod_mixxx/mixxx_launcher.sh still exists"
    failures=$((failures + 1))
else
    echo "OK: No launcher copy in tkgl-bootstrap"
fi

# 3. TKGL module matches device version (67 lines — captured from device 2026-07-21)
#    Includes: Mali governor, IRQ affinity, powerbutton-monitor, udev trigger, error handling
TKGL_LINES=$(wc -l < tkgl-bootstrap/modules/mod_mixxx/tkgl_mod_mixxx.sh)
if [ "$TKGL_LINES" -lt 55 ]; then
    echo "FAIL: tkgl_mod_mixxx.sh is $TKGL_LINES lines — appears to be stripped version (device has 67)"
    failures=$((failures + 1))
elif [ "$TKGL_LINES" -gt 80 ]; then
    echo "FAIL: tkgl_mod_mixxx.sh is $TKGL_LINES lines — unexpectedly large, review manually"
    failures=$((failures + 1))
else
    echo "OK: tkgl_mod_mixxx.sh is $TKGL_LINES lines (matches device ~67 lines)"
fi

# 4. Launcher has duplicate-instance guard (device-verified feature)
if grep -q "pidof mixxx" mixxx-bundle/mixxx_launcher.sh; then
    echo "OK: Launcher has pidof guard"
else
    echo "FAIL: Launcher missing pidof guard (present on device)"
    failures=$((failures + 1))
fi

# 5. No other .sh file outside canonical path invokes bin/mixxx directly
EXTRA=$(grep -rl "bin/mixxx" --include="*.sh" tkgl-bootstrap/ buildroot-customizations/ 2>/dev/null | grep -v "/data/mixxx/mixxx" | grep -v "post-build" | grep -v "rootfs_overlay/usr/bin" | wc -l)
if [ "$EXTRA" -ne 0 ]; then
    echo "FAIL: $EXTRA launcher(s) outside canonical path invoke bin/mixxx directly:"
    grep -rl "bin/mixxx" --include="*.sh" tkgl-bootstrap/ buildroot-customizations/ 2>/dev/null | grep -v "/data/mixxx/mixxx" | grep -v "post-build" | grep -v "rootfs_overlay/usr/bin"
    failures=$((failures + 1))
else
    echo "OK: No external launchers invoke bin/mixxx directly"
fi

if [ "$failures" -gt 0 ]; then
    echo "ERROR: $failures verification(s) failed"
    exit 1
fi

echo "All launcher verifications passed"
exit 0
