# Broken Experiments & Dead Ends

Documenting approaches that didn't work, why they failed, and what replaced them.

---

## Qt 5.15.2 Downgrade → Reverted

**Attempt:** Downgrade buildroot Qt from 5.15.8 to 5.15.2 to match device runtime Qt version, avoiding ABI mismatch.

**Failure:** Qt 5.15.2 is incompatible with GCC 16 (the host compiler). Build errors across multiple Qt modules due to C++17/C++20 standards changes.

**Resolution:** Reverted to Qt 5.15.8 in buildroot. Bundle simplified to use device's native Qt 5.15.2 libs at runtime instead of bundling compiled Qt. Launchers set `QT_PLUGIN_PATH` and `LD_LIBRARY_PATH` to point at device libs.

**Commit:** `a2aab70 fix: revert Qt 5.15.2 downgrade, simplify bundle, fix mixxx.service`

---

## eglfs_mali Rotation → Blocked

**Attempt:** Use Mali GPU's native `eglfs_mali` integration (`QT_QPA_EGLFS_INTEGRATION=eglfs_mali`) for automatic screen rotation handling. Mali renders to 800×1280 portrait fb0, display controller rotates output to 1280×800 landscape.

**Failure:** After applying the OpenGL-skip widget fix (MIXXX PR #15874 backport), `eglfs_mali` crashes on startup. Additionally, Mali's `orientation()`/`nativeOrientation()` functions ignore `QT_QPA_EGLFS_ROTATION` — all rotation values produce the same 90°-off output.

**Rejected approach:** `QT_QPA_EGLFS_ROTATION` (any value) — Mali fbdev compositor ignores it.

**Engine DJ approach:** Uses `QPainter::rotate`/`QTransform` internally with `AIR_SCREEN_ROTATION=270` from device tree. Does NOT use Qt EGLFS rotation.

**Current status:** Blocked. Two possible paths:
1. Fix `eglfs_mali` crash with Qt logging (`QT_LOGGING_RULES=qt.qpa.egl*=true`)
2. Implement QTransform/QGraphicsView rotation fallback wrapping MIXXX central widget

**Session:** `9cd6dae7` — Deploy MIXXX onto Denon Prime Go

---

## SSH Disabled in Custom Firmware → Blocker

**Attempt:** Flash custom firmware (`PRIMEGO-4.3.4-Update.img.dtb`) to device over USB. Expected SSH access for further debugging.

**Failure:** After successful flash, device comes online (ping OK) but port 22 is refused. sshd.service is not enabled in the buildroot defconfig — probably missing `BR2_PACKAGE_OPENSSH` or sshd service enablement in the rootfs overlay.

**Impact:** Cannot SSH into device after flashing custom firmware. Have to restore stock firmware to regain access.

**Resolution needed:** Check `jp11_defconfig` for OpenSSH/sshd enablement, add sshd.service to rootfs overlay, rebuild.

**Session:** `c1fae510` — Recovered Plan

---

## primego-v3.dts (Original) → Superseded

**Attempt:** DTS referencing stock `unpacked-img/JP11/splash.img.xz` — the original unmodified stock firmware image.

**Superseded by:** `primego-v3-fixed.dts` which references `unpacked-ssh-img/stock-tkgl.img.xz` — stripped stock with SSH key pre-installed and USB ethernet enabled.

**Why removed:** The original v3 DTS doesn't include SSH access, making on-device debugging impossible.

---

## updater Binary in Git → Removed

**Attempt:** Committed the compiled `updater` Go binary (ELF x86-64, 15MB) directly to the repository.

**Why removed:** Binaries don't belong in git. The source is in `go/pkg/fastboot/` and can be rebuilt. Was removed during repository cleanup.

---

## COPILOT_HISTORY.md → Removed

**Attempt:** Raw Copilot CLI command history log for context preservation.

**Why removed:** Contains no structured information beyond raw user prompts. Session data preserved in `.copilot/session-state/` directories. Replaced by proper git commit history.
