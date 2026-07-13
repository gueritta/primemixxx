#!/bin/sh
# MIXXX Launcher — Denon Prime Go (SD card)
# Minimal launcher: sets env for SD card's bundled Qt 5.15.8 + eglfs_mali.
# No USB mount, seed DB, GPU governor, or dialog suppression — those are
# handled by the TKGL bootstrap framework that calls this script.
BUNDLE=/media/az01-internal/mixxx
export QT_PLUGIN_PATH="$BUNDLE/qt-plugins"
export LD_LIBRARY_PATH="$BUNDLE/lib:/usr/qt/lib:/usr/lib"
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_mali
export QT_QPA_EGLFS_ROTATION=90
export QT_QPA_FONTDIR=/usr/share/fonts
export QT_QPA_GENERIC_PLUGINS=evdevtouch:/dev/input/event0,evdevkeyboard:/dev/input/event1
export QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=/dev/input/event0:rotate=0
export HOME=/tmp
export XDG_RUNTIME_DIR=/tmp
exec taskset -c 2,3 chrt -f 99 $BUNDLE/bin/mixxx -platform eglfs --settingsPath $BUNDLE/settings --resourcePath $BUNDLE "$@"
