# Launch & CPU Shielding — Denon Prime Go + MIXXX

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

### Wrapper Script

```bash
#!/bin/sh
# mixxx_launcher.sh — deployed to /media/az01-internal/mixxx/

MIXDIR="/media/az01-internal/mixxx"

# System libs FIRST, bundled libs for MIXXX-specific deps
# /usr/qt/lib provides Denon's optimized Qt5.15.2 binaries
export LD_LIBRARY_PATH="$MIXDIR/lib:/usr/qt/lib:/usr/lib:/lib"
export QT_PLUGIN_PATH="$MIXDIR/qt-plugins:/usr/qt/plugins"
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_emu
export QT_QPA_EGLFS_KMS_ATOMIC=1
export HOME=/root

# Stop Engine DJ to release ALSA hardware locks
systemctl stop engine 2>/dev/null || true

# GPU performance governor (matches Engine's setup)
echo performance > /sys/devices/platform/ffa30000.gpu/devfreq/ffa30000.gpu/governor 2>/dev/null || true

# Launch MIXXX pinned to CPU 2-3 with real-time FIFO priority 99
exec taskset -c 2,3 chrt -f 99 "$MIXDIR/bin/mixxx" -platform eglfs \
  --settingsPath "$MIXDIR/settings" \
  --resourcePath "$MIXDIR/share/mixxx"
```

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
