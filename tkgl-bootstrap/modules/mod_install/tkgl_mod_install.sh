#!/bin/sh
# TKGL module: prepare writable application directories only.

tkgl_mod_install() {
    log "=== mod_install: preparing Mixxx directories ==="
    mkdir -p /data/mixxx/settings /data/tkgl-logs
    [ -c /dev/mali0 ] && chmod 666 /dev/mali0 2>/dev/null
    log "mod_install complete"
}

tkgl_mod_install
