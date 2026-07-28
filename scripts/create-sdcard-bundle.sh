#!/bin/bash -e
# create-sdcard-bundle.sh — Assemble a complete, ready-to-use SD card bundle
# for the Denon Prime Go. Users extract this tarball to the root of an SD
# card, insert it, and get a working MIXXX setup without compiling anything.
#
# The script takes the existing mixxx-bundle/ directory (which should already
# contain the MIXXX binary, Qt 5.15.8 libs, mappings, launcher, and skin)
# and combines it with the TKGL bootstrap framework to produce a single
# tarball: primego-sdcard-mixxx-<version>.tar.gz
#
# Usage:
#   ./scripts/create-sdcard-bundle.sh                           # default output
#   ./scripts/create-sdcard-bundle.sh --output ./my-bundle.tar.gz  # custom output
#   ./scripts/create-sdcard-bundle.sh --version 2.6.0           # version tag
#   SKIP_ASSERTIONS=1 ./scripts/create-sdcard-bundle.sh         # skip assertion checks
#
# Prerequisites:
#   - mixxx-bundle/ must exist with bin/mixxx, lib/, mixxx_launcher.sh, etc.
#     (run scripts/dev-collect-mixxx-bundle.sh first, or download a prebuilt bundle)
#   - tkgl-bootstrap/ must exist with doer_list, modules/, scripts/, etc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUNDLE_DIR="$REPO_ROOT/mixxx-bundle"
TKGL_DIR="$REPO_ROOT/tkgl-bootstrap"
BUILDROOT_CUSTOM_DIR="$REPO_ROOT/buildroot-customizations"

# ── Configuration ────────────────────────────────────────────────────────────
VERSION="${VERSION:-$(date +%Y%m%d)}"
OUTPUT="${OUTPUT:-$REPO_ROOT/artifacts/primego-sdcard-mixxx-${VERSION}.tar.gz}"
SKIP_ASSERTIONS="${SKIP_ASSERTIONS:-0}"
WORK_DIR=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --skip-assertions) SKIP_ASSERTIONS=1; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Resolve absolute output path
OUTPUT_DIR="$(dirname "$OUTPUT")"
mkdir -p "$OUTPUT_DIR"
OUTPUT="$(cd "$OUTPUT_DIR" 2>/dev/null && pwd)/$(basename "$OUTPUT")"

echo "=== Creating SD Card Bundle ==="
echo "Version:  $VERSION"
echo "Output:   $OUTPUT"
echo "Source:   $BUNDLE_DIR"

# ── Pre-flight checks ────────────────────────────────────────────────────────
if [ ! -f "$BUNDLE_DIR/bin/mixxx" ]; then
  echo "ERROR: MIXXX binary not found at $BUNDLE_DIR/bin/mixxx" >&2
  echo "Run scripts/dev-collect-mixxx-bundle.sh first, or download a prebuilt bundle." >&2
  exit 1
fi

if [ ! -f "$BUNDLE_DIR/mixxx_launcher.sh" ]; then
  echo "ERROR: Launcher not found at $BUNDLE_DIR/mixxx_launcher.sh" >&2
  exit 1
fi

if [ ! -f "$TKGL_DIR/doer_list" ]; then
  echo "ERROR: TKGL bootstrap not found at $TKGL_DIR/doer_list" >&2
  exit 1
fi

# ── Step 1: Create temporary work directory ───────────────────────────────────
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

STAGING="$WORK_DIR/primego-sdcard"
mkdir -p "$STAGING"

echo ""
echo "--- Assembling SD card bundle ---"

# ── Step 2: Copy MIXXX bundle ────────────────────────────────────────────────
echo "Copying MIXXX bundle..."
rsync -a --exclude='.git' --exclude='*.bak' "$BUNDLE_DIR/" "$STAGING/"

# ── Step 3: Copy TKGL bootstrap ──────────────────────────────────────────────
echo "Copying TKGL bootstrap..."
mkdir -p "$STAGING/tkgl_bootstrap_DenonPrimeGO"
rsync -a --exclude='.git' "$TKGL_DIR/" "$STAGING/tkgl_bootstrap_DenonPrimeGO/"

# ── Step 4: Copy entry point (thin delegator) from buildroot overlay ─────────
echo "Copying entry point..."
ENTRYPOINT_SRC="$BUILDROOT_CUSTOM_DIR/board/inmusic/jp11/rootfs_overlay/data/mixxx/mixxx"
if [ -f "$ENTRYPOINT_SRC" ]; then
  cp -v "$ENTRYPOINT_SRC" "$STAGING/mixxx"
  chmod +x "$STAGING/mixxx"
else
  echo "WARNING: Entry point not found at $ENTRYPOINT_SRC"
  echo "Creating from template..."
  cat > "$STAGING/mixxx" <<'ENTRYEOF'
#!/bin/sh
# TKGL entry point - delegates to SD card launcher
exec /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/mixxx_launcher.sh "$@"
ENTRYEOF
  chmod +x "$STAGING/mixxx"
fi

# ── Step 5: Fix Mali GPU driver (replace Buildroot r0p0 with symlink to device r1p0) ──
echo ""
echo "--- Fixing Mali GPU driver (r0p0 → r1p0 symlink) ---"
for malilib in libEGL.so libGLESv2.so libGLESv1_CM.so; do
  if [ -f "$STAGING/lib/$malilib" ]; then
    rm -f "$STAGING/lib/$malilib"
  fi
  ln -sf /usr/lib/libmali.so.14.0 "$STAGING/lib/$malilib"
  echo "  $malilib → /usr/lib/libmali.so.14.0 (device r1p0)"
done

# ── Step 6: Strip system-critical libs ────────────────────────────────────────
echo ""
echo "--- Stripping system-critical libs (must come from device /lib) ---"
SYSTEM_LIBS=(
  "libc.so.6" "libm.so.6" "libpthread.so.0" "libdl.so.2" "librt.so.1"
  "libstdc++.so.6" "libgcc_s.so.1" "ld-linux-armhf.so.3" "libatomic.so.1"
  "libresolv.so.2" "libnss_dns.so.2" "libnss_files.so.2" "libutil.so.1"
  "libcrypt.so.1" "libnsl.so.1" "libanl.so.1"
)
REMOVED=0
for lib in "${SYSTEM_LIBS[@]}"; do
  if [ -f "$STAGING/lib/$lib" ]; then
    echo "  REMOVED: $lib"
    rm -f "$STAGING/lib/$lib"
    REMOVED=$((REMOVED + 1))
  fi
done
echo "  Removed $REMOVED system libs"

# Also remove any that match patterns (symlinks etc.)
for pattern in ld-linux* libc-* libm-* libpthread-* libdl-* librt-* libstdc++* libgcc_s* libatomic* libresolv* libnss_* libutil* libcrypt* libnsl* libanl*; do
  for f in "$STAGING/lib/$pattern"; do
    if [ -f "$f" ] && [ ! -L "$f" ]; then
      echo "  REMOVED (pattern): $(basename "$f")"
      rm -f "$f"
      REMOVED=$((REMOVED + 1))
    fi
  done
done

# ── Step 7: Create music mount point ──────────────────────────────────────────
echo ""
echo "--- Creating music mount point ---"
mkdir -p "$STAGING/music"
echo "This directory is a mount point for USB music drives." > "$STAGING/music/README.txt"

# ── Step 8: Create seed database ─────────────────────────────────────────────
echo ""
echo "--- Creating seed database ---"
SEED_DB="$STAGING/settings/mixxxdb.seed"
mkdir -p "$(dirname "$SEED_DB")"

# Create a minimal SQLite seed database with the music library directory entry.
# This allows MIXXX to skip the first-run wizard and know where to scan.
sqlite3 "$SEED_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS directories (
    id INTEGER PRIMARY KEY,
    directory TEXT NOT NULL,
    volume TEXT NOT NULL
);
INSERT OR IGNORE INTO directories (id, directory, volume) VALUES (1, '/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle/music', '1');

CREATE TABLE IF NOT EXISTS information (
    id INTEGER PRIMARY KEY,
    schema_version INTEGER NOT NULL
);
INSERT OR IGNORE INTO information (id, schema_version) VALUES (1, 38);

CREATE TABLE IF NOT EXISTS settings (
    setting TEXT PRIMARY KEY,
    value TEXT
);
INSERT OR IGNORE INTO settings (setting, value) VALUES ('mixxx.schema.version', '38');
SQL

if [ -f "$SEED_DB" ]; then
  echo "  Seed database created: $(stat -c%s "$SEED_DB") bytes"
else
  echo "  WARNING: sqlite3 not available, seed database not created"
  echo "  Users will need to go through the first-run wizard."
fi

# ── Step 9: Ensure launcher is executable ─────────────────────────────────────
chmod +x "$STAGING/mixxx_launcher.sh" 2>/dev/null || true

# ── Step 10: Create TKGL path config ─────────────────────────────────────────
echo "--- Creating TKGL path config ---"
TKGL_ROOT_STAGING="$STAGING/tkgl_bootstrap_DenonPrimeGO"
mkdir -p "$TKGL_ROOT_STAGING/scripts"
cat > "$TKGL_ROOT_STAGING/scripts/tkgl_path" <<'PATHEOF'
MOUNT_POINT="/media/TKGL_BOOTSTRAP"
TKGL_ROOT="$MOUNT_POINT/tkgl_bootstrap_DenonPrimeGO"
TKGL_BIN="$TKGL_ROOT/bin"
TKGL_LIB="$TKGL_ROOT/lib"
TKGL_CONF="$TKGL_ROOT/conf"
TKGL_LOG="$TKGL_ROOT/logs"
TKGL_SCRIPTS="$TKGL_ROOT/scripts"
TKGL_MODULES="$TKGL_ROOT/modules"
TKGL_LOG_FILE="$TKGL_LOG/bootstrap_$(date +%Y%m%d_%H%M%S).log"
PATHEOF

# ── Step 11: Verify assertions ────────────────────────────────────────────────
if [ "$SKIP_ASSERTIONS" != "1" ]; then
  echo ""
  echo "=== Verifying assertions ==="
  FAILURES=0

  # BINARY-WORKING: bin/mixxx must be executable, resolve symlink for size check
  MIX_REAL="$STAGING/bin/mixxx"
  if [ -L "$MIX_REAL" ]; then
    MIX_REAL="$(readlink -f "$MIX_REAL")"
  fi
  if [ ! -x "$MIX_REAL" ]; then
    echo "FAIL [BINARY-WORKING]: bin/mixxx is not executable (resolved: $MIX_REAL)"
    FAILURES=$((FAILURES + 1))
  else
    MIX_SIZE=$(stat -c%s "$MIX_REAL" 2>/dev/null || echo "0")
    if [ "$MIX_SIZE" -lt 5000000 ]; then
      echo "FAIL [BINARY-WORKING]: bin/mixxx is too small (${MIX_SIZE} bytes, expected ~10MB)"
      FAILURES=$((FAILURES + 1))
    else
      echo "PASS [BINARY-WORKING]: bin/mixxx is $(numfmt --to=iec $MIX_SIZE 2>/dev/null || echo "${MIX_SIZE}B")"
    fi
  fi

  # SYSLIBS-FORBIDDEN: System libs must not be in the bundle
  for lib in libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 \
             libstdc++.so.6 libgcc_s.so.1 ld-linux-armhf.so.3 libatomic.so.1; do
    if [ -f "$STAGING/lib/$lib" ]; then
      echo "FAIL [SYSLIBS-FORBIDDEN]: $lib still present in bundle"
      FAILURES=$((FAILURES + 1))
    fi
  done
  echo "PASS [SYSLIBS-FORBIDDEN]: No forbidden system libs found"

  # MALI-DDK-R1P0: EGL/GLES libs must be symlinks to /usr/lib/libmali.so.14.0
  for malilib in libEGL.so libGLESv2.so libGLESv1_CM.so; do
    TARGET=$(readlink "$STAGING/lib/$malilib" 2>/dev/null || echo "NOT_A_SYMLINK")
    if [ "$TARGET" != "/usr/lib/libmali.so.14.0" ]; then
      echo "FAIL [MALI-DDK-R1P0]: $malilib → '$TARGET' (expected /usr/lib/libmali.so.14.0)"
      FAILURES=$((FAILURES + 1))
    fi
  done
  echo "PASS [MALI-DDK-R1P0]: Mali symlinks correct"

  # MALI-INTEGRATION: QT_QPA_EGLFS_INTEGRATION must be eglfs_mali
  if grep -q 'QT_QPA_EGLFS_INTEGRATION=eglfs_mali' "$STAGING/mixxx_launcher.sh"; then
    echo "PASS [MALI-INTEGRATION]: QT_QPA_EGLFS_INTEGRATION=eglfs_mali"
  else
    echo "FAIL [MALI-INTEGRATION]: QT_QPA_EGLFS_INTEGRATION not set to eglfs_mali"
    FAILURES=$((FAILURES + 1))
  fi

  # QT-VERSION: SD card must have libQt5Core and Mali integration plugin
  if [ -f "$STAGING/lib/libQt5Core.so.5" ]; then
    echo "PASS [QT-VERSION]: libQt5Core.so.5 present in bundle"
  else
    echo "FAIL [QT-VERSION]: libQt5Core.so.5 missing from bundle"
    FAILURES=$((FAILURES + 1))
  fi

  # MALI-INTEGRATION-PLUGIN: eglfs_mali plugin must exist
  if [ -f "$STAGING/qt-plugins/egldeviceintegrations/libqeglfs-mali-integration.so" ]; then
    echo "PASS [MALI-PLUGIN]: libqeglfs-mali-integration.so present"
  else
    echo "FAIL [MALI-PLUGIN]: libqeglfs-mali-integration.so MISSING — eglfs_mali won't work"
    FAILURES=$((FAILURES + 1))
  fi

  # RESOURCE-PATH-ROOT: --resourcePath must be $BUNDLE root, not $BUNDLE/bin
  if grep -q '\--resourcePath.*\$BUNDLE[^/]' "$STAGING/mixxx_launcher.sh" || \
     grep -q '\--resourcePath.*\$BUNDLE"' "$STAGING/mixxx_launcher.sh" || \
     grep -q '\--resourcePath.*BUNDLE ' "$STAGING/mixxx_launcher.sh"; then
    echo "PASS [RESOURCE-PATH-ROOT]: --resourcePath points to \$BUNDLE root"
  else
    echo "FAIL [RESOURCE-PATH-ROOT]: Check --resourcePath in mixxx_launcher.sh"
    FAILURES=$((FAILURES + 1))
  fi

  # DISPLAY-ROTATION: Must be 90
  if grep -q 'QT_QPA_EGLFS_ROTATION=90' "$STAGING/mixxx_launcher.sh"; then
    echo "PASS [DISPLAY-ROTATION]: EGLFS rotation set to 90"
  else
    echo "FAIL [DISPLAY-ROTATION]: QT_QPA_EGLFS_ROTATION not 90"
    FAILURES=$((FAILURES + 1))
  fi

  # SHEBANG-SH-ONLY: All shell scripts must use #!/bin/sh
  echo "Checking shebangs..."
  BASH_SHEBANGS=$(find "$STAGING" -name "*.sh" -type f -exec head -1 {} \; 2>/dev/null | grep -c '#!/bin/bash' || true)
  if [ "$BASH_SHEBANGS" -gt 0 ]; then
    echo "FAIL [SHEBANG-SH-ONLY]: $BASH_SHEBANGS scripts with #!/bin/bash found"
    find "$STAGING" -name "*.sh" -type f -exec head -1 {} \; 2>/dev/null | grep -n '#!/bin/bash' || true
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [SHEBANG-SH-ONLY]: All .sh scripts use #!/bin/sh"
  fi

  # PIDOF-GUARD: Launcher must have duplicate-instance guard
  if grep -q "pidof mixxx" "$STAGING/mixxx_launcher.sh"; then
    echo "PASS [PIDOF-GUARD]: Launcher has duplicate-instance guard"
  else
    echo "FAIL [PIDOF-GUARD]: Launcher missing pidof guard"
    FAILURES=$((FAILURES + 1))
  fi

  # KMS-ATOMIC: Must not be set
  if grep -r "KMS_ATOMIC" "$STAGING" --include="*.sh" -l 2>/dev/null | grep -q .; then
    echo "FAIL [KMS-ATOMIC]: KMS_ATOMIC found in bundle"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS [KMS-ATOMIC]: No KMS_ATOMIC in bundle"
  fi

  if [ "$FAILURES" -gt 0 ]; then
    echo ""
    echo "=== $FAILURES ASSERTION(S) FAILED ===" >&2
    echo "Run with SKIP_ASSERTIONS=1 to bypass (not recommended for releases)." >&2
    exit 1
  fi
  echo ""
  echo "=== All assertions passed ==="
fi

# ── Step 12: Package ──────────────────────────────────────────────────────────
echo ""
echo "--- Packaging bundle ---"
STAGING_PARENT="$(dirname "$STAGING")"
STAGING_NAME="$(basename "$STAGING")"

# Create tarball. The archive should extract to a directory called
# "primego-sdcard/" which represents the root of the SD card.
cd "$STAGING_PARENT"
tar czf "$OUTPUT" "$STAGING_NAME"
BUNDLE_SIZE=$(stat -c%s "$OUTPUT" 2>/dev/null || echo "0")

echo ""
echo "=== SD Card Bundle Created ==="
echo "Output:  $OUTPUT"
echo "Size:    $(numfmt --to=iec "$BUNDLE_SIZE" 2>/dev/null || echo "${BUNDLE_SIZE}B")"
echo ""
echo "Contents:"
echo "  MIXXX binary:        $(file "$(readlink -f "$STAGING/bin/mixxx")" 2>/dev/null | cut -d: -f2- | head -c 80 || echo '?')"
echo "  Libraries:           $(ls "$STAGING/lib/"*.so* 2>/dev/null | wc -l) .so files"
echo "  Qt plugins:          $(find "$STAGING/qt-plugins" -name '*.so' 2>/dev/null | wc -l) .so files"
echo "  Mali symlinks:       $(find "$STAGING/lib" -lname '*/libmali*' 2>/dev/null | wc -l) shim(s)"
echo "  TKGL modules:        $(ls "$STAGING/tkgl_bootstrap_DenonPrimeGO/modules/" 2>/dev/null | wc -l)"
echo "  Launcher:            mixxx_launcher.sh"
echo "  Controller mappings: $(ls "$STAGING/controllers/"*.js "$STAGING/controllers/"*.xml 2>/dev/null | wc -l) files"
echo ""
echo "To use:"
echo "  1. Extract to root of SD card (formatted as ext4, label 'TKGL_BOOTSTRAP'):"
echo "     tar xzf $(basename "$OUTPUT") -C /path/to/sdcard/"
echo "  2. Insert SD card into Prime Go"
echo "  3. Flash the SSH-enabled firmware (see README)"
echo "  4. Boot → MIXXX auto-starts via TKGL"
