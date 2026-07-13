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

The actual working launcher on the device is minimal — 14 lines. The TKGL bootstrap framework
handles USB mounts, seed DB restoration, and GPU governor. This script only sets environment
variables and launches MIXXX.

```bash
#!/bin/sh
# MIXXX Launcher — Denon Prime Go (SD card)
# Minimal: env only. USB mount, seed DB, GPU governor handled by TKGL bootstrap.
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
exec taskset -c 2,3 chrt -f 99 $BUNDLE/bin/mixxx -platform eglfs --settingsPath $BUNDLE/settings --resourcePath $BUNDLE
```

**Key env vars (correct values):**
| Variable | Value | Notes |
|----------|-------|-------|
| `LD_LIBRARY_PATH` | `$BUNDLE/lib:/usr/qt/lib:/usr/lib` | SD Qt 5.15.8 first, then device Qt 5.15.2 (/usr/qt/lib), then system |
| `QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS` | `/dev/input/event0:rotate=0` | Touch coordinates match physical orientation |
| `HOME` | `/tmp` | Not `/root` |
| `QT_QPA_EGLFS_KMS_ATOMIC` | not set | Not needed for Mali integration |
| `--resourcePath` | `$BUNDLE` (root) | Not `$BUNDLE/bin` |

**What the launcher does NOT do (handled by TKGL bootstrap):**
- USB mount and bind-mount
- Seed DB restoration
- GPU performance governor
- `systemctl stop engine`
- `QT_LOGGING_RULES`

### USB MP3 Library: Sandbox Bypass (TKGL)

The TKGL bootstrap framework handles USB mounting and seed DB restoration.
The SD card launcher itself is minimal and does not include this logic.



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
