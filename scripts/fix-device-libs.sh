#!/bin/bash -e
# fix-device-libs.sh — Remove system-critical libs from the deployed MIXXX bundle.
# These MUST come from the device's own /lib, not from Buildroot.
#
# Usage:
#   ./fix-device-libs.sh                       # Run locally (test/preview mode)
#   ./fix-device-libs.sh --remote DEVICE_IP    # Run on device via SSH
#   BUNDLE_LIB=/path/to/lib ./fix-device-libs.sh  # Override bundle path
#
# Examples:
#   BUNDLE_LIB=./mixxx-bundle/lib ./fix-device-libs.sh   # Preview against local bundle
#   ./fix-device-libs.sh --remote 10.109.235.244          # Run on connected device
#   ./fix-device-libs.sh --remote primego.local           # Run on device via mDNS
#
# Local mode (default) operates on the local filesystem — useful for testing
# or previewing which libs would be removed before deploying.
# Remote mode SSHes into the device and runs the removal commands there.

set -euo pipefail

# ── Parse arguments ────────────────────────────────────────────────────────────
REMOTE_HOST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE_HOST="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── System-critical libraries to purge from bundle ─────────────────────────────
SYSTEM_LIBS=(
  "libc.so.6"
  "libm.so.6"
  "libpthread.so.0"
  "libdl.so.2"
  "librt.so.1"
  "libstdc++.so.6"
  "libgcc_s.so.1"
  "ld-linux-armhf.so.3"
  "libatomic.so.1"
  "libresolv.so.2"
  "libnss_dns.so.2"
  "libnss_files.so.2"
  "libutil.so.1"
  "libcrypt.so.1"
  "libnsl.so.1"
  "libanl.so.1"
)

# ── Bundle lib path (overrideable via env) ─────────────────────────────────────
: "${BUNDLE_LIB:=/media/az01-internal/mixxx/lib}"

# ── The core fix logic (shared between local and remote modes) ─────────────────
FIX_COMMANDS='
echo "=== Fixing MIXXX bundle: removing system libs ==="
for lib in '"${SYSTEM_LIBS[*]}"'; do
  if [ -f "$BUNDLE_LIB/$lib" ]; then
    echo "  Removing $lib (must use device system version)"
    rm -f "$BUNDLE_LIB/$lib"
  fi
done

echo ""
echo "=== Remaining libs in bundle ==="
ls -1 "$BUNDLE_LIB/" 2>/dev/null || echo "(none)"
echo ""
echo "=== Checking for libc conflicts ==="
echo "Bundle libc: $(ls "$BUNDLE_LIB/libc"* 2>/dev/null || echo "NONE - good!")"
echo "Bundle ld:   $(ls "$BUNDLE_LIB/ld-"* 2>/dev/null || echo "NONE - good!")"
echo "Bundle libstdc++: $(ls "$BUNDLE_LIB/libstdc"* 2>/dev/null || echo "NONE - good!")"
echo ""
echo "Fix applied. Try running MIXXX now."
'

# ── Execute ────────────────────────────────────────────────────────────────────
if [ -n "$REMOTE_HOST" ]; then
  echo "=== Running lib fix on remote device: $REMOTE_HOST ==="
  echo "Bundle path: $BUNDLE_LIB"
  echo ""
  setsid ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "root@$REMOTE_HOST" \
    "BUNDLE_LIB='$BUNDLE_LIB' bash -e" <<< "$FIX_COMMANDS"
else
  echo "=== Running lib fix locally (test/preview mode) ==="
  echo "Bundle path: $BUNDLE_LIB"
  echo ""
  eval "$FIX_COMMANDS"
fi
