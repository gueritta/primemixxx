#!/bin/sh
# Confirms only ONE launcher exists that calls ./bin/mixxx
# Confirms TKGL module does NOT contain a launcher copy
# Confirms tkgl_mod_mixxx.sh is under 50 lines (thin caller)
set -e

failures=0

# 1. Only one launcher invokes bin/mixxx (the canonical SD card launcher)
#    The entry point /data/mixxx/mixxx delegates, it doesn't invoke bin/mixxx directly.
#    No other .sh file outside the canonical path should invoke bin/mixxx.
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

# 3. TKGL module is a thin caller (under 50 lines — all config lives in SD launcher)
TKGL_LINES=$(wc -l < tkgl-bootstrap/modules/mod_mixxx/tkgl_mod_mixxx.sh)
if [ "$TKGL_LINES" -gt 50 ]; then
    echo "FAIL: tkgl_mod_mixxx.sh is $TKGL_LINES lines (max 50)"
    failures=$((failures + 1))
else
    echo "OK: tkgl_mod_mixxx.sh is $TKGL_LINES lines (thin caller)"
fi

# 4. No other .sh file outside canonical path invokes bin/mixxx directly
EXTRA=$(grep -rl "exec.*bin/mixxx" --include="*.sh" tkgl-bootstrap/ buildroot-customizations/ 2>/dev/null | grep -v "/data/mixxx/mixxx" | wc -l)
if [ "$EXTRA" -ne 0 ]; then
    echo "FAIL: $EXTRA launcher(s) outside canonical path invoke bin/mixxx directly:"
    grep -rl "exec.*bin/mixxx" --include="*.sh" tkgl-bootstrap/ buildroot-customizations/ 2>/dev/null | grep -v "/data/mixxx/mixxx"
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
