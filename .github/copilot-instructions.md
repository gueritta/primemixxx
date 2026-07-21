# Denon Prime 4 — Agent Constitution

> Rules, assertions, invariants, paths, and version constraints only.
> Zero prose. Zero background. See `docs/ONBOARDING.md` for context.

---

## CRITICAL RULES — Violating any of these breaks the device

### Assertions

- RULE_ID: "BINARY-WORKING"
- ASSERTION: Only `lib/bin/mixxx` (~10 MB) is a working binary. `mixxx.real` (~17 MB) crashes.
- CHECK: `file $BUNDLE/bin/mixxx` must show symlink to `../lib/bin/mixxx`. Must NOT point to `../mixxx.real`.
- VIOLATION: `bin/mixxx` is not a symlink, or points to `mixxx.real` → EGLFS crash "OpenGL windows cannot be mixed with others"

- RULE_ID: "SYSLIBS-FORBIDDEN"
- ASSERTION: These 9 libraries MUST NOT exist in the bundle. They MUST come from device `/lib`:
  `libc.so.6` `libm.so.6` `libpthread.so.0` `libdl.so.2` `librt.so.1`
  `libstdc++.so.6` `libgcc_s.so.1` `ld-linux-armhf.so.3` `libatomic.so.1`
- CHECK: `ls $BUNDLE/lib/libc.so.6 2>/dev/null` must return nothing. `scripts/fix-device-libs.sh` must be run after every `collect-mixxx-bundle.sh`.
- VIOLATION: Any of these libs present in bundle → segfault (kernel ABI mismatch)

- RULE_ID: "MALI-DDK-R1P0"
- ASSERTION: `libEGL.so`, `libGLESv2.so`, `libGLESv1_CM.so` on the SD card MUST be symlinks to `/usr/lib/libmali.so.14.0`.
- CHECK: `readlink $BUNDLE/lib/libEGL.so` must return `/usr/lib/libmali.so.14.0`
- VIOLATION: Buildroot's r0p0 libs present → EGL init failure or black screen

- RULE_ID: "MALI-INTEGRATION"
- ASSERTION: `QT_QPA_EGLFS_INTEGRATION` MUST be `eglfs_mali`.
- CHECK: `grep QT_QPA_EGLFS_INTEGRATION mixxx-bundle/mixxx_launcher.sh` must output `eglfs_mali`
- VIOLATION: Any other integration (e.g. `eglfs_emu`) → black screen

- RULE_ID: "QT-VERSION"
- ASSERTION: SD card Qt 5.15.8 MUST be used. Device Qt 5.15.2 MUST NOT be the primary Qt.
- CHECK: `ls $BUNDLE/lib/libQt5Core.so.5` must exist. `libqeglfs-mali-integration.so` must exist in `$BUNDLE/qt-plugins/egldeviceintegrations/`.
- VIOLATION: Missing SD Qt bundle or using device Qt as primary → black screen

- RULE_ID: "MASK-FORBIDDEN"
- ASSERTION: `mixxx-app.service` MUST NOT be masked.
- CHECK: `systemctl status mixxx-app.service 2>&1 | grep -q masked` must return 1 (not found)
- VIOLATION: Service masked to `/dev/null` → TKGL's `systemd-run --unit=mixxx-app` fails silently

- RULE_ID: "RESOURCE-PATH-ROOT"
- ASSERTION: `--resourcePath` MUST be `$BUNDLE` (the bundle root), NEVER `$BUNDLE/bin`.
- CHECK: `grep -- '--resourcePath' mixxx-bundle/mixxx_launcher.sh` must show `$BUNDLE`, not `$BUNDLE/bin`
- VIOLATION: Resource path points to `bin/` → MIXXX can't find skins, translations, etc.

- RULE_ID: "DISPLAY-ROTATION"
- ASSERTION: `QT_QPA_EGLFS_ROTATION` MUST be `90`. Touchscreen evdev rotate MUST be `90`.
- CHECK: `grep QT_QPA_EGLFS_ROTATION mixxx-bundle/mixxx_launcher.sh` must output `90`
- CHECK: `grep EVDEV_TOUCHSCREEN mixxx-bundle/mixxx_launcher.sh` must output `rotate=90`
- VIOLATION: Wrong rotation → display orientation or touch coordinates mismatch

- RULE_ID: "LAUNCHER-SINGLE-SOURCE"
- ASSERTION: There is exactly ONE canonical launcher: `mixxx-bundle/mixxx_launcher.sh`
- CHECK: `grep -rl "exec.*bin/mixxx" --include="*.sh" tkgl-bootstrap/ buildroot-customizations/ | grep -v "/data/mixxx/mixxx" | wc -l` must return 0 (no other launcher invokes `bin/mixxx` directly)
- VIOLATION: Any .sh file outside the canonical path that invokes `./bin/mixxx` directly

### Constraints

- CONSTRAINT_ID: "QT-KMS-ATOMIC"
- NEVER set `QT_QPA_EGLFS_KMS_ATOMIC=1`
- REASON: Breaks Mali integration on Prime Go display

- CONSTRAINT_ID: "NO-SCHED-FIFO-99"
- NEVER launch the main MIXXX process at `SCHED_FIFO 99`
- REASON: Causes ALL 44+ child threads (Mali GPU, touchscreen, CachingReader, Qt pool, GLib, etc.) to inherit RT priority and compete with audio. Instead: launch at `SCHED_OTHER`, then selectively boost only the 2 audio engine threads to `SCHED_FIFO 98` post-launch.

- CONSTRAINT_ID: "NO-DEVICE-QT-PRIMARY"
- NEVER use device Qt 5.15.2 + `eglfs_emu` as the primary display backend
- REASON: `eglfs_emu` cannot take over the display from fbcon → black screen

---

## FILE LAYOUT — Absolute Paths, Single Source of Truth

| Artifact Type | Canonical Location |
|---|---|
| MIDI JS mappings | `mixxx-bundle/mixxx-mapping/prime-go/*.js` |
| MIDI XML mappings | `mixxx-bundle/mixxx-mapping/prime-go/*.midi.xml` |
| Launcher script | `mixxx-bundle/mixxx_launcher.sh` |
| TKGL module entry | `tkgl-bootstrap/modules/mod_mixxx/tkgl_mod_mixxx.sh` |
| TKGL config | `tkgl-bootstrap/modules/mod_mixxx/mixxx.cfg` |
| Entry point (internal) | `buildroot-customizations/…/data/mixxx/mixxx` |
| Firmware launcher | `buildroot-customizations/…/usr/bin/mixxx_launcher.sh` |
| Buildroot defconfig | `buildroot/configs/denon_prime_go_defconfig` |
| SD card layout spec | `SD-CARD.md` |
| User documentation | `docs/` |
| Onboarding (prose, context) | `docs/ONBOARDING.md` |

---

## VERSION CONSTRAINTS — Exact, not Approximate

```
- MIXXX binary:     lib/bin/mixxx (10 MB), NOT mixxx.real (17 MB)
- Qt version:       5.15.8 (bundled on SD), NOT 5.15.2 (device system)
- Mali DDK:         r1p0 ONLY, via symlinks to /usr/lib/libmali.so.14.0
- Kernel:           5.10.109-inmusic-rt64 (PREEMPT_RT)
- Buildroot:        2021.02.10
- Device arch:      armv7l (Cortex-A17)
- Cross-compiler:   buildroot/output/host/bin/arm-buildroot-linux-gnueabihf-
- ALSA device:      hw:JP11,0
- Display:          LVDS-1, framebuffer 800×1280 portrait, display controller rotates to 1280×800 landscape
```

---

## DIRECTORY ROLES — What each directory IS and MUST NOT contain

```
mixxx-bundle/                                         | SD card root. Contains everything deployed. Source of truth.
mixxx-bundle/mixxx-mapping/prime-go/                  | Prime Go mappings. ALL controller JS/XML lives here.
tkgl-bootstrap/                                       | Device-side bootstrap. Modules here. NO document copies.
tkgl-bootstrap/modules/mod_mixxx/                     | TKGL boot path. tkgl_mod_mixxx.sh (thin caller) + config. NO launcher or mapping copies.
buildroot-customizations/board/inmusic/jp11/rootfs_overlay/ | Firmware overlay. Entry point + firmware launcher only.
scripts/                                              | Build/deploy tooling. No runtime artifacts.
docs/                                                 | Human documentation. No rules, no code.
```

---

## PRE-COMMIT CHECKS — Must all pass before any commit

```
1. No duplicate mapping files in tkgl-bootstrap (symlinks to canonical are OK):
   for f in Denon-Prime-Go-scripts.js Denon-Prime-Go.midi.xml; do
     tkgl="tkgl-bootstrap/modules/mod_mixxx/$f"
     if [ -L "$tkgl" ]; then
       # Symlink is correct — resolves to canonical
       :
     elif [ -f "$tkgl" ]; then
       echo "FAIL: $f is a regular file duplicate in tkgl-bootstrap"; exit 1
     fi
   done

2. No launcher copy in tkgl-bootstrap (canonical launcher is on SD card):
   if [ -f "tkgl-bootstrap/modules/mod_mixxx/mixxx_launcher.sh" ]; then
     echo "FAIL: tkgl-bootstrap contains a launcher copy"; exit 1
   fi

3. No plaintext secrets outside DEPLOY.md and build scripts:
   FILES=$(grep -rl "denonprime" --include="*.md" . 2>/dev/null | \
           grep -v "DEPLOY.md" | grep -v "copilot-instructions.md" | grep -v ".git/" || true)
   if [ -n "$FILES" ]; then
     echo "FAIL: password in committed .md file outside DEPLOY.md: $FILES"; exit 1
   fi

4. Resource path correctness:
   grep -q '\--resourcePath.*\$BUNDLE[^/]' mixxx-bundle/mixxx_launcher.sh || \
     { echo "FAIL: --resourcePath must be \$BUNDLE root, not \$BUNDLE/bin"; exit 1; }

5. No KMS_ATOMIC in any launcher:
   grep -r "KMS_ATOMIC" --include="*.sh" mixxx-bundle/ tkgl-bootstrap/ buildroot-customizations/ 2>/dev/null && \
     { echo "FAIL: KMS_ATOMIC set in launcher"; exit 1; } || true
```

---

## AGENT BEHAVIOR RULES

```
- When generating a new controller mapping, place it in mixxx-bundle/mixxx-mapping/prime-go/ ONLY.
- When asked to modify launcher behavior, modify ONLY mixxx-bundle/mixxx_launcher.sh.
- When asked to fix a build issue, check the VERSION CONSTRAINTS section first.
- Before claiming a fix is complete, run the PRE-COMMIT CHECKS.
- If a user asks to copy a file instead of symlinking, WARN about duplication rules.
- NEVER hardcode the device IP or password in any generated script. Use the DEVICE_IP env var.
- After any SCP-based file change on the device, update the local repo to match. The repo is always the source of truth.
```

---

## PACKAGE / ENVIRONMENT CONSTANTS

```
- Device IP:          set via DEVICE_IP env var, never hardcoded
- Device hostname:    primego.local (mDNS)
- Device arch:        armv7l (Cortex-A17)
- Cross-compiler:     buildroot/output/host/bin/arm-buildroot-linux-gnueabihf-
- ALSA device:        hw:JP11,0
- Display:            LVDS-1, framebuffer 800×1280 portrait → 1280×800 landscape
- Audio format:       S32_LE, 4 channels, 44100 Hz
- Audio latency:      period_size=1024 (23.2ms), buffer_size=2048 (46.4ms)
- CPU shielding:      MIXXX on cores 2-3, non-audio threads banished to 0-1
- IRQ affinity:       all non-audio IRQs pinned to CPU 0
- RT throttle:        sched_rt_runtime_us=-1 (disabled)
```

---

## DOCUMENTATION INDEX

| Doc | Covers |
|---|---|
| `docs/ONBOARDING.md` | Architecture, hardware, boot chain, MIDI table, build overview, known issues |
| `docs/launch.md` | Boot chain details, CPU shielding, wrapper scripts |
| `docs/display.md` | Mali GPU, DDK mismatch, EGLFS configuration |
| `docs/audio.md` | ALSA routing, XMOS/AKM hardware chain |
| `docs/midi.md` | Full MIDI control table |
| `docs/hardware-reference.md` | LED protocols, SysEx format |
| `docs/firmware.md` | Firmware flashing notes |
| `docs/sentry.md` | Sentry error tracking |
| `SD-CARD.md` | SD card layout, library listing, launcher script |
| `DEPLOY.md` | Deployment workflow, troubleshooting |
| `BROKEN_EXPERIMENTS.md` | Failed experiments — DO NOT repeat |
