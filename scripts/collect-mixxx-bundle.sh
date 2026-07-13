#!/bin/bash -e
# collect-mixxx-bundle.sh — Gather MIXXX binary + all dependencies from Buildroot output
# into a self-contained bundle directory ready for deployment to the device's SD card.
#
# Output: ./mixxx-bundle/ containing:
#   bin/mixxx              — MIXXX binary
#   lib/                   — MIXXX-specific shared libraries (includes Qt 5.15.8 — CRITICAL for display)
#   mixxx-mapping/         — MIDI controller mapping XML/JS files
#   mixxx_launcher.sh      — wrapper that sets LD_LIBRARY_PATH and launches MIXXX
# Qt 5.15.8 libs and plugins ARE bundled — the device's Qt 5.15.2 + eglfs_emu
# causes a black screen. SD card's bundled Qt 5.15.8 + custom Mali integration
# (eglfs_mali) is required for working display output.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUILDROOT_TARGET="$REPO_ROOT/buildroot/2023.02.11/output/target"
BUNDLE_DIR="$REPO_ROOT/mixxx-bundle"

if [ ! -f "$BUILDROOT_TARGET/usr/bin/mixxx" ]; then
  echo "ERROR: MIXXX binary not found at $BUILDROOT_TARGET/usr/bin/mixxx" >&2
  echo "Make sure Buildroot has been compiled first." >&2
  exit 1
fi

echo "=== Collecting MIXXX deployment bundle ==="
echo "Buildroot target: $BUILDROOT_TARGET"
echo "Bundle output:    $BUNDLE_DIR"

# Clean only what gets regenerated — preserve hand-crafted files
# (mixxx_launcher.sh, mixxx-mapping/, settings/)
rm -rf "$BUNDLE_DIR"/{bin,lib,skins,keyboard,controllers,effects,translations}
mkdir -p "$BUNDLE_DIR"/{bin,lib,mixxx-mapping}

# ── Step 1: Copy MIXXX binary ────────────────────────────────────────────────
echo ""
echo "--- Copying MIXXX binary ---"
cp -v "$BUILDROOT_TARGET/usr/bin/mixxx" "$BUNDLE_DIR/bin/"

# ── Step 2: Discover and copy all needed shared libraries ─────────────────────
echo ""
echo "--- Discovering shared library dependencies ---"

# Use readelf to extract NEEDED entries from an ELF file
get_needed() {
  local elf="$1"
  readelf -d "$elf" 2>/dev/null | grep 'NEEDED' | awk '{print $5}' | tr -d '[]' || true
}

# Resolve a soname to its real path in the Buildroot target
find_lib() {
  local soname="$1"
  # Search standard paths in Buildroot target
  find "$BUILDROOT_TARGET/lib" "$BUILDROOT_TARGET/usr/lib" -name "$soname" -print -quit 2>/dev/null
}

# Libraries that MUST come from the device's system, NOT from Buildroot
# Bundling these causes ABI/kernel incompatibility → segfault
SYSTEM_ONLY_LIBS=(
  "libc.so.6" "libm.so.6" "libpthread.so.0" "libdl.so.2" "librt.so.1"
  "libstdc++.so.6" "libgcc_s.so.1" "ld-linux-armhf.so.3" "libatomic.so.1"
  "libresolv.so.2" "libnss_dns.so.2" "libnss_files.so.2" "libutil.so.1"
  "libcrypt.so.1" "libnsl.so.1" "libanl.so.1"
)

is_system_lib() {
  local name="$1"
  for syslib in "${SYSTEM_ONLY_LIBS[@]}"; do
    [ "$name" = "$syslib" ] && return 0
  done
  return 1
}

# Recursively collect all dependencies
declare -A SEEN_LIBS

collect_deps() {
  local elf="$1"
  local needed
  needed=$(get_needed "$elf")

  for soname in $needed; do
    if [ -n "${SEEN_LIBS[$soname]:-}" ]; then
      continue  # already processed
    fi
    SEEN_LIBS[$soname]=1

    # Skip system-critical libs — they MUST come from the device
    if is_system_lib "$soname"; then
      echo "  SKIP: $soname (system lib, will use device version)"
      continue
    fi

    local libpath
    libpath=$(find_lib "$soname")
    if [ -z "$libpath" ]; then
      echo "  SKIP: $soname (not found in Buildroot target, expected on device)"
      continue
    fi

    # Copy the actual file (resolving symlinks)
    local realpath
    realpath=$(readlink -f "$libpath" 2>/dev/null || echo "$libpath")
    local libname
    libname=$(basename "$libpath")
    if [ ! -f "$BUNDLE_DIR/lib/$libname" ]; then
      cp -v "$realpath" "$BUNDLE_DIR/lib/$libname"
    fi

    # Recurse into this library's dependencies
    collect_deps "$libpath"
  done
}

echo "Scanning MIXXX binary..."
collect_deps "$BUNDLE_DIR/bin/mixxx"

# Symlink resources from bin/ so MIXXX finds them (MIXXX resolves resources relative to binary)
for res in skins keyboard controllers effects translations; do
  ln -sf "../$res" "$BUNDLE_DIR/bin/$res"
done

# ── Step 3: Fix Mali GPU driver (replace Buildroot r0p0 with symlink to device r1p0) ──
echo ""
echo "--- Fixing Mali GPU driver (r0p0 → r1p0 symlink) ---"
for malilib in libEGL.so libGLESv2.so; do
  if [ -f "$BUNDLE_DIR/lib/$malilib" ]; then
    rm -f "$BUNDLE_DIR/lib/$malilib"
    ln -sf /usr/lib/libmali.so.14.0 "$BUNDLE_DIR/lib/$malilib"
    echo "  $malilib → /usr/lib/libmali.so.14.0 (device r1p0)"
  fi
done

# ── Step 4: Qt plugins ──────────────────────────────────────────────────────
# Bundle Qt 5.15.8 plugins from Buildroot output — CRITICAL for display.
# The Mali integration plugin (libqeglfs-mali-integration.so) is REQUIRED
# for working display output with eglfs_mali. Device's Qt 5.15.2 plugins
# use eglfs_emu which causes a black screen.
echo "--- Bundling Qt 5.15.8 plugins from Buildroot ---"
mkdir -p "$BUNDLE_DIR/qt-plugins"
if [ -d "$BUILDROOT_TARGET/usr/lib/qt/plugins" ]; then
  # Copy ALL Qt plugins from Buildroot
  cp -rv "$BUILDROOT_TARGET/usr/lib/qt/plugins/"* "$BUNDLE_DIR/qt-plugins/"
  echo "Qt plugins bundled from Buildroot"
elif [ -d "$BUILDROOT_TARGET/usr/qt/plugins" ]; then
  cp -rv "$BUILDROOT_TARGET/usr/qt/plugins/"* "$BUNDLE_DIR/qt-plugins/"
  echo "Qt plugins bundled from Buildroot"
else
  echo "WARNING: No Qt plugins found in Buildroot target. Searching..."
  QT_PLUGIN_DIRS=$(find "$BUILDROOT_TARGET" -type d -name plugins -path "*/qt/*" 2>/dev/null)
  if [ -n "$QT_PLUGIN_DIRS" ]; then
    for dir in $QT_PLUGIN_DIRS; do
      cp -rv "$dir/"* "$BUNDLE_DIR/qt-plugins/"
    done
    echo "Qt plugins bundled from: $QT_PLUGIN_DIRS"
  else
    echo "ERROR: Could not find Qt plugins in Buildroot output!" >&2
    echo "The bundle will NOT work without Qt 5.15.8 plugins." >&2
    exit 1
  fi
fi

# ── Step 4b: Copy MIXXX resources (skins, keyboard, controllers, etc.) ──────
echo ""
echo "--- Copying MIXXX resources ---"
MIX_RESOURCES_SRC="$BUILDROOT_TARGET/usr/share/mixxx"
if [ -d "$MIX_RESOURCES_SRC" ]; then
  for dir in skins keyboard controllers effects translations; do
    if [ -d "$MIX_RESOURCES_SRC/$dir" ]; then
      cp -rv "$MIX_RESOURCES_SRC/$dir" "$BUNDLE_DIR/"
    fi
  done
fi

# ── Step 5: Copy Denon MIDI controller mappings into controllers/ ────────────
# Mixxx discovers mappings from <resourcePath>/controllers/. The Denon custom
# mappings must live alongside the default bundled mappings (copied in Step 4b).
# The .midi.xml files reference lodash.mixxx.js and midi-components-0.0.js
# which are already in controllers/ from Buildroot's MIXXX resources.
#
# IMPORTANT: .midi.xml and .js files must be FLAT in controllers/, NOT in a
# subfolder. Mixxx resolves mapping file names (e.g. "Denon-Prime-Go.midi.xml")
# by scanning controllers/ directly — subfolders are not searched recursively.
echo ""
echo "--- Copying Denon MIDI mappings into controllers/ ---"
MAPPINGS_SRC="$REPO_ROOT/buildroot-customizations/board/inmusic/jp11/mixxx-mapping"
if [ -d "$MAPPINGS_SRC" ]; then
  # Ensure controllers/ exists (should have been created in Step 4b)
  mkdir -p "$BUNDLE_DIR/controllers"
  # Copy Denon mappings flat into controllers/ (no subfolders — Mixxx requires flat layout)
  for item in "$MAPPINGS_SRC/"*.midi.xml "$MAPPINGS_SRC/"*-scripts.js "$MAPPINGS_SRC/"*.hid.xml; do
    [ -f "$item" ] && cp -v "$item" "$BUNDLE_DIR/controllers/"
  done
  # Copy any Prime Go mapping files from the prime-go/ subfolder into controllers/ flat
  for item in "$MAPPINGS_SRC"/prime-go/*.midi.xml "$MAPPINGS_SRC"/prime-go/*-scripts.js; do
    [ -f "$item" ] && cp -v "$item" "$BUNDLE_DIR/controllers/"
  done
  # Also keep a source copy in mixxx-mapping/ for repo reference
  mkdir -p "$BUNDLE_DIR/mixxx-mapping"
  cp -rv "$MAPPINGS_SRC/"* "$BUNDLE_DIR/mixxx-mapping/"
fi

# ── Step 6: Copy LD_PRELOAD workaround library ────────────────────────────────
# Kernel 5.10.109-inmusic-rt64 never sends NLMSG_DONE for hidraw netlink dumps.
# This .so skips hidraw udev scans and caps infinite poll() timeouts.
echo ""
echo "--- Copying no_hid_poll.so workaround ---"
if [ -f "$REPO_ROOT/mixxx-bundle/helpers/no_hid_poll.so" ]; then
  mkdir -p "$BUNDLE_DIR/lib"
  cp -v "$REPO_ROOT/mixxx-bundle/helpers/no_hid_poll.so" "$BUNDLE_DIR/lib/no_hid_poll.so"
else
  echo "WARNING: no_hid_poll.so not found — compile it first with:"
  echo "  CC=\$BUILDROOT/output/host/bin/arm-buildroot-linux-gnueabihf-gcc"
  echo "  \$CC -shared -fPIC -o helpers/no_hid_poll.so helpers/no_hid_poll.c -ldl"
fi

# ── Step 7: Ensure launcher is executable (hand-crafted, not generated) ──────
echo ""
echo "--- Ensuring launcher is executable ---"
chmod +x "$BUNDLE_DIR/mixxx_launcher.sh"

# ── Step 8: Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Bundle collected successfully ==="
echo "Bundle size: $(du -sh "$BUNDLE_DIR" | cut -f1)"
echo "Binary:      $(file "$BUNDLE_DIR/bin/mixxx" | cut -d: -f2-)"
echo "Libraries:   $(ls "$BUNDLE_DIR/lib/" | wc -l) files"
echo ""
echo "Next: run scripts/deploy-to-device.sh to copy to device"
