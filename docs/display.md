# Display & GPU — Denon Prime Go + MIXXX

## Mali-T76x GPU

The Prime Go uses an ARM Mali-T76x GPU (4 cores, r1p0 0x0750) integrated into the Rockchip RK3288 SoC. The stock firmware auto-selects the correct Mali driver variant via `/sbin/az01-libmali-setup` at boot, which bind-mounts `libmali-r1p0.so.14.0` based on the GPU hardware revision read from `/sys/devices/platform/ffa30000.gpu/gpuinfo`.

## Qt5 EGLFS Configuration

### DDK Mismatch (Critical)

This is a classic issue when building the "Digital Twin" for cross-compilation. You are encountering this error because your Buildroot environment is pulling a generic or outdated Mali Driver Development Kit (`r0p0`), whereas the Denon Prime hardware specifically utilizes **`libmali 14.0 (r1p0, without OpenCL)`**. 

Because Engine OS bypasses X11/Wayland and uses the `eglfs` plugin to render directly to the Rockchip framebuffer (`/dev/fb0`), the user-space driver (`libmali.so`) linked during compilation must match the exact Application Binary Interface (ABI) expected by the device's kernel-space driver. A DDK version mismatch will cause EGL initialization to fail or result in linking errors.

### Resolution

**1. Extract the Native `r1p0` Blob (Scraping the ABI)**
Instead of relying on Buildroot's default package for the Mali GPU, you must pull the exact proprietary driver from the official firmware. 
* Use the firmware extraction workflow (`dumpimage` -> `xz -d` -> loopback mount) to unpack the official `rootfs.img`.
* Navigate to the `/usr/lib` (or `/usr/qt/lib`) directory within the extracted filesystem and copy the native `libmali.so` (and its associated symlinks like `libEGL.so`, `libGLESv2.so`).

**2. Inject into the Buildroot Sysroot**
Copy these extracted `r1p0` binaries directly into your Buildroot environment's `sysroot` (typically located at `output/host/arm-buildroot-linux-gnueabihf/sysroot/usr/lib/` or `output/staging/usr/lib/`). This forces your CMake toolchain to link Mixxx against the exact GPU driver version present on the target hardware.

**3. Strip OpenCL from your Build Configuration**
The specific `r1p0` Mali driver deployed by Denon is explicitly compiled **without OpenCL support**. Ensure that your `mixxx.mk` CMake configuration strictly disables OpenCL features, or the linker will fail when it attempts to find OpenCL symbols in the injected `libmali.so`.

**4. Runtime Linking**
When you deploy Mixxx to the hardware, ensure that your `LD_LIBRARY_PATH` environment variable prioritizes the device's native library directories. This guarantees that Mixxx utilizes the hardware's optimized `r1p0` binaries at runtime, completing the hardware-accelerated GLES pipeline.

**Quick fix for existing build**: Symlink the bundled libEGL/libGLESv2 to the system Mali driver:
```bash
cd /media/az01-internal/mixxx/lib
rm -f libEGL.so libGLESv2.so libGLESv1_CM.so
ln -sf /usr/lib/libmali.so.14.0 libEGL.so
ln -sf /usr/lib/libmali.so.14.0 libGLESv2.so
ln -sf /usr/lib/libmali.so.14.0 libGLESv1_CM.so
```

### Required Environment Variables (Working Configuration)

```bash
# Use SD card's bundled Qt 5.15.8 — NOT device's Qt 5.15.2
export LD_LIBRARY_PATH="/media/az01-internal/mixxx/lib:/usr/qt/lib:/usr/lib"
export QT_PLUGIN_PATH="/media/az01-internal/mixxx/qt-plugins"
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_mali          # Custom Mali integration (not emu)
export QT_QPA_EGLFS_ROTATION=90
export QT_QPA_FONTDIR=/usr/share/fonts
export QT_QPA_GENERIC_PLUGINS=evdevtouch:/dev/input/event0,evdevkeyboard:/dev/input/event1
export QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=/dev/input/event0:rotate=0
export HOME=/tmp
```

### Key Points

- **SD card's bundled Qt 5.15.8 + `eglfs_mali` is the working combination.** Device-native Qt 5.15.2 with `eglfs_emu` causes a black screen — the Mali EGLFS integration can't take over the display from fbcon. The SD card's custom-built `libqeglfs-mali-integration.so` (14KB, built with the MIXXX buildroot) handles display takeover correctly.
- **System Mali libs must be used** — Buildroot's bundled `libEGL.so`/`libGLESv2.so` target Mali DDK `r0p0` which is incompatible with the device's `r1p0`. All EGL/GLES symlinks in the SD card's `lib/` point to `/usr/lib/libmali.so.14.0`.
- **Custom Mali integration plugin:** `/media/az01-internal/mixxx/qt-plugins/egldeviceintegrations/libqeglfs-mali-integration.so` — built from the same Qt 5.15.8 source as the bundled Qt libs. This is the critical component that enables display output.
- **KMS/DRM**: The GPU drives the built-in 7-inch display via `/dev/dri/card0` (DRM connector status: "connected"). fbcon may still hold DRM plane-4 but Mali GPU outputs via hardware overlay.
- **Touchscreen**: ILI2117 detected on `/dev/input/event0`, works with evdev input plugin with `QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS="/dev/input/event0:rotate=90"`.
- **Dialog suppression:** The SD card's MIXXX binary (10 MB at `lib/bin/mixxx`) handles EGLFS gracefully. The `mixxx.real` binary (17 MB) is a different build that crashes with `EGLFS: OpenGL windows cannot be mixed with others`. Only `lib/bin/mixxx` should be used. `nodialog.so` exists at `lib/nodialog.so` as a fallback for other Qt builds but is NOT used in the default launcher.

### GPU Performance

```bash
# Set GPU governor to performance (matches Engine's setup)
echo performance > /sys/devices/platform/ffa30000.gpu/devfreq/ffa30000.gpu/governor

# Check GPU info
cat /sys/devices/platform/ffa30000.gpu/gpuinfo
```
