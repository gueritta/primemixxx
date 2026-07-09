#!/bin/sh
# MIXXX Launcher — deployed on SD card at /media/az01-internal/mixxx/
# Uses device-native Qt5.15.2 from /usr/qt/lib (optimized for this hardware)
# Falls back to bundled libs only when device lacks them.
# EGLFS renders directly to framebuffer with Mali r1p0 GPU driver.

MIXDIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$MIXDIR"

# ── Library path: device-native first, bundled as fallback ──
# /usr/qt/lib:   Denon's optimized Qt5.15.2 (compiled specifically for this SoC)
# /usr/lib:      Mali r1p0 GPU driver, EGL, GLESv2, system libs
# $BUNDLE/lib:   MIXXX-specific libs (qt5keychain, portaudio, etc.)
export LD_LIBRARY_PATH="/usr/qt/lib:/usr/lib:$BUNDLE/lib:$LD_LIBRARY_PATH"

# ── Qt5 environment ──
export QT_PLUGIN_PATH="/usr/qt/plugins"
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_emu
export QT_QPA_EGLFS_KMS_ATOMIC=1
export QT_QPA_EGLFS_ROTATION=90
export QT_QPA_EGLFS_DEBUG=0

# ── GPU: set performance governor (Mali scaling_governor) ──
for g in /sys/class/devfreq/*mali*/governor /sys/class/devfreq/*gpu*/governor; do
    [ -f "$g" ] && echo performance > "$g" 2>/dev/null
done

# ── Ensure USB drives are mounted ──
# Trigger udev to mount any already-plugged USB storage
udevadm trigger --subsystem-match=block --action=add 2>/dev/null || true

# ── Home ──
export HOME=/root
export XDG_RUNTIME_DIR=/tmp

# Stop the native Denon Engine UI if running (releases ALSA & GPU locks)
systemctl stop engine 2>/dev/null || true
sleep 0.5

# ── CPU shielding: pin Mixxx to cores 2-3 with real-time FIFO priority 99 ──
# This protects the <5ms audio buffer from being interrupted by background tasks.
# Cores 0-1 remain free for kernel interrupts and system tasks.
exec taskset -c 2,3 chrt -f 99 "$BUNDLE/bin/mixxx" -platform eglfs \
  --settingsPath "$BUNDLE/settings" \
  --resourcePath "$BUNDLE/bin"
