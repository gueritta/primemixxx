#!/bin/bash -e
# collect-mixxx-bundle.sh — Gather MIXXX binary + all dependencies from Buildroot output
# into a self-contained bundle directory ready for deployment to the device's SD card.
#
# Output: ./mixxx-bundle/ containing:
#   bin/mixxx              — MIXXX binary
#   lib/                   — MIXXX-specific shared libraries (Qt5 libs NOT bundled — device provides 5.15.2)
#   mixxx-mapping/         — MIDI controller mapping XML/JS files
#   mixxx_launcher.sh      — wrapper that sets LD_LIBRARY_PATH and launches MIXXX
# Qt5 libs and plugins are NOT bundled — the device provides Qt 5.15.2 at /usr/qt/{lib,plugins}

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
  # Qt5 libraries — device has Qt 5.15.2 at /usr/qt/lib, don't bundle Buildroot's 5.15.8
  # (both are 5.15.x LTS, patch-level ABI compatible)
  case "$name" in
    libQt5*) return 0 ;;
  esac
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
# Device provides Qt plugins at /usr/qt/plugins (5.15.2, Mali-optimized).
# No need to bundle Buildroot's Qt 5.15.8 plugins — use device's instead.
echo "--- Qt plugins: using device /usr/qt/plugins (not bundled) ---"

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

# ── Step 5: Copy MIDI controller mappings ────────────────────────────────────
echo ""
echo "--- Copying MIDI mappings ---"
MAPPINGS_SRC="$REPO_ROOT/buildroot-customizations/board/inmusic/jp11/mixxx-mapping"
if [ -d "$MAPPINGS_SRC" ]; then
  cp -rv "$MAPPINGS_SRC/"* "$BUNDLE_DIR/mixxx-mapping/"
fi

# ── Step 6: Ensure launcher is executable (hand-crafted, not generated) ──────
echo ""
echo "--- Ensuring launcher is executable ---"
chmod +x "$BUNDLE_DIR/mixxx_launcher.sh"

# ── Step 7: Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Bundle collected successfully ==="
echo "Bundle size: $(du -sh "$BUNDLE_DIR" | cut -f1)"
echo "Binary:      $(file "$BUNDLE_DIR/bin/mixxx" | cut -d: -f2-)"
echo "Libraries:   $(ls "$BUNDLE_DIR/lib/" | wc -l) files"
echo ""
echo "Next: run scripts/deploy-to-device.sh to copy to device"
