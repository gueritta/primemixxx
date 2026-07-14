#!/bin/sh
# MIXXX Launcher — Denon Prime Go (SD card)
# Minimal launcher: sets env for SD card's bundled Qt 5.15.8 + eglfs_mali.
# No USB mount, seed DB, GPU governor, or dialog suppression — those are
# handled by the TKGL bootstrap framework that calls this script.
BUNDLE=/media/az01-internal/mixxx
# Workaround: kernel 5.10.109-inmusic-rt64 never sends NLMSG_DONE for the
# hidraw netlink dump, so udev's hid_enumerate() hangs forever. The LD_PRELOAD
# library skips the hidraw udev scan and caps infinite poll() timeouts.
export LD_PRELOAD=$BUNDLE/lib/no_hid_poll.so
export QT_PLUGIN_PATH="$BUNDLE/qt-plugins"
export LD_LIBRARY_PATH="$BUNDLE/lib:/usr/qt/lib:/usr/lib"
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_mali
export QT_QPA_EGLFS_ROTATION=90
export QT_QPA_FONTDIR=/usr/share/fonts
export QT_QPA_GENERIC_PLUGINS="evdevtouch:/dev/input/event0 evdevkeyboard:/dev/input/event1"
export QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=/dev/input/event0:rotate=90
export QT_QPA_EGLFS_PHYSICAL_WIDTH=155
export QT_QPA_EGLFS_PHYSICAL_HEIGHT=98
export PA_ALSA_PLUGHW=1
export HOME=/tmp
export XDG_RUNTIME_DIR=/tmp
exec chrt -f 99 taskset -c 2,3 $BUNDLE/bin/mixxx -platform eglfs --settingsPath $BUNDLE/settings --resourcePath $BUNDLE "$@"
