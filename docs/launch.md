# Launch & CPU Shielding — Denon Prime Go + MIXXX

## Boot Chain (Working Configuration)

At boot, `tkgl-mixxx.service` fires, which starts the TKGL bootstrap framework:

```
tkgl-mixxx.service → /data/tkgl-bootstrap-launcher
  → sources mod_mixxx/tkgl_mod_mixxx.sh
    → systemd-run --unit=mixxx-app -- /data/mixxx/mixxx
      → /media/az01-internal/mixxx/mixxx_launcher.sh  (SD card)
        → SD Qt 5.15.8 + eglfs_mali + USB bind-mount + seed DB
          → exec taskset chrt /media/az01-internal/mixxx/bin/mixxx
```

**Critical: `mixxx-app.service` must NOT be masked.** The TKGL module uses `systemd-run --unit=mixxx-app` to create a transient unit. If the name is masked (`/etc/systemd/system/mixxx-app.service → /dev/null`), systemd-run fails and MIXXX never starts.

### Entry Point: `/data/mixxx/mixxx`

A thin delegation script (116 bytes) that calls the SD card launcher:
```sh
#!/bin/sh
exec /media/az01-internal/mixxx/mixxx_launcher.sh "$@"
```

The SD card launcher stays on the SD card where it can be updated independently. The entry point on internal storage only needs to exist at boot time.

### TKGL Module: `tkgl_mod_mixxx.sh`

Minimal — delegates all env/mount/display config to the SD launcher. Sets only `HOME` and `XDG_RUNTIME_DIR`. Does NOT set `LD_LIBRARY_PATH`, `QT_PLUGIN_PATH`, `QT_QPA_*`, `--settingsPath`, or `-platform` — these would override the SD launcher's configuration.

## TKGL Bootstrap Framework

To implement the **`tkgl_bootstrap`** framework, you are setting up a modular, "tethered" exploitation environment that allows you to run custom scripts without permanently altering or risking your core operating system. 

Because the stock firmware does not natively look for external startup scripts, implementing this framework requires a one-time firmware modification to inject an "execution hook" into the boot sequence. 

### 1. Inject the Bootstrap Hook (Firmware Repacking)
You cannot use `tkgl_bootstrap` on a completely stock device. You must first flash a custom firmware image (such as the SSH-enabled drops from the *icedream* or *Hakai* projects). 
During the creation of this custom firmware, developers modify the system initialization scripts (the ones managed by `systemd` or `busybox` init) to include a specific execution hook. This hook is programmed to run very early in the boot sequence, specifically right before the `engine.service` launches the main DJ application. 

### 2. Prepare the External Media
Once your device is running the modified firmware containing the hook, take a standard USB flash drive or SD card and format it to **FAT32** or **ext4**. 

### 3. Create the Bootstrap Directory
On the root level of your newly formatted USB drive or SD card, create a folder and name it exactly **`tkgl_bootstrap`**.

### 4. Add Your Custom Scripts
Place your custom shell scripts or binaries inside the `tkgl_bootstrap` folder. Depending on your goals, these scripts can be written to:
*   Launch networking daemons (like an SSH or VNC server).
*   Alter MIDI configurations (using `LD_PRELOAD` libraries to spoof hardware).
*   Kill the native UI (`systemctl stop engine`) and launch an alternative application like Mixxx or Akai Force software from a chroot sandbox.

### 5. Boot the Device
Plug the USB drive into your Denon Prime or inMusic device and power it on. As the device boots, the injected hook will scan the external media, locate the `tkgl_bootstrap` directory, and automatically execute your arbitrary shell scripts before the main software locks down the hardware.

### The Primary Benefit
By implementing your mods this way, you protect the internal memory. If your custom script contains an error and causes a kernel panic or system crash, you do not need to disassemble the hardware to recover it. You simply **unplug the USB drive and reboot**; the device will bypass the hook and return to its pristine, stock state.

---

## CPU Shielding Wrapper

Le **CPU shielding** (isolation ou protection du processeur) est un mécanisme critique implémenté dans le script bash de lancement (souvent appelé "wrapper") lors de la phase de "Hostile Takeover" (Prise de contrôle hostile). 

Voici comment il fonctionne et pourquoi il est indispensable :

*   **Protection du tampon audio (Audio Buffer) :** La fonction principale du CPU shielding est de **protéger le tampon audio matériel, qui est extrêmement court (inférieur à 5 millisecondes)**. 
*   **Priorité d'exécution absolue :** Étant donné que l'exécution d'une application personnalisée comme Mixxx sur ce matériel se fait via un "déploiement parasite" (Parasitic Deployment) qui tourne par-dessus le système d'origine sans modifier le noyau Linux existant, le script doit forcer le matériel à se concentrer sur l'audio. Le CPU shielding permet de verrouiller et de dédier les cœurs du processeur (ARM Cortex-A17) aux threads audio de l'application avec une **priorité absolue en temps réel**.
*   **Prévention des coupures :** En isolant ainsi le processeur, le script garantit que les processus en arrière-plan du système d'exploitation ne viendront pas interrompre le décodage et le traitement du son. Cela permet d'obtenir des performances de "qualité native", évitant ainsi les craquements, la latence ou les coupures de son pendant une performance live.

En pratique, l'opération se déroule en deux temps : vous devez d'abord "tuer" l'interface native d'Engine OS avec la commande `systemctl stop engine` pour libérer les ressources, puis exécuter votre script wrapper qui va activer ce CPU shielding juste avant de lancer le binaire de votre application.

### Wrapper Script (Working Configuration)

The working setup uses the **SD card's bundled Qt 5.15.8** (not the device's Qt 5.15.2) with a custom-built `libqeglfs-mali-integration.so` for display. It also handles USB bind-mounting and seed DB restoration.

```bash
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

### USB MP3 Library: Sandbox Bypass

MIXXX's sandbox blocks access to vfat filesystems. The working solution:

1. **Bind-mount**: `mount --bind /media/AE1F-B2D6/tuv /media/az01-internal/mixxx/music`
   - The sandbox trusts the mount **path** (ext4), not the underlying filesystem (vfat)
   - Config: `Directory[0]=/media/az01-internal/mixxx/music` in `[Library]` section

2. **Seed DB**: MIXXX loads library directories from the `directories` SQLite table, NOT from `mixxx.cfg`
   - A fresh DB has an empty table → scanner does nothing
   - The first-run wizard imports config → DB, but is skipped by EGLFS dialog suppression
   - Solution: `mixxxdb.seed` pre-populated with the directories entry
   - Wrapper restores seed DB if mixxxdb.sqlite is missing or < 5KB

3. **sandbox.cfg**: Contains paths to whitelist (one per line). Placed at `settings/sandbox.cfg`.
   - Note: the bind-mount approach works without sandbox.cfg, but having both provides defense in depth.

### Config Reference (mixxx.cfg)

```ini
[Config]
FirstRun=1
HasScreenedForLibraryDir=1

[Library]
Directory[0]=/media/az01-internal/mixxx/music
RescanOnStartup 1
```

### Key Differences from Earlier Setup

| Component | Old (broken) | New (working) |
|-----------|-------------|---------------|
| Qt libs | Device Qt 5.15.2 (`/usr/qt/lib`) | SD card Qt 5.15.8 (`$BUNDLE/lib`) |
| EGLFS integration | `eglfs_emu` | `eglfs_mali` (custom built) |
| Mali plugin | Stock `libqeglfs-emu-integration.so` | Custom `libqeglfs-mali-integration.so` |
| USB access | Direct vfat mount (sandbox denied) | Bind-mount to ext4 path (sandbox granted) |
| Library dirs | From config (not imported to DB) | Seed DB with pre-populated `directories` table |
| Dialog suppression | LD_PRELOAD nodialog shim | Built-in (SD binary has "skipping dialog on EGLFS") |

## Systemd Service (Optional)

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

Enable with caution — disables Engine DJ at boot.

## Verified Boot Chain (Tested 2026-07-13)

The full chain was verified across a device reboot:

```
tkgl-mixxx.service (enabled)
  → /data/tkgl-bootstrap-launcher
    → tkgl_mod_mixxx.sh
      → systemd-run --unit=mixxx-app
        → /data/mixxx/mixxx (116 bytes delegation)
          → /media/az01-internal/mixxx/mixxx_launcher.sh (SD card)
            → USB bind-mount + seed DB restore
              → exec /media/az01-internal/mixxx/bin/mixxx
```

**Verified results after fresh boot (43s uptime):**
- ✅ `mixxx-app.service` transient created and active
- ✅ MIXXX PID 388 running from SD card binary
- ✅ USB bind-mount: `/dev/sda1` → `/media/az01-internal/mixxx/music`
- ✅ DB present: 307KB `mixxxdb.sqlite`
- ✅ Tracks visible in library

**Critical prerequisite:** `mixxx-app.service` must NOT be masked (`/dev/null`). If masked, `systemd-run` fails silently. Fix: `systemctl unmask mixxx-app.service`

## Switcher Scripts

### switch-to-mixxx
```bash
#!/bin/sh
mount -o remount,rw / 2>/dev/null
systemctl stop engine
/media/az01-internal/mixxx/mixxx_launcher.sh
```

### switch-to-engine
```bash
#!/bin/sh
killall mixxx 2>/dev/null
systemctl start engine
```

## Critical: System Libraries

The MIXXX bundle at `/media/az01-internal/mixxx/lib/` must NOT contain system-critical libraries that should come from the device's own `/lib`:

**Excluded from bundle**: `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1`, `libstdc++.so.6`, `libgcc_s.so.1`, `ld-linux-armhf.so.3`, `libatomic.so.1`

Bundling these from Buildroot causes kernel ABI incompatibility → segfault.
