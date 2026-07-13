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
│   │   └── libqeglfs-mali-integration.so   # Custom Mali integration (CRITICAL for display)
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
├── controllers/                           # Controller mappings (loaded by Mixxx via bin/controllers symlink)
│   ├── Denon-Prime-4*.xml, *-scripts.js   # Prime 4 mapping
│   └── prime-go/Denon-Prime-Go*.xml, *-scripts.js  # Prime GO mapping
├── mixxx-mapping/                         # Source copy (hand-crafted, preserved across collect runs)
├── mixxx_launcher.sh                      # Wrapper: stops engine, sets env, CPU shielding
├── settings/                              # MIXXX runtime settings (created at launch)
│   └── mixxx.cfg
├── share/
│   └── mixxx/                             # Resource path (skins, translations, etc.)
└── backup/                                # Device binary backup
    └── mixxx.bak                          # MD5: a0365bdce2162c1a09d0ba77ab4af227
```

## Launcher Script (Working Version on Device: `/data/mixxx/mixxx`)

The firmware overlay at `buildroot-customizations/board/inmusic/jp11/rootfs_overlay/usr/bin/mixxx_launcher.sh`
matches this script. The entry point called by TKGL bootstrap.

```sh
#!/bin/sh
# MIXXX Launcher — Denon Prime Go (SD card binary + USB bind-mount)
MIXDIR="/media/az01-internal/mixxx"
BUNDLE="$MIXDIR"
SETTINGS="$MIXDIR/settings"

# Wait for USB (up to 15s)
for i in $(seq 0 15); do
    if [ -b /dev/sda1 ]; then break; fi
    sleep 1
done

# Mount USB if plugged, bind-mount to trusted ext4 path
if [ -b /dev/sda1 ]; then
    mkdir -p /media/AE1F-B2D6
    mount /dev/sda1 /media/AE1F-B2D6 -o ro,fmask=0022,dmask=0022 2>/dev/null || true
    if [ -d /media/AE1F-B2D6/tuv ]; then
        mkdir -p "$MIXDIR/music"
        mount --bind /media/AE1F-B2D6/tuv "$MIXDIR/music" 2>/dev/null || true
    fi
fi

# Restore seed DB if current DB is missing/corrupted
# MIXXX loads library dirs from SQLite 'directories' table, not mixxx.cfg
if [ ! -f "$SETTINGS/mixxxdb.sqlite" ] || [ $(stat -c%s "$SETTINGS/mixxxdb.sqlite" 2>/dev/null || echo 0) -lt 5000 ]; then
    if [ -f "$SETTINGS/mixxxdb.seed" ]; then
        cp "$SETTINGS/mixxxdb.seed" "$SETTINGS/mixxxdb.sqlite"
    fi
fi

# SD card's bundled Qt 5.15.8 + custom Mali integration (eglfs_mali)
export LD_LIBRARY_PATH="$BUNDLE/lib:/usr/lib:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$BUNDLE/qt-plugins"
export QT_QPA_FONTDIR=/usr/share/fonts
export QT_QPA_GENERIC_PLUGINS=evdevtouch:evdevmouse:evdevkeyboard
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_mali
export QT_QPA_EGLFS_KMS_ATOMIC=1
export QT_QPA_EGLFS_ROTATION=90
export QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS="/dev/input/event0:rotate=90"
export QT_LOGGING_RULES="qt.qpa.evdevtouch=true;qt.qpa.input=true"

for g in /sys/class/devfreq/*mali*/governor /sys/class/devfreq/*gpu*/governor; do
    [ -f "$g" ] && echo performance > "$g" 2>/dev/null
done

export HOME=/root
export XDG_RUNTIME_DIR=/tmp

systemctl stop engine 2>/dev/null || true
sleep 0.5

exec taskset -c 2,3 chrt -f 99 "$BUNDLE/bin/mixxx" -platform eglfs \
  --settingsPath "$SETTINGS" \
  --resourcePath "$BUNDLE/bin" \
  "$@"
```

## Systemd Service

There are two service paths:

### 1. Firmware overlay: `/usr/lib/systemd/system/mixxx.service`
The canonical service definition in the Buildroot overlay. Sources `mixxx_launcher.sh`.

### 2. TKGL Bootstrap: `/etc/systemd/system/tkgl-mixxx.service`
The actual service used at boot (TKGL framework). Can be masked with
`systemctl mask tkgl-mixxx` or overridden by the `mixxx` service.

### Boot chain:
```
tkgl-mixxx.service → /data/tkgl-bootstrap-launcher → tkgl_mod_mixxx.sh
  → systemd-run --unit=mixxx-app → /data/mixxx/mixxx → SD card launcher → MIXXX
```

### Important: `mixxx-app.service` must NOT be masked
The TKGL module uses `systemd-run --unit=mixxx-app` to create a transient unit.
If the name is masked (`/dev/null`), `systemd-run` fails silently and MIXXX
won't start at boot. If masked, unmask with:
```bash
systemctl unmask mixxx-app.service 2>/dev/null || true
```

### To re-enable the simple service:

## USB MP3 Library: Sandbox Bypass & Seed DB

### Problem
1. MIXXX sandbox silently blocks vfat filesystems → USB library won't scan
2. MIXXX loads library directories from SQLite `directories` table, NOT from `mixxx.cfg` → fresh DB = empty `directories` table = scanner idle
3. First-run wizard (which imports config→DB) is skipped by EGLFS dialog suppression

### Solution
1. **Bind-mount USB to ext4 path** bypasses sandbox: `mount --bind /media/AE1F-B2D6/tuv /media/az01-internal/mixxx/music`
2. **Seed DB** (`mixxxdb.seed`) pre-populated with `directories` table entry pointing to the bind-mount path
3. **Wrapper** restores seed DB if current DB is missing or < 5KB

### Config (mixxx.cfg)
```ini
[Config]
FirstRun=1
HasScreenedForLibraryDir=1
[Library]
Directory[0]=/media/az01-internal/mixxx/music
RescanOnStartup=1
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

## Known Issues (Current State)

1. **Screen rotation:** `QT_QPA_EGLFS_ROTATION=90` — Mali renders portrait (800×1280), display controller rotates to landscape (1280×800).
2. **Mali DDK mismatch:** Bundled `libEGL.so`/`libGLESv2.so` from Buildroot target r0p0; device has r1p0. **FIXED:** Symlinks on SD card point all EGL/GLES libs to `/usr/lib/libmali.so.14.0`. The deployment script handles this automatically.
3. **Qt version:** Buildroot cross-compiles MIXXX against Qt 5.15.8. The SD card bundles this exact Qt version (under `lib/`). Device's native Qt 5.15.2 is **NOT used** — it causes a black screen with `eglfs_emu`. **CRITICAL:** The launcher MUST use `$BUNDLE/lib` (SD card's Qt 5.15.8) in `LD_LIBRARY_PATH`, NOT `/usr/qt/lib`.
4. **WiFi power save:** Must run `iw dev wlan0 set power_save off` — not persistent across reboots.
5. **USB UUID:** The USB mount path `/media/AE1F-B2D6` assumes a specific vfat UUID. If the USB key is reformatted, update the launcher accordingly.

## Deployment Scripts

- `scripts/collect-mixxx-bundle.sh` — Gathers MIXXX + deps from Buildroot output into `mixxx-bundle/`
- `scripts/deploy-to-device.sh` — SCPs bundle to device, installs systemd service + switchers, backs up existing SD card
- `scripts/fix-device-libs.sh` — Removes system-critical libs from deployed bundle on device
- `scripts/quick-fix-deploy.sh` — Redeploys only changed files for fast iteration
