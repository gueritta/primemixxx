# Denon Prime 4 — Agent Constitution

> Rules, assertions, invariants, paths, and version constraints.
> For full architecture context and rationale, see `docs/ONBOARDING.md`.

## QUICK NAVIGATION

| If you need to… | Section |
|---|---|
| Fix a segfault or black screen | [CRITICAL RULES](#critical-rules--violating-any-of-these-breaks-the-device) |
| Build firmware or bundle | [BUILD, TEST, AND LINT COMMANDS](#build-test-and-lint-commands) |
| Deploy to the device | [Deployment workflow](#deployment-workflow) |
| Understand the boot chain | [HIGH-LEVEL ARCHITECTURE](#high-level-architecture) |
| Edit a controller mapping | [Controller mapping workflow](#controller-mapping-workflow) |
| Edit the skin (QSS, layout, buttons) | [Skin development](#skin-development) + `mixxx-bundle/skins/LateNightMini/copilot-instructions.md` |
| Pull changes back from device | [Runtime modification workflow](#runtime-modification-workflow--critical) |
| Restart MIXXX on device | [Restarting MIXXX](#restarting-mixxx-on-device) |
| Debug on device | [Debugging on device](#debugging-on-device) |

## WHAT THIS PROJECT IS

Custom firmware + MIXXX deployment for **Denon DJ Prime Go** hardware (Rockchip RK3288 ARMv7, Mali-T76x GPU, PREEMPT_RT kernel). MIXXX (open-source DJ software) runs from an internal SD card alongside the stock Engine OS — the two are switchable on demand. Three layers: **Buildroot firmware customization**, **SD card runtime bundle**, and **TKGL boot-time framework** on a separate SD card.

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
- CHECK: `ls $BUNDLE/lib/libc.so.6 2>/dev/null` must return nothing. `scripts/dev-fix-device-libs.sh` must be run after every `dev-collect-mixxx-bundle.sh`.
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

- RULE_ID: "RESTART-PROPER"
- ASSERTION: When restarting MIXXX after skin/config changes, MUST use `systemctl restart engine.service` (NOT `systemctl restart mixxx-app.service` and NOT `pkill mixxx`).
- CORRECT: `systemctl stop mixxx-app.service; systemctl restart engine.service`
- WRONG: `systemctl restart mixxx-app.service` (TKGL module checks `is-active` and returns early if the unit is still running)
- WRONG: `pkill mixxx; systemctl restart engine.service` (orphaned mixxx-app.service unit stays active, TKGL skips relaunch)
- REASON: `engine.service` triggers TKGL bootstrap → `tkgl_mod_mixxx.sh` → `systemd-run --unit=mixxx-app`. The module checks if mixxx-app is already active and skips if so. You MUST stop mixxx-app.service first so TKGL recreates it.

- RULE_ID: "SHEBANG-SH-ONLY"
- ASSERTION: ALL shell scripts deployed to the device MUST use `#!/bin/sh`, NEVER `#!/bin/bash`.
- CHECK: `head -1 scripts/device/*.sh` must show only `#!/bin/sh`.
- VIOLATION: `#!/bin/bash` shebang → "not found" error on device (Buildroot has no bash, only ash/sh).
- REASON: Buildroot 2021.02.10 ships only BusyBox ash. `/bin/bash` does not exist on the device.

- RULE_ID: "EVAL-NO-REDIRECT"
- ASSERTION: NEVER use `eval $SSH_CMD` (or any `eval` wrapper) for commands containing `>`, `>>`, `<`, `<<`, or `|`.
- CHECK: `grep 'eval.*|.*ssh' scripts/dev-deploy-to-device.sh` must return nothing if the eval'd string contains redirect/pipes.
- VIOLATION: `eval` interprets `>` as LOCAL file redirection (writes to host filesystem, not device). `eval` interprets `|` as LOCAL pipe (pipes on host, not device). Both break silently with confusing "Permission denied" or "not found" errors.
- CORRECT PATTERN: `cat localfile | sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "cat > /remote/path"`
- ACCEPTABLE: Simple `eval $SSH_CMD "$SSH_TARGET" "command"` without `>`, `<`, `|`, or `<<` is OK.
- REASON: `eval` strips one level of quoting and re-parses the string. Shell metacharacters (`>`, `|`, `<<`) that were quoted inside the eval'd argument become unquoted during re-parsing and get interpreted by the LOCAL shell.

- RULE_ID: "HEREDOC-FORBIDDEN-DEPLOY"
- ASSERTION: dev-deploy-to-device.sh MUST NOT contain heredocs (`<<`). All device files must exist as local source-of-truth files in `scripts/device/`.
- CHECK: `grep -c '<< ' scripts/dev-deploy-to-device.sh` must return 0.
- VIOLATION: Heredocs in deploy scripts are fragile — they require `eval` (see EVAL-NO-REDIRECT) and duplicate content that should live in version-controlled files.
- CORRECT: Create `scripts/device/<filename>` then deploy with `cat scripts/device/<filename> | sshpass ssh "cat > /dest/path"`.

- RULE_ID: "MDNS-PRIMEGO"
- ASSERTION: Avahi mDNS MUST advertise `primego.local`, NOT `buildroot.local`.
- CHECK: `ssh root@$DEVICE_IP "ps | grep avahi-daemon | grep primego"` must find a match.
- FIX: `DEVICE_IP=... bash scripts/dev-install-device-services.sh` — this deploys `fix-mdns.sh` + `fix-mdns.service` which run at boot and are idempotent.
- VIOLATION: Avahi defaults to `buildroot.local` → mDNS doesn't resolve `primego.local`.

- RULE_ID: "ETC-OVERLAY-COLD-BOOT"
- ASSERTION: NEVER rely on `/etc/systemd/system/` unit files, drop-ins, or `.target.wants/` symlinks being visible at COLD BOOT.
- CHECK: `mount | grep '/etc type overlay'` returns `upperdir=/data/system/etc/overlay`. The `/data` partition (mmcblk0p7 ext4) mounts AFTER systemd reads unit files. At cold boot, systemd sees ONLY the read-only lowerdir (`/etc` from ROM).
- VIOLATION: Any new systemd service (e.g. `usb-gadget-eth.service`, `fix-mdns.service`) placed in `/etc/systemd/system/` will be SILENTLY ABSENT at cold boot — systemd can't find the unit file. Symlinks in `multi-user.target.wants/` pointing to missing files resolve to nothing. Drop-ins in `.d/` directories are invisible. No error is logged — the service simply never starts.
- WORKAROUND: All cold-boot hooks MUST go through `/data/tkgl-bootstrap-launcher` (ext4, mounted before systemd reads units). `engine.service` is the ONLY service guaranteed to run at cold boot because it has a counterpart in `/usr/lib/systemd/system/` (ROM). Add early-boot commands to the bootstrap stub, not to systemd units.
- POST-BOOT: After the device is fully booted, run `systemctl daemon-reload && systemctl reenable <service>` to make unit files visible. Services started this way persist until next cold boot.
- FIX PATTERN: See `scripts/device/tkgl-bootstrap-stub.sh` — the USB Ethernet gadget is started via `/usr/sbin/usb-gadget-eth.sh 2>/dev/null &` at the top of the stub, bypassing systemd entirely.

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

> NOTE: `/data/mixxx` and `/media/az01-internal/mixxx` are the same filesystem (bind mount of mmcblk0p7).
> TKGL bootstrap lives on a SEPARATE SD card at `/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/`.

### SD Card Bundle (local: `mixxx-bundle/`, device: `/data/mixxx/` = `/media/az01-internal/mixxx/`)

| Artifact Type | Canonical Location (local repo) | Device path |
|---|---|---|
| MIDI JS mappings | `mixxx-bundle/mixxx-mapping/prime-go/*.js` | `/data/mixxx/controllers/*.js` (flat, no `mixxx-mapping/` subdir) |
| MIDI XML mappings | `mixxx-bundle/mixxx-mapping/prime-go/*.midi.xml` | `/data/mixxx/controllers/*.midi.xml` |
| Launcher script | `mixxx-bundle/mixxx_launcher.sh` | `/data/mixxx/mixxx_launcher.sh` |
| MIXXX settings template | `mixxx-bundle/settings/mixxx.cfg` | `/data/mixxx/settings/mixxx.cfg` (runtime-modified, diff from template) |

### TKGL Bootstrap (local: `tkgl-bootstrap/`, device: `/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/`)

| Artifact Type | Canonical Location (local repo) | Device path |
|---|---|---|
| TKGL module entry | `tkgl-bootstrap/modules/mod_mixxx/tkgl_mod_mixxx.sh` | `…/modules/mod_mixxx/tkgl_mod_mixxx.sh` |
| TKGL install module | `tkgl-bootstrap/modules/mod_install/tkgl_mod_install.sh` | `…/modules/mod_install/tkgl_mod_install.sh` |
| TKGL bootstrap script | `tkgl-bootstrap/scripts/tkgl_bootstrap` | `…/scripts/tkgl_bootstrap` |
| TKGL path config | `tkgl-bootstrap/scripts/tkgl_path` | `…/scripts/tkgl_path` |
| TKGL doer list | `tkgl-bootstrap/doer_list` | `…/doer_list` |

### Firmware Overlay (local: `buildroot-customizations/…/rootfs_overlay/`, device: `/`)

> **NOTE:** `buildroot-customizations/` is a **git submodule** (remote: `../buildroot-enginedevices.git`, branch: `mixxx`). Changes here live in a separate repo. Use `git submodule update --init` after clone.

| Artifact Type | Canonical Location (local repo) | Device path |
|---|---|---|
| Entry point (thin delegator) | `buildroot-customizations/…/data/mixxx/mixxx` | `/data/mixxx/mixxx` |
| Firmware launcher (thin delegator) | `buildroot-customizations/…/usr/bin/mixxx_launcher.sh` | `/usr/bin/mixxx_launcher.sh` |

### Other

| Artifact Type | Canonical Location |
|---|---|
| Buildroot defconfig | `buildroot/configs/denon_prime_go_defconfig` |
| SD card layout spec | `SD-CARD.md` |
| User documentation | `docs/` |
| Onboarding (prose, context) | `docs/ONBOARDING.md` |

### Device-Only Paths (not in local repo — managed on device)

| Path | Purpose |
|---|---|
| `/data/mixxx/settings/mixxx.cfg` | Active MIXXX config (runtime-generated, differs from template) |
| `/data/mixxx/settings/controllers/` | Active controller preset copies |
| `/data/mixxx/lib/` | Qt 5.15.8 + Mali symlinks + no_hid_poll.so |
| `/data/mixxx/bin/mixxx` → `../lib/bin/mixxx` | MIXXX binary symlink |

---

## VERSION CONSTRAINTS — Exact, not Approximate

```
- MIXXX binary:     lib/bin/mixxx (10 MB), NOT mixxx.real (17 MB)
- Qt version:       5.15.8 (bundled on SD), NOT 5.15.2 (device system)
- Mali DDK:         r1p0 ONLY, via symlinks to /usr/lib/libmali.so.14.0
- Kernel:           6.1.111-inmusic-2024-09-19-rt41 (PREEMPT_RT)
- Buildroot:        2021.02.10
- Device arch:      armv7l (Cortex-A17)
- Cross-compiler:   buildroot/output/host/bin/arm-buildroot-linux-gnueabihf-
- ALSA device:      hw:JP11,0
- Display:          LVDS-1, framebuffer 800×1280 portrait, display controller rotates to 1280×800 landscape
```

---

## DIRECTORY ROLES — What each directory IS and MUST NOT contain

```
mixxx-bundle/                                         | SD card root. Source of truth for all deployed content.
mixxx-bundle/mixxx-mapping/prime-go/                  | LOCAL-ONLY canonical mapping directory. Device has flat controllers/.
mixxx-bundle/controllers/                             | Symlinks into mixxx-mapping/prime-go/ (local-only, reflects device flat dir).
mixxx-bundle/settings/                                | MIXXX settings template (mixxx.cfg, soundconfig.xml).
tkgl-bootstrap/                                       | LOCAL representation of /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/.
tkgl-bootstrap/modules/mod_mixxx/                     | TKGL module + backup. NO mapping copies (symlinks OK). NO launcher copy.
buildroot-customizations/board/inmusic/jp11/rootfs_overlay/ | Firmware overlay. Entry point + firmware launcher only. Both thin delegators.
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

6. Launcher has duplicate-instance guard (device-verified feature):
   grep -q "pidof mixxx" mixxx-bundle/mixxx_launcher.sh || \
     { echo "FAIL: launcher missing pidof guard"; exit 1; }

7. TKGL module captured from device (not hand-edited):
   if [ -f "tkgl-bootstrap/modules/mod_mixxx/tkgl_mod_mixxx.sh" ]; then
     lines=$(wc -l < "tkgl-bootstrap/modules/mod_mixxx/tkgl_mod_mixxx.sh")
     if [ "$lines" -lt 50 ]; then
       echo "FAIL: tkgl_mod_mixxx.sh is too short (<50 lines), likely stripped version"; exit 1
     fi
   fi

8. Controller path in mixxx.cfg must NOT point to settings/controllers/:
   grep -q "settings/controllers/" mixxx-bundle/settings/mixxx.cfg && \
     { echo "FAIL: mixxx.cfg points to settings/controllers/ instead of controllers/"; exit 1; } || true
```

---

## MANDATORY COPIES — Files that MUST exist in multiple locations

These are NOT duplicates — they serve different purposes:

| File | Locations | Why |
|---|---|---|
| `Denon-Prime-Go-scripts.js` | `mixxx-bundle/controllers/` (symlink), `tkgl-bootstrap/…/` (symlink) | Symlinks to canonical `mixxx-mapping/prime-go/`. OK. |
| `Denon-Prime-Go.midi.xml` | Same as above | Same. |
| `mixxx.cfg` | `mixxx-bundle/settings/` (template), `/data/mixxx/settings/` (runtime) | Template vs active config — different content, different purpose. |
| `mixxx_launcher.sh` | `mixxx-bundle/` ONLY | Single canonical launcher. TKGL module calls entry point which delegates to it. |

---

## DEVICE FILESYSTEM REALITY (verified 2026-07-21)

```
/data/mixxx  ==  /media/az01-internal/mixxx    (same mmcblk0p7 ext4 bind mount)
/media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/  (separate SD card, ext4)

Boot chain:
  TKGL bootstrap → systemd-run → /data/mixxx/mixxx (entry) → /media/az01-internal/mixxx/mixxx_launcher.sh
```

---

## WIFI CONNECTIVITY — Keepalive Required

- RULE_ID: "WIFI-KEEPALIVE"
- ASSERTION: SSH to device via WiFi drops after ~30s of silence. MUST maintain continuous ping.
- ACTION: Before any SSH session, start: `ping -i 25 $DEVICE_IP > /dev/null 2>&1 &` and note the PID.
- ACTION: After work is complete, kill the ping process.
- VIOLATION: No keepalive ping → SSH hangs mid-session with "No route to host" or "Connection timed out".

---

## AGENT BEHAVIOR RULES

```
- DEVICE IS GROUND TRUTH. Before modifying any file, verify against the device via SSH.
- When generating a new controller mapping, place it in mixxx-bundle/mixxx-mapping/prime-go/ ONLY.
- When asked to modify launcher behavior, modify ONLY mixxx-bundle/mixxx_launcher.sh.
- When asked to fix a build issue, check the VERSION CONSTRAINTS section first.
- Before claiming a fix is complete, run the PRE-COMMIT CHECKS.
- If a user asks to copy a file instead of symlinking, WARN about duplication rules.
- NEVER hardcode the device IP or password in any generated script. Use the DEVICE_IP env var.
- Device password is in DEPLOY.md (denonprime4). Never hardcode it.
- After any SCP-based file change on the device, update the local repo to match. The repo is always the source of truth.
- CRITICAL: After modifying engine.service or tkgl-bootstrap-stub.sh, you MUST deploy them to the device. These files live on internal eMMC and are NOT part of the SD card bundle — they won't be updated by dev-deploy-to-device.sh. Run `DEVICE_IP=... ./scripts/dev-install-device-services.sh` or manually scp them.
```

### Runtime modification workflow — CRITICAL

When editing files directly on the device at runtime (SSH in, tweak, restart MIXXX to test), you MUST sync them back to the local repo BEFORE committing. The deploy scripts are unidirectional (local → device) — there is no automated pull-back.

**Connecting to the device (two methods):**

```bash
# Primary: USB Ethernet gadget (always works, no WiFi dropouts)
ssh root@192.168.42.1   # password: denonprime4

# Fallback: WiFi (requires keepalive ping)
ping -i 25 $DEVICE_IP > /dev/null 2>&1 &   # start keepalive first
ssh root@$DEVICE_IP
kill %1   # stop keepalive when done
```

**Every runtime editing session MUST end with pulling changed files back:**

```bash
DEV=root@192.168.42.1  # or root@$DEVICE_IP
BUNDLE=/media/az01-internal/mixxx

# 0. Before pulling, back up the SD card (EXCLUDE music/ — it's USB content, not SD)
#    Also skip lib/ (huge, rebuildable), bin/ (binary), logs, and databases:
BACKUP_DIR="sdcard-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
scp $DEV:$BUNDLE/mixxx_launcher.sh "$BACKUP_DIR/"
scp -r $DEV:$BUNDLE/controllers "$BACKUP_DIR/"
scp -r $DEV:$BUNDLE/skins "$BACKUP_DIR/"
scp -r $DEV:$BUNDLE/settings "$BACKUP_DIR/"
# ⚠ NEVER scp $BUNDLE/music/ — it's a USB mount point, NOT SD card content
# ⚠ NEVER scp $BUNDLE/lib/ or $BUNDLE/bin/ — they're large and rebuildable

# 1. Controller mappings (most frequently edited at runtime)
scp $DEV:$BUNDLE/controllers/Denon-Prime-Go-scripts.js mixxx-bundle/mixxx-mapping/prime-go/
scp $DEV:$BUNDLE/controllers/Denon-Prime-Go.midi.xml mixxx-bundle/mixxx-mapping/prime-go/
scp $DEV:$BUNDLE/controllers/Denon-Prime-Go-Jog-Wheels.midi.xml mixxx-bundle/mixxx-mapping/prime-go/
scp $DEV:$BUNDLE/controllers/Denon-Prime-Go-jog-wheel-scripts.js mixxx-bundle/mixxx-mapping/prime-go/
scp $DEV:$BUNDLE/controllers/LateNightMini_toggle_helper.js mixxx-bundle/mixxx-mapping/prime-go/
scp $DEV:$BUNDLE/controllers/common-*.js mixxx-bundle/mixxx-mapping/prime-go/

# 2. Skin files (LateNightMini is canonical)
scp -r $DEV:$BUNDLE/skins/LateNightMini /tmp/device-LateNightMini
diff -rq mixxx-bundle/skins/LateNightMini /tmp/device-LateNightMini | grep -v "\.bak"
# Merge any differences into mixxx-bundle/skins/LateNightMini/

# 3. Runtime configs (rewritten by MIXXX on every run)
scp $DEV:$BUNDLE/settings/mixxx.cfg mixxx-bundle/settings/
scp $DEV:$BUNDLE/settings/effects.xml mixxx-bundle/settings/
scp $DEV:$BUNDLE/settings/samplers.xml mixxx-bundle/settings/
scp $DEV:$BUNDLE/settings/soundconfig.xml mixxx-bundle/settings/

# 4. System files (service units, udev rules, scripts)
scp $DEV:/etc/systemd/system/mixxx.service scripts/device/
scp $DEV:/usr/sbin/powerbutton-monitor scripts/device/
scp $DEV:/etc/systemd/system/powerbutton-monitor.service scripts/device/
scp $DEV:/usr/sbin/usb-gadget-eth.sh scripts/device/
scp $DEV:/etc/systemd/system/usb-gadget-eth.service scripts/device/
scp $DEV:/etc/udev/rules.d/99-wifi-power-save.rules scripts/device/

# 5. Launcher and entry point
scp $DEV:$BUNDLE/mixxx_launcher.sh mixxx-bundle/
scp $DEV:/data/mixxx/mixxx mixxx-bundle/
```

**After pulling, always verify:**
```bash
# Check what changed
git status --short

# CRITICAL: Verify controller path in mixxx.cfg points to controllers/ NOT settings/controllers/
grep "settings/controllers" mixxx-bundle/settings/mixxx.cfg && echo "FAIL: wrong path!" || echo "OK"

# Run pre-commit checks
./scripts/dev-verify-launcher.sh
./scripts/dev-check-duplicates.sh
```

**Canonical skin is LateNightMini** (`mixxx-bundle/skins/LateNightMini/`). RoundCorners (`mixxx-bundle/skins/roundcorners/`) is a legacy reference kept locally for history but never deployed to device. All skin work goes into LateNightMini.

**Files that MUST be committed together**: controller mappings + skin + launcher + runtime configs form a single deployable unit. Never commit one without verifying the others are in sync.

**`settings/controllers/` is WRONG.** Controller files live in `controllers/` (flat). MIXXX writes stale copies to `settings/controllers/` at runtime — these must be cleaned up and `mixxx.cfg` must point to `controllers/`. Check on every pull-back.

---

## PACKAGE / ENVIRONMENT CONSTANTS

```
- Device IP (WiFi):   set via DEVICE_IP env var, never hardcoded
- Device IP (USB):    192.168.42.1 (USB Ethernet gadget, always available)
- Device hostname:    primego.local (mDNS, may not resolve from all networks)
- Device SSH pass:    denonprime4 (from DEPLOY.md — never hardcode)
- Preferred SSH:      USB Ethernet at 192.168.42.1 — no keepalive needed, no dropouts
- Device arch:        armv7l (Cortex-A17)
- Device kernel:      6.1.111-inmusic-2024-09-19-rt41 (PREEMPT_RT)
- Cross-compiler:     buildroot/output/host/bin/arm-buildroot-linux-gnueabihf-
- ALSA device:        hw:JP11,0
- Display:            LVDS-1, framebuffer 800×1280 portrait → 1280×800 landscape
- Audio format:       S32_LE, 4 channels, 44100 Hz
- Audio latency:      period_size=1024 (23.2ms), buffer_size=2048 (46.4ms)
- CPU shielding:      MIXXX on cores 2-3, non-audio threads banished to 0-1
- IRQ affinity:       all non-audio IRQs pinned to CPU 0
- RT throttle:        sched_rt_runtime_us=-1 (disabled)
- TKGL SD card:       /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/ (mmcblk1p1, separate from main SD)
- Primary SD card:    /media/az01-internal/mixxx (mmcblk0p7 ext4, same as /data/mixxx)
```

---

## BUILD, TEST, AND LINT COMMANDS

### Firmware build pipeline (host)

```bash
./unpack.sh              # Download and unpack original firmware
./clone-buildroot.sh     # Clone Buildroot 2021.02.10
./compile-buildroot.sh   # Build toolchain + packages (requires sudo)
./pack.sh                # Pack modified images → firmware .dtb
```

Or use Makefile targets: `make unpack`, `make clone-buildroot`, etc.

### MIXXX bundle pipeline (developer)

```bash
./scripts/dev-collect-mixxx-bundle.sh    # Gather MIXXX + deps from Buildroot output into mixxx-bundle/
./scripts/dev-fix-device-libs.sh         # Remove system-critical libs from bundle
DEVICE_IP=primego.local ./scripts/dev-deploy-to-device.sh  # SCP to device
./scripts/dev-quick-fix-deploy.sh        # Fast iteration: redeploy only changed files
```

### User-facing scripts

**Device scripts** — run ON the device from the TKGL SD card, no Buildroot or host needed:

```bash
sh /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/install-device.sh     # Install TKGL boot hook + optional services
sh /media/TKGL_BOOTSTRAP/tkgl_bootstrap_DenonPrimeGO/uninstall-device.sh   # Remove boot hook, restore Engine OS
```

`install-device.sh` backs up the original `engine.service` to `engine.service.orig`,
then installs the TKGL stub, engine.service, and interactively offers USB gadget,
power button monitor, mDNS fix, and WiFi powersave rule.

`uninstall-device.sh` is the inverse — stops MIXXX, removes the stub, restores
`engine.service.orig`, and interactively asks which optional services to keep.

**Host scripts** — run on your computer to create SD cards (no Buildroot required):

```bash
./scripts/dev-create-sdcard-bundle.sh        # Assemble a complete SD card tarball (from prebuilt mixxx-bundle/)
./scripts/dev-fix-sdcard-paths.sh            # Patch paths after extracting tarball to SD card
```

### Developer scripts (all prefixed `dev-`)

All scripts under `scripts/` with the `dev-` prefix are developer-only. They require
Buildroot output, SSH access to the device, or other dev tooling:

| Script | Purpose |
|---|---|
| `dev-collect-mixxx-bundle.sh` | Gather MIXXX + Qt libs from Buildroot into `mixxx-bundle/` |
| `dev-fix-device-libs.sh` | Remove 9 forbidden system libs from bundle |
| `dev-deploy-to-device.sh` | Full deploy via SCP (calls dev-install-device-services.sh) |
| `dev-install-device-services.sh` | Install engine.service, stub, switchers, udev rules, USB gadget, etc. |
| `dev-quick-fix-deploy.sh` | Fast iteration: redeploy only changed files |
| `dev-sync-all-back.sh` | Pull all runtime-edited files from device back to repo |
| `dev-sync-profiler-back.sh` | Pull profiler scripts from device back to repo |
| `dev-verify-launcher.sh` | Pre-commit: launcher integrity, single source, pidof guard |
| `dev-check-duplicates.sh` | Pre-commit: no duplicate mapping files |
| `dev-build-style-qss.sh` | Concatenate `style_qss/_*.qss` modules → `style.qss` |
| `dev-test-bootstrap.sh` | One-shot manual TKGL bootstrap test on device |
| `dev-patch-qt-to-5.15.2.sh` | Historical: downgrade Qt (NOT used — we need 5.15.8) |

Device scripts (deployed to the device, not run locally) live in `scripts/device/`:
`tkgl-bootstrap-stub.sh`, `switch-to-mixxx.sh`, `switch-to-engine.sh`,
`usb-gadget-eth.sh`, `fix-mdns.sh`, `powerbutton-monitor`, plus profiling tools
(`profiler.sh`, `cpu-latency.sh`, `xrun-monitor.sh`, `bench-harness.sh`).

### Go tools (cross-platform updater)

Module: `go/` (Go 1.24, `github.com/icedream/primemixxx/go`). Key deps: `go-fltk` for GUI, `gousb` for USB flashing, `xz` for firmware decompression, `u-root` for fastboot. Dependency updates managed by Renovate (`renovate.json` at repo root).

```bash
cd go
go build ./cmd/updater/      # Build the GUI firmware updater (FLTK-based, requires build-fltk)
go build ./cmd/find_update/  # Build the CLI update finder (no GUI deps)
go test ./pkg/updater/       # Run updater package tests (XZ decompression)
go test ./pkg/fastboot/      # Run fastboot package tests
go test ./...                # Run all Go tests
```

Cross-compile for Windows: `make -C go all-windows-amd64`

### Pre-commit verification

```bash
./scripts/dev-verify-launcher.sh     # Launcher integrity: single source, pidof guard, TKGL module size
./scripts/dev-check-duplicates.sh    # No duplicate mapping files outside canonical location
```

Both scripts exit non-zero on failure — run before every commit. They also serve as standalone debugging tools: `dev-verify-launcher.sh` checks launcher correctness, `dev-check-duplicates.sh` finds duplicate mappings outside canonical locations.

### Fast iteration (device)

```bash
./scripts/dev-quick-fix-deploy.sh    # Redeploy only changed files, skip full bundle collection
```

### Build DTS→DTB firmware images

```bash
make PRIMEGO-4.3.4-STOCK-SSH-Update.img.dtb   # Build SSH-enabled stock firmware (SSH+WiFi auto-provisioned)
make PRIMEGO-4.3.4-Update.img.dtb             # Build custom MIXXX-enabled firmware
```

All `PRIMEGO-*.img.dtb` and `PRIME4-*.img.dtb` targets are built from corresponding `.dts` files via `mkimage -f`. The Makefile also provides shorthand targets (`make unpack`, `make clone-buildroot`, `make compile-buildroot`, `make pack`) that delegate to the same-named shell scripts.

---

## HIGH-LEVEL ARCHITECTURE

This is a **custom firmware + MIXXX deployment** for Denon DJ Prime Go hardware (Rockchip RK3288 ARMv7, Mali-T76x GPU, PREEMPT_RT kernel). MIXXX runs from an internal SD card alongside the stock Engine OS — the two are switchable on demand.

### Three layers of the project

1. **Buildroot customization** (`buildroot-customizations/`): Adds SSH, MIXXX, and TKGL bootstrap to the stock Buildroot firmware. Output is a `.dtb` firmware image flashed via USB using the Go updater.

2. **SD card bundle** (`mixxx-bundle/`): Contains the MIXXX binary, Qt 5.15.8, Mali GPU shims, MIDI mappings, launcher script, and settings. This is the runtime environment — deployed via SCP to `/media/az01-internal/mixxx/`.

3. **TKGL bootstrap** (`tkgl-bootstrap/`): A modular boot-time framework on a separate SD card. Handles USB mounting, seed DB restoration, GPU governor, IRQ affinity, and launching MIXXX via `systemd-run`.

### Boot chain

```
Power-on → U-Boot → Linux kernel → systemd → tkgl-mixxx.service
  → TKGL bootstrap → mod_mixxx → systemd-run --unit=mixxx-app
    → /data/mixxx/mixxx (thin delegator on internal storage)
      → /media/az01-internal/mixxx/mixxx_launcher.sh (SD card)
        → MIXXX binary with CPU shielding (cores 2-3, audio threads at SCHED_FIFO 98)
```

### Key architectural decisions

- **Qt 5.15.8 bundled on SD card**, not device Qt 5.15.2 — device's `eglfs_emu` can't take over the display from fbcon
- **Mali r1p0 DDK** via symlinks to device's `/usr/lib/libmali.so.14.0` — Buildroot ships incompatible r0p0
- **PREEMPT_RT kernel** with CPU shielding — audio threads isolated on cores 2-3, everything else banished to 0-1
- **SD card as runtime environment** — unplug to fall back to stock Engine OS, internal storage never modified at runtime

### MIDI architecture

All hardware controls (platters, faders, pads, buttons) are exposed as internal USB MIDI across 6 channels:
- Channels 1-2: Mixer (PFL, EQ, fader, sweep FX)
- Channels 3-4: Decks (transport, pads, jog, tempo)
- Channel 5: DJ FX
- Channel 16: Global (browse, view, shift, load)

MIXXX mappings live in `mixxx-bundle/mixxx-mapping/prime-go/` (canonical) and deploy flat to device's `controllers/` directory. The mapping uses JavaScript (`Denon-Prime-Go-scripts.js`) for LED feedback (SysEx RGB), pad modes, shift layers, and jog wheel handling, plus XML (`Denon-Prime-Go.midi.xml`) for static MIDI→control bindings.

---

## KEY CONVENTIONS

### Controller mapping workflow

1. **Canonical location**: `mixxx-bundle/mixxx-mapping/prime-go/` — ALWAYS create new mappings here
2. **Flat deployment**: Device stores mappings in `/data/mixxx/controllers/` (flat, no subdirectories)
3. **Local symlinks**: `mixxx-bundle/controllers/` contains symlinks into `mixxx-mapping/prime-go/` to mirror the device's flat structure
4. **TKGL symlinks**: `tkgl-bootstrap/modules/mod_mixxx/` may contain symlinks to canonical (separate SD card on device)
5. **No regular file duplicates** — if the same file exists in two locations, one must be a symlink

### Skin development

- Skin lives in `mixxx-bundle/skins/LateNightMini/` (Tango-derived, heavily customized for 1280×800 touchscreen)
- **CRITICAL**: WPushButton has a stale-read bug on Qt 5.15.8 EGLFS — use the `_trig` CO toggle pattern. Full documentation and conversion rules at `mixxx-bundle/skins/LateNightMini/copilot-instructions.md`
- `style.qss` is split into 5 modules in `style_qss/`: `_base.qss`, `_library.qss`, `_controls.qss`, `_buttons.qss`, `_deck2.qss`
- Build QSS from modules: `./scripts/dev-build-style-qss.sh` — concatenates all `_*.qss` files in order into `style.qss`
- Resolution architecture: Physical display 1280×800 landscape, GPU framebuffer 800×1280 portrait, Qt logical screen 1280×800 (EGLFS_ROTATION=90), display HW rotates output
- **SizeAwareStack breakpoints MUST match 800px world** — any breakpoint ≥800 triggers wrong template at native resolution. The skin always runs at 1280px (≥801 breakpoint → lg template)
- **44px minimum touch targets**, 4px grid spacing
- `print()` is silent on device — use `console.warn()` or `engine.log()` for debug output

### Deployment workflow

1. Collect bundle: `./scripts/dev-collect-mixxx-bundle.sh`
2. Fix system libs: `./scripts/dev-fix-device-libs.sh`
3. Deploy to device: `DEVICE_IP=... ./scripts/dev-deploy-to-device.sh`
4. For fast iteration (skin/mapping changes): `./scripts/dev-quick-fix-deploy.sh`
5. After deployment, restart MIXXX: `ssh root@$DEVICE_IP 'systemctl stop mixxx-app.service; systemctl restart engine.service'`
6. **Always update the local repo after device-side changes** — the repo is the source of truth

### Restarting MIXXX on device

**ONLY correct way:**
```bash
systemctl stop mixxx-app.service; systemctl restart engine.service
```

NEVER use `systemctl restart mixxx-app.service` or `pkill mixxx` — TKGL checks `is-active` and skips relaunch if the unit is still running or orphaned.

### Switching between Engine OS and MIXXX (device)

```bash
# Switch from Engine OS to MIXXX
ssh root@$DEVICE_IP switch-to-mixxx

# Switch from MIXXX back to Engine OS
ssh root@$DEVICE_IP switch-to-engine
```

These are scripts at `/usr/bin/switch-to-mixxx` and `/usr/bin/switch-to-engine` deployed by `dev-deploy-to-device.sh`.

### USB music library (sandbox bypass)

MIXXX's sandbox silently blocks vfat filesystems, preventing USB drive scanning. The launcher works around this by mounting USB drives to an ext4 path (`$BUNDLE/music`). A seed database (`mixxxdb.seed`) pre-populates the `directories` table so MIXXX knows where to scan without going through the first-run wizard. Library directories live in SQLite (`mixxxdb.sqlite`, `directories` table), NOT in `mixxx.cfg`.

### WiFi connectivity

SSH via WiFi drops after ~30s of silence. Before any SSH session, maintain a keepalive:
```bash
ping -i 25 $DEVICE_IP > /dev/null 2>&1 &
```
Kill the ping PID when done.

### Debugging on device

- `print()` is **silent** on Buildroot Qt5 EGLFS — use `console.warn()` or `engine.log()` instead
- Check boot logs: `journalctl -u tkgl-mixxx` or `ls /var/log/tkgl/mixxx*.log`
- Verify MIXXX running: `ps | grep mixxx`, `systemctl status mixxx-app.service`
- Verify USB mount: `mount | grep "az01-internal/mixxx/music"`
- Verify library DB: `sqlite3 /media/az01-internal/mixxx/settings/mixxxdb.sqlite "SELECT directory FROM directories;"`
- MIXXX segfaults: check system libs exclusion, Mali DDK symlinks, and binary symlink targets (see CRITICAL RULES)

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
| `SD-CARD.md` | SD card layout, library listing, launcher script, audio optimization stack |
| `DEPLOY.md` | Deployment workflow, troubleshooting, switch-to-mixxx/engine |
| `BROKEN_EXPERIMENTS.md` | Failed experiments — DO NOT repeat |
| `SKIN-TODO.md` | Skin and hardware mapping pending tasks, resolution architecture, critical pitfalls |
