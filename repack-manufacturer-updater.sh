#!/bin/bash
# repack-manufacturer-updater.sh
# =============================================================================
# UNTESTED — documented approach, not yet verified end-to-end.
# =============================================================================
#
# Repackages the original Denon manufacturer's updater (native x86-64 binary)
# with a custom firmware DTB into a self-extracting .run file via makeself.
#
# BACKGROUND — FLASHING METHODS:
#   Two updaters exist for flashing the Denon Prime GO (JP11) / Prime 4 (JC11):
#
#   1. Go reverse-engineered updater (generate-updater-linux.sh):
#      - Decompresses xz-embedded rootfs BEFORE sending via fastboot
#      - Sends raw 500MB rootfs -> "too large for partition" (rootfs = mmcblk0p6, 500MB)
#      - Use only with stripped rootfs <500MB uncompressed
#
#   2. Manufacturer's native updater (this script repackages it):
#      - Extracted from icedream/denon-prime4 release .run file (Makeself 2.7.1)
#      - Sends xz-compressed data directly -> device decompresses on-flash
#      - Stock 500MB rootfs (142MB xz) flashes successfully
#      - 16MB native x86-64 ELF with bundled GTK3 libraries
#      - No sudo needed: udev rule 99-inmusic-fastboot.rules sets 0666 on VID 15e4 PID d00c
#
# FIRMWARE FORMAT:
#   .img.dtb files are FIT (Flattened Image Tree) images, NOT raw DTBs.
#   Inspect with: dumpimage -l firmware.dtb  (from u-boot-tools)
#   Extract with: dumpimage -T flat_dt -p 2 -o rootfs.xz firmware.dtb
#   Image 0: splash (xz), Image 1: recoverysplash (xz), Image 2: rootfs (xz)
#
# DEVICE REFERENCE (Prime GO JP11):
#   Internal eMMC (mmcblk0, 7.3GB):
#     p6: rootfs 500MB (read-only, ext4)
#     p7: /data 6.8GB (rw, overlay for /etc + /var, survives flashes)
#   SD card (mmcblk1):
#     p1: BOOT 7.4GB (vfat, extlinux.conf + kernel + DTB)
#     p2: deb13 7.5GB (ext4, Debian rootfs for dual-boot)
#   SSH: root@<ip> / password: denonprime4 (OpenSSH 9.6)
#   Kernel: 6.1.111-inmusic-2024-09-19-rt41 armv7l
#   Engine: /usr/Engine/Engine (Qt5, renders direct to framebuffer via Mali GPU)
#
# PREREQUISITES:
#   - makeself (https://github.com/megastep/makeself) in PATH
#   - Manufacturer's updater extracted from release .run:
#       ./PRIMEGO-4.3.4-ssh-Update.run --noexec --target extracted_run
#   - A custom firmware .dtb (FIT image with xz-embedded rootfs)
#
# USAGE:
#   ./repack-manufacturer-updater.sh <path-to-custom.dtb> [output-name]
#
#   Example:
#     ./repack-manufacturer-updater.sh ./PRIMEGO-4.3.4-stripped-ssh.dtb
#     # Produces: PRIMEGO-4.3.4-stripped-ssh.run

set -euo pipefail

CUSTOM_DTB="${1:-}"
OUTPUT_NAME="${2:-}"

if [ -z "$CUSTOM_DTB" ]; then
    echo "Usage: $0 <path-to-custom.dtb> [output-name]"
    echo ""
    echo "Repackages the original Denon manufacturer's updater with your firmware."
    echo ""
    echo "Arguments:"
    echo "  custom.dtb     Path to your firmware DTB (FIT image with xz-embedded rootfs)"
    echo "  output-name    Optional base name for the .run file (defaults to DTB basename)"
    exit 1
fi

if [ ! -f "$CUSTOM_DTB" ]; then
    echo "ERROR: Custom DTB not found: $CUSTOM_DTB"
    exit 1
fi

if ! command -v makeself &>/dev/null; then
    echo "ERROR: makeself not found in PATH."
    echo "Install: git clone https://github.com/megastep/makeself.git && ln -s \"\$(pwd)/makeself/makeself.sh\" ~/.local/bin/makeself"
    exit 1
fi

MANUFACTURER_UPDATER_DIR="$(dirname "$(readlink -f "$0")")/extracted_run"

if [ ! -f "$MANUFACTURER_UPDATER_DIR/updater" ]; then
    echo "ERROR: Manufacturer updater not found at $MANUFACTURER_UPDATER_DIR"
    echo "Download from https://github.com/icedream/denon-prime4/releases and extract:"
    echo "  ./PRIMEGO-4.3.4-ssh-Update.run --noexec --target extracted_run"
    exit 1
fi

DTB_BASENAME="$(basename "$CUSTOM_DTB" .dtb)"
OUTPUT_BASENAME="${OUTPUT_NAME:-$DTB_BASENAME}"
DEVICE_NAME="Denon DJ PRIME GO"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "=== Building repackaged updater in $WORKDIR ==="

cp "$MANUFACTURER_UPDATER_DIR"/updater       "$WORKDIR/"
cp "$MANUFACTURER_UPDATER_DIR"/updater.sh    "$WORKDIR/"
cp "$MANUFACTURER_UPDATER_DIR"/*.so*         "$WORKDIR/" 2>/dev/null || true
cp "$CUSTOM_DTB" "$WORKDIR/PRIMEGO-4.3.4-Update.img.dtb"

cat > "$WORKDIR/config.toml" <<EOF
[[devices]]
name = "$DEVICE_NAME"
imagePath = "PRIMEGO-4.3.4-Update.img.dtb"
usbConfig = 1
usbInterface = 0
usbAlternate = 0
usbInputEndpoint = 1
usbOutputEndpoint = 2
usbReadSize = 256
usbReadBufferSize = 0
usbWriteSize = 4096
usbWriteBufferSize = 0
usbOpTimeout = "1m"
EOF

OUTPUT_FILE="${OUTPUT_BASENAME}.run"

echo "=== Creating $OUTPUT_FILE ==="
makeself --zstd --sha256 --nox11 --nowait --follow \
    "$WORKDIR" \
    "$OUTPUT_FILE" \
    "${DEVICE_NAME} Firmware Updater (custom)" \
    ./updater.sh

echo ""
echo "=== Done: $OUTPUT_FILE ==="
echo ""
echo "STATUS: UNTESTED — documented approach, not yet verified end-to-end."
echo ""
echo "To flash:"
echo "  1. Put device in update mode (hold recovery button + tap power)"
echo "  2. Connect USB cable"
echo "  3. Run: ./$OUTPUT_FILE"
echo "  4. The GUI should auto-detect and offer to flash"
echo ""
echo "NOTE: The manufacturer's updater is a GTK3 GUI app. It needs a display."
echo "If running headless, use the Go updater with a firmware DTB whose raw"
echo "rootfs fits the device partition (see generate-updater-linux.sh)."
