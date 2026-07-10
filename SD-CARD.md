# SD Card Reconstruction — Denon Prime GO (`/media/az01-internal/mixxx/`)

## Identity

- **Mount point:** `/media/az01-internal` (internal SD card, mounted by `edisksd` service)
- **Activation:** `echo external > /sys/bus/platform/devices/sd-mux/state`
- **Evidence:** The `mount.sh` script creates `media/az01-internal` as the SD card mount target. Stock firmware's `setup-prerequisites.sh` activates the SD mux. This IS the real SD card, not a partition.

## Local Source Copy

The `mixxx-bundle/` directory in this repo is the **local mirror** of what was SCP'd to the device. It was created by `scripts/collect-mixxx-bundle.sh` from Buildroot output, then deployed via `scripts/deploy-to-device.sh` using SCP.

## Contents

```
/media/az01-internal/mixxx/
├── bin/
│   ├── mixxx                              # MIXXX 2.5.6 ARMv7 binary (~325MB unstripped)
│   └── mixxx.debug                        # Debug symbols
├── lib/                                   # 66 shared libraries
│   ├── libQt5*.so.5                       # Qt 5.15.8 (bundled, not device's 5.15.2)
│   ├── libEGL.so, libGLESv2.so, libGLESv1_CM.so  # Mali r1p0 shims → /usr/lib/libmali.so
│   ├── libasound.so.2                     # ALSA
│   ├── libportaudio.so.2, libportmidi.so.2  # Audio I/O
│   ├── libFLAC.so.12, libogg.so.0, libvorbis*.so  # Audio codecs
│   ├── libmp3lame.so.0, libmad.so.0       # MP3 codecs
│   ├── libsndfile.so.1                    # Sample file I/O
│   ├── libebur128.so.1                    # Loudness normalization
│   ├── libkeyfinder.so.2, libchromaprint.so.1  # Key/BPM detection
│   ├── librubberband.so.2                 # Time stretching
│   ├── libfftw3.so.3                      # FFT
│   ├── libqt5keychain.so.1                # Credential storage
│   ├── libprotobuf-lite.so.32             # Protocol Buffers
│   ├── liblilv-0, libserd-0, libsord-0, libsratom-0  # LV2 plugin host
│   ├── libSoundTouch.so.1                 # Pitch/tempo
│   ├── libid3tag.so.0, libtag.so.1        # Metadata
│   ├── libmodplug.so.1, libmp4v2.so.2     # Tracker/MP4
│   ├── libopus.so.0, libopusfile.so.0    # Opus codec
│   ├── libsystemd.so.0, libudev.so.1      # System integration
│   ├── libdbus-1.so.3                     # D-Bus
│   ├── libglib-2.0, libgio-2.0, libgobject-2.0, libgmodule-2.0, libgthread-2.0  # GLib
│   ├── libpcre.so.1, libpcre2-16.so.0     # Regex
│   ├── libffi.so.8                        # Foreign function interface
│   ├── libz.so.1                          # Compression
│   ├── libblkid.so.1, libmount.so.1       # Block device/mount
│   ├── libcap.so.2                        # POSIX capabilities
│   ├── libcrypto.so.1.1, libssl.so.1.1    # OpenSSL
│   ├── libsecret-1.so.0                   # Secret service
│   ├── libupower-glib.so.3                # Power management
│   └── libusb-1.0.so.0                    # USB
├── qt-plugins/                            # Qt 5.15.8 platform plugins
│   ├── platforms/
│   │   ├── libqeglfs.so                   # EGLFS (main)
│   │   ├── libqminimalegl.so
│   │   ├── libqminimal.so
│   │   └── libqoffscreen.so
│   ├── egldeviceintegrations/
│   │   └── libqeglfs-emu-integration.so   # EGLFS emu backend
│   ├── generic/
│   │   ├── libqevdevkeyboardplugin.so
│   │   ├── libqevdevmouseplugin.so
│   │   ├── libqevdevtabletplugin.so
│   │   └── libqevdevtouchplugin.so        # Touchscreen
│   ├── imageformats/
│   │   ├── libqico.so
│   │   └── libqsvg.so
│   ├── iconengines/
│   │   └── libqsvgicon.so
│   ├── sqldrivers/
│   │   └── libqsqlite.so
│   └── platformthemes/
│       └── libqxdgdesktopportal.so
├── mixxx-mapping/                         # Controller mappings
│   ├── Denon-Prime-4*.xml, *-scripts.js   # Prime 4 mapping
│   └── prime-go/Denon-Prime-Go*.xml, *-scripts.js  # Prime GO mapping
├── mixxx_launcher.sh                      # Wrapper: stops engine, sets env, CPU shielding
├── settings/                              # MIXXX runtime settings (created at launch)
│   └── mixxx.cfg
├── share/
│   └── mixxx/                             # Resource path (skins, translations, etc.)
└── backup/                                # Device binary backup
    └── mixxx.bak                          # MD5: a0365bdce2162c1a09d0ba77ab4af227
```

## Launcher Script (mixxx_launcher.sh)

```sh
#!/bin/sh
MIXDIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$MIXDIR"

# Device-native Qt5.15.2 first, bundled libs for MIXXX-specific deps
export LD_LIBRARY_PATH="/usr/qt/lib:/usr/lib:$BUNDLE/lib:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="/usr/qt/plugins"          # Device Qt plugins
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_emu
export QT_QPA_EGLFS_KMS_ATOMIC=1
export QT_QPA_EGLFS_ROTATION=90
export HOME=/root
export XDG_RUNTIME_DIR=/tmp

# GPU performance governor
for g in /sys/class/devfreq/*mali*/governor; do
    [ -f "$g" ] && echo performance > "$g" 2>/dev/null
done

# USB mount trigger
udevadm trigger --subsystem-match=block --action=add 2>/dev/null || true

# Stop Engine DJ → release ALSA & GPU
systemctl stop engine 2>/dev/null || true
sleep 0.5

# CPU shielding: cores 2-3, real-time FIFO priority 99
exec taskset -c 2,3 chrt -f 99 "$BUNDLE/bin/mixxx" -platform eglfs \
  --settingsPath "$BUNDLE/settings" \
  --resourcePath "$BUNDLE/bin"
```

## Systemd Service (on device)

```ini
# /etc/systemd/system/mixxx.service
[Unit]
Description=MIXXX DJ Software
Conflicts=engine.service
After=local-fs.target

[Service]
Type=simple
ExecStart=/media/az01-internal/mixxx/mixxx_launcher.sh
Restart=no
TTYPath=/dev/tty1
StandardInput=tty
StandardOutput=tty
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
```

## Switcher Scripts (on device)

### `/usr/bin/switch-to-mixxx`
```sh
#!/bin/sh
mount -o remount,rw / 2>/dev/null
systemctl stop engine
/media/az01-internal/mixxx/mixxx_launcher.sh
```

### `/usr/bin/switch-to-engine`
```sh
#!/bin/sh
killall mixxx 2>/dev/null
systemctl start engine
```

## CRITICAL: System Libs NOT on SD Card

These MUST come from device's `/lib` — bundled versions cause segfaults from kernel ABI mismatch:
- `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`
- `librt.so.1`, `libstdc++.so.6`, `libgcc_s.so.1`
- `ld-linux-armhf.so.3`, `libatomic.so.1`

## Known Issues at Time of Deployment

1. **Screen rotation:** `QT_QPA_EGLFS_ROTATION=90` — Mali renders portrait (800×1280), display controller rotates to landscape (1280×800). Rotation value uncertain.
2. **Mali DDK mismatch:** Bundled `libEGL.so`/`libGLESv2.so` may target wrong r0p0; device has r1p0. Fix: symlink to `/usr/lib/libmali.so.14.0`.
3. **Qt version mismatch:** Buildroot compiled against Qt 5.15.8, device has Qt 5.15.2. Launcher uses device Qt at runtime via `LD_LIBRARY_PATH`.
4. **WiFi power save:** Must run `iw dev wlan0 set power_save off` — not persistent across reboots.

## Deployment Scripts

- `scripts/collect-mixxx-bundle.sh` — Gathers MIXXX + deps from Buildroot output into `mixxx-bundle/`
- `scripts/deploy-to-device.sh` — SCPs bundle to device, installs systemd service + switchers, backs up existing SD card
- `scripts/fix-device-libs.sh` — Removes system-critical libs from deployed bundle on device
- `scripts/quick-fix-deploy.sh` — Redeploys only changed files for fast iteration
