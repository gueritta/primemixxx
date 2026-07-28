#!/bin/sh
# TKGL module: prepare writable application directories, sync binaries to internal eMMC.

tkgl_mod_install() {
    log "=== mod_install: preparing Mixxx directories ==="
    mkdir -p /data/mixxx/settings /data/tkgl-logs
    [ -c /dev/mali0 ] && chmod 666 /dev/mali0 2>/dev/null

    # Sync lib/ and bin/ to internal eMMC for fast access (50MHz/8-bit bus vs 25MHz/4-bit SD).
    # The launcher prefers internal paths when available — this ensures they are.
    INTERNAL="/media/az01-internal/mixxx"
    BUNDLE="/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/mixxx-bundle"

    if [ ! -f "$INTERNAL/lib/bin/mixxx" ]; then
        log "syncing lib/ and bin/ to internal eMMC (one-time, ~48MB)..."
        mkdir -p "$INTERNAL/lib" "$INTERNAL/bin" "$INTERNAL/qt-plugins"
        # Copy without overwriting Mali symlinks if they already exist
        [ -d "$BUNDLE/lib" ] && cp -a "$BUNDLE/lib/" "$INTERNAL/lib/" 2>/dev/null || true
        [ -d "$BUNDLE/qt-plugins" ] && cp -a "$BUNDLE/qt-plugins/" "$INTERNAL/qt-plugins/" 2>/dev/null || true
        # Recreate bin/mixxx symlink (cp -a follows symlinks, so we recreate it)
        ln -sf ../lib/bin/mixxx "$INTERNAL/bin/mixxx" 2>/dev/null || true
        log "internal eMMC sync complete"
    else
        log "internal lib/bin already present, skipping sync"
    fi

    log "mod_install complete"
}

tkgl_mod_install
