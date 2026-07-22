# Optimization Audit — Denon Prime Go + MIXXX

> Audit date: 2026-07-22
> Scope: compile-time flags, runtime launcher, TKGL module, kernel-level

---

## 1. COMPILE-TIME: MIXXX Build (`mixxx.mk`)

### Enabled

| Flag | Effect |
|---|---|
| `-march=armv7ve` | ARMv7 + virtualization extensions |
| `-mtune=cortex-a17` | Codegen tuned for Cortex-A17 pipeline |
| `-mfpu=neon-vfpv4` | NEON SIMD (128-bit, 32×64-bit regs) + VFPv4 hardware float |
| `-mfloat-abi=hard` | FPU register passing (no soft-float overhead) |
| `-O3` | Aggressive optimization |
| `-ftree-vectorize` | Auto-vectorize scalar loops to NEON |
| `-funsafe-math-optimizations` | Relax IEEE compliance for speed (OK for audio DSP) |
| `-DOPTIMIZE=native` | MIXXX CMake: enables internal `-Ofast` equivalent + native arch detection |
| `-DQT_QPA_PLATFORM=eglfs` | EGLFS compositor at compile time |
| `-DOPENGL=ES -DQGLES2=ON -DQGLES3=ON` | OpenGL ES 2/3 mode (Mali GPU path) |

**Verdict: NEON is fully enabled.** The Cortex-A17 NEON unit (FMA, 128-bit loads) is leveraged for DSP loops (EQ, filter, FFT via fftw3, keyfinder, rubberband).

### Compile-time gaps

| Gap | Issue | Fix |
|---|---|---|
| `CONFIG_NO_HZ_FULL` | Not in kernel config | Tick fires on ALL cores including isolated 2-3. Needs kernel rebuild. |
| `CONFIG_HZ=1000` | 1kHz scheduler tick | ~0.1-0.2% CPU steal on audio cores. Tolerable with RT, but `nohz_full` would eliminate. |
| `rcu_nocbs` | Not set | RCU callbacks can land on audio cores. Needs kernel rebuild. |
| `CONFIG_FTRACE` | **Not set in buildroot config** | See §9 below for what's needed. `/sys/kernel/debug/tracing/` will be empty. |
| `CONFIG_SCHED_DEBUG` | Not set | `/proc/sched_debug` not available. |
| `CONFIG_SCHEDSTATS` | Not set | `/proc/schedstat` not available. |

> ⚠ **Device kernel caveat:** The buildroot config targets 6.1.78, but the device runs
> stock 6.1.111-inmusic-2024-09-19-rt41. The device's actual kernel config is unknown
> and may differ. Verify on-device: `zcat /proc/config.gz \| grep -E "FTRACE\|SCHED_DEBUG\|SCHEDSTATS\|PSI"`
> or check at runtime: `ls /proc/schedstat /proc/sched_debug /proc/pressure/cpu /sys/kernel/debug/tracing/ 2>&1`

---

## 2. RUNTIME: Launcher (`mixxx_launcher.sh`)

### Enabled

| # | Optimization | Line | Detail |
|---|---|---|---|
| L1 | CPU shielding | 58 | `taskset -c 2,3` pins MIXXX to audio-dedicated cores |
| L2 | RT throttling disabled | 55 | `sched_rt_runtime_us=-1` — audio threads get 100% CPU |
| L3 | Audio thread RT boost | 69-73 | EngineWorkerSch, EngineSideChain → SCHED_FIFO 98, pinned 2-3 |
| L4 | Non-audio thread banish | 76-82 | 16 thread patterns → SCHED_OTHER, pinned 0-1 |
| L5 | Main thread low-RT | 84-85 | SCHED_FIFO 1 on cores 2-3 (MIDI/UI responsiveness) |
| L6 | LD_PRELOAD hid fix | 28 | `no_hid_poll.so` skips broken hidraw udev scan |
| L7 | USB sandbox bypass | 17-23 | Mounts vfat USB to ext4 path |
| L8 | HOME on tmpfs | 52 | Avoids SD card write wear from config |
| L9 | Duplicate guard | 8-10 | `pidof mixxx` prevents double-launch |
| L10 | Mali DDK r1p0 | 38 | Symlinks → `/usr/lib/libmali.so.14.0` |
| L11 | SD Qt 5.15.8 | 30-32 | Bypasses device's broken Qt 5.15.2 + eglfs_emu |
| L12 | EGLFS rotation | 42 | `QT_QPA_EGLFS_ROTATION=90` |

### Runtime gaps (implementable without kernel rebuild)

| # | Priority | Optimization | Command | Benefit |
|---|---|---|---|---|
| R1 | **HIGH** | CPU freq governor → performance | `echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor` | RK3288 defaults to `ondemand` — freq transitions cause ~50µs latency spikes. Must stay at 1.8GHz. |
| R2 | **HIGH** | Disable Transparent Huge Pages | `echo never > /sys/kernel/mm/transparent_hugepage/enabled` | THP compaction causes 10-50ms stalls on RT kernels. |
| R3 | **HIGH** | Timer migration off | `echo 0 > /proc/sys/kernel/timer_migration` | Keeps timers on originating CPU — reduces cache line bouncing on isolated cores. |
| R4 | **MED** | Disable KSM | `echo 0 > /sys/kernel/mm/ksm/run` | KSM page scanning causes periodic latency spikes. |
| R5 | **MED** | VM writeback tuning | `sysctl vm.dirty_ratio=5 vm.dirty_background_ratio=1` | SD card writeback can stall audio threads. |
| R6 | **MED** | OOM protection | `echo -1000 > /proc/$MIXPID/oom_score_adj` | Prevent OOM killer from targeting MIXXX. |
| R7 | **MED** | Pin audio IRQ 45 to CPU 2 | `echo 4 > /proc/irq/45/smp_affinity` | Co-locate audio DMA IRQ with engine threads. |
| R8 | **LOW** | SD card noatime | Add `noatime,nodiratime` to mount options | Reduces metadata writes during library scans. |
| R9 | **LOW** | Disable IPv6 | `sysctl net.ipv6.conf.all.disable_ipv6=1` | Reduces kernel network stack overhead. |
| R10 | **LOW** | ALSA buffer reduction | Try period=512 (11.6ms) or 256 (5.8ms) | Lower latency; PREEMPT_RT should handle it. |

---

## 3. RUNTIME: TKGL Module (`tkgl_mod_mixxx.sh`)

### Enabled

| # | Optimization | Line | Detail |
|---|---|---|---|
| T1 | WiFi power save off | 17 | `iw dev wlan0 set power_save off` — prevents SSH drops |
| T2 | GPU governor → performance | 31-33 | Mali GPU at max clock |
| T3 | IRQ affinity | 38-44 | All non-critical IRQs (>31, except 45) → CPU 0 |
| T4 | Mali0 permissions | 29 | `chmod 666 /dev/mali0` |
| T5 | udev trigger | 34 | `udevadm trigger --subsystem-match=block` |
| T6 | Powerbutton monitor | 53 | Graceful shutdown on KEY_POWER |
| T7 | Independent cgroup | 58-62 | `systemd-run --collect --service-type=exec` |

### TKGL gaps

| # | Priority | Optimization | Detail |
|---|---|---|---|
| T-R1 | HIGH | CPU governor → performance | Currently only GPU governor is set. Add CPU governor to TKGL module before launch. |
| T-R2 | HIGH | THP off | Add to TKGL before systemd-run. |
| T-R3 | LOW | debugfs mount for driver debugging | `mount -t debugfs none /sys/kernel/debug` — exposes clock tree, DMA, GPIO, GPU stats. Useful for driver-level debugging. Does NOT expose ftrace (CONFIG_FTRACE not set). |

---

## 4. DEVICE SERVICES

| # | Service | File | Purpose |
|---|---|---|---|
| S1 | powerbutton-monitor | `scripts/device/powerbutton-monitor` | Clean shutdown on KEY_POWER (debounced, stops MIXXX → poweroff) |
| S2 | fix-mdns | `scripts/device/fix-mdns.sh` | Advertise `primego.local` instead of `buildroot.local` |
| S3 | usb-gadget-eth | `scripts/device/usb-gadget-eth.sh` | USB Ethernet at 192.168.42.1 |
| S4 | 99-wifi-power-save.rules | udev rule | Disables WiFi power save on wlan add (unreliable, TKGL does it at boot) |
| S5 | 99-usb-automount.rules | udev rule | systemd-mount USB drives |

---

## 5. ALSA AUDIO CHAIN

| Parameter | Current | Notes |
|---|---|---|
| Device | `hw:JP11,0` | Direct hardware (no plughw conversion overhead) |
| Format | S32_LE, 4ch, 44100Hz | Native XMOS/AKM format |
| Period size | 1024 (23.2ms) | Conservative for PREEMPT_RT |
| Buffer size | 2048 (46.4ms) | 2 periods deep |
| PA_ALSA_PLUGHW | disabled | Direct hw: avoids sw conversion |

---

## 6. KERNEL LIMITATIONS (unfixable without rebuild)

| Issue | Effect | Fix |
|---|---|---|
| `CONFIG_NO_HZ_FULL` not set | 1ms timer tick on ALL cores (0.1-0.2% CPU steal on audio cores) | Rebuild kernel with `CONFIG_NO_HZ_FULL=y` + `nohz_full=2-3` cmdline |
| `CONFIG_HZ=1000` | 1kHz scheduler tick | Reduce to 100Hz or use `nohz_full` |
| No `rcu_nocbs` | RCU callbacks land on audio cores | Rebuild with `CONFIG_RCU_NOCB_CPU=y` + `rcu_nocbs=2-3` cmdline |
| `isolcpus=1-3` | Wastes CPU 1 isolation (incomplete without nohz_full) | Change to `isolcpus=2-3` or add `nohz_full` companion |
| `threadirqs` | Unknown if in cmdline | Forces IRQ handlers into threaded context (usually default in PREEMPT_RT) |

---

## 7. MEASUREMENT TOOLKIT

No profiling tools exist on device. Built from `/proc`/`/sys` primitives:

| Tool | File | Measures |
|---|---|---|
| `profiler.sh` | `scripts/device/profiler.sh` | Modular sampler: CPU deltas, IRQ rates, sched stats, thread latency, xruns |
| `cpu-latency.sh` | `scripts/device/cpu-latency.sh` | Worst-case scheduling latency via /proc/stat busy-loop calibration |
| `xrun-monitor.sh` | `scripts/device/xrun-monitor.sh` | Audio dropout counting via /proc/asound polling |
| `bench-harness.sh` | `scripts/device/bench-harness.sh` | Before/after diff: apply optimization, measure, compare |

### /proc interfaces leveraged

- `/proc/interrupts` — IRQ counts per CPU
- `/proc/stat` — CPU time breakdown (user, sys, irq, softirq, steal, idle)
- `/proc/schedstat` — Scheduler run_delay, cpu_time, pcount per CPU (⚠ needs CONFIG_SCHEDSTATS, not set in buildroot)
- `/proc/sched_debug` — Full scheduler state dump (⚠ needs CONFIG_SCHED_DEBUG, not set in buildroot)
- `/proc/$PID/status` — voluntary/involuntary context switches
- `/proc/$PID/sched` — Scheduler policy, prio, nr_migrations, exec_start (**always available**, no CONFIG_ dependency)
- `/proc/$PID/stat` — utime, stime, num_threads, rt_priority
- `/proc/asound/card*/pcm*p/sub*/status` — ALSA xrun counters (always available)
- `/proc/pressure/cpu,io,memory` — PSI stall info (⚠ needs CONFIG_PSI, unknown status)
- `/sys/kernel/debug/tracing/` — ftrace (⚠ needs CONFIG_FTRACE, **not set** — see §9)
- `/sys/kernel/debug/` — other debug nodes: clk/, dmaengine/, gpio, driver stats (mountable, CONFIG_DEBUG_FS=y)

---

## 8. PRIORITY ORDER FOR IMPLEMENTATION

1. **Build measurement tools first** — can't optimize what you can't measure
2. **CPU governor → performance** — likely single biggest latency win
3. **THP off** — eliminates known RT stall source
4. **Timer migration off** — cache affinity on isolated cores
5. **Audio IRQ 45 → CPU 2** — co-locate with audio threads
6. **VM writeback tuning** — prevents SD card writeback stalls
7. **Remaining items** in order of priority above

Each optimization must be measured before and after using the profiler harness.

---

## 9. ENABLING FTRACE — What's Missing

The stock kernel config (`buildroot-customizations/board/inmusic/common/linux.config`)
has `CONFIG_DEBUG_FS=y` (debugfs is mountable) but **`CONFIG_FTRACE` is not set**.

### Current state

| Config option | Status | Effect |
|---|---|---|
| `CONFIG_DEBUG_FS` | **y** | `mount -t debugfs none /sys/kernel/debug` works |
| `CONFIG_DEBUG_FS_ALLOW_ALL` | **y** | No mount restrictions |
| `CONFIG_FTRACE` | **not set** | `/sys/kernel/debug/tracing/` directory is empty |
| `CONFIG_FUNCTION_TRACER` | **not set** | No `function_graph` tracer |
| `CONFIG_DYNAMIC_FTRACE` | **not set** | No tracepoint or kprobe infrastructure |
| `CONFIG_SCHED_DEBUG` | **not set** | No `/proc/sched_debug` |
| `CONFIG_SCHEDSTATS` | **not set** | No `/proc/schedstat` |

### What ftrace would give us (if enabled)

| Tracer | What it measures | Relevance to audio |
|---|---|---|
| `function_graph` | Call graph with per-function latency | Identify which kernel functions cause >100µs stalls |
| `hwlat` | Hardware latency detector (SMI/BIOS stalls) | Detect firmware interrupts stealing CPU from audio |
| `irqsoff` | Max time spent with IRQs disabled | Find IRQ handlers that block audio DMA completion |
| `preemptoff` | Max time preemption was disabled | Verify PREEMPT_RT isn't blocking scheduler |
| `wakeup` | Max wakeup latency | Measure how fast audio threads get CPU after signal |
| `wakeup_rt` | Max RT task wakeup latency | Specific to SCHED_FIFO threads (our audio engine) |
| `sched_switch` tracepoint | Per-sched-event timeline | Correlate xruns with scheduler decisions |

### What needs to change in linux.config

```diff
-# CONFIG_FTRACE is not set
+CONFIG_FTRACE=y
+CONFIG_FUNCTION_TRACER=y
+CONFIG_FUNCTION_GRAPH_TRACER=y
+CONFIG_DYNAMIC_FTRACE=y
+CONFIG_IRQSOFF_TRACER=y
+CONFIG_PREEMPT_TRACER=y
+CONFIG_SCHED_TRACER=y
+CONFIG_HWLAT_TRACER=y
+CONFIG_STACK_TRACER=y
+CONFIG_TRACER_SNAPSHOT=y

-# CONFIG_SCHED_DEBUG is not set
+CONFIG_SCHED_DEBUG=y

-# CONFIG_SCHEDSTATS is not set
+CONFIG_SCHEDSTATS=y
```

### Runtime cost

ftrace has near-zero overhead when **not** actively tracing (it's all `NOP`-patched dynamic
tracepoints and static key branches). Overhead kicks in only when a tracer is enabled via
the `tracing_on` knob. For production use, keep tracing off and enable it only during
debugging sessions.

### Alternative: eBPF

If the kernel has `CONFIG_BPF=y` and `CONFIG_BPF_SYSCALL=y`, eBPF-based tools (bpftrace)
could provide similar tracing without ftrace. Check the device kernel config for BPF support.
eBPF is lighter-weight than ftrace and more flexible for targeted probing, but requires
cross-compiling bpftrace or using `bpftool` on-device.

### Rebuild procedure

The workflow described in research is correct in structure, but the version numbers
need correction for this project:

| Item | Research says | **Actual** |
|---|---|---|
| Buildroot version | 2023.02.x LTS | **2021.02.10** |
| Base kernel | 5.15 | **6.1.78** (buildroot) / **6.1.111** (device stock) |
| RT patch | 5.15.86-rt56 | **patches-6.1.77-rt24** |
| Kernel source | Request from inMusic | GPL compliance: https://inmusicbrands.com/gpl/ |
| Kconfig interface | `make linux-menuconfig` | Correct — standard Buildroot kernel config target |
| `/proc/schedstat` | Listed as verification target | Requires `CONFIG_SCHEDSTATS=y` (not `CONFIG_SCHED_DEBUG`) |
| `/proc/sched_debug` | Not mentioned | Requires `CONFIG_SCHED_DEBUG=y` |
| `/proc/<PID>/sched` | Not mentioned | Always available — no config dependency |

**Correct rebuild sequence for this project:**

1. Obtain inMusic's 6.1.111 GPL kernel source
2. Apply PREEMPT_RT patchset matching the kernel version
3. Copy device kernel config as starting `.config` (or start from `linux.config`)
4. `make linux-menuconfig` → enable ftrace + sched debug + nohz_full + rcu_nocb
5. `./compile-buildroot.sh` → produces new `zImage` + `.dtb`
6. Flash via Go updater (`./go/cmd/updater/`)
7. Verify: `mount -t debugfs none /sys/kernel/debug && ls /sys/kernel/debug/tracing/`

### ⚠ Device kernel caveat

The buildroot config targets 6.1.78, but the device boots stock 6.1.111-inmusic-2024-09-19-rt41.
The device kernel's `.config` is unknown. Verify on-device with:
```bash
ssh root@192.168.42.1 'zcat /proc/config.gz 2>/dev/null | grep -E "FTRACE|SCHED_DEBUG|SCHEDSTATS|BPF" || echo "config.gz not available — kernel built without /proc/config.gz"'
```

---

## 10. WHAT'S MISSING FOR A KERNEL REBUILD FROM DEVICE CONFIG

Six blockers prevent us from taking the device's actual kernel config and rebuilding
with ftrace + sched debug + nohz_full enabled:

### Blocker 1: Kernel version mismatch

| | Buildroot | Device |
|---|---|---|
| Kernel | 6.1.78 | **6.1.111** |
| RT patch | patches-6.1.77-rt24 | **unknown** |
| Source | vanilla linux-stable | **inMusic modified** |

Our entire build chain (`clone-buildroot.sh`, `compile-buildroot.sh`) is hardcoded to
6.1.78. Bumping to 6.1.111 means changing:
- `BR2_DEFAULT_KERNEL_VERSION` in `jp11_defconfig` (6.1.78 → 6.1.111)
- `BR2_LINUX_KERNEL_PATCH` URL to a matching RT patchset for 6.1.111
- `linux.config` header version (currently says `Linux/arm 6.1.78`)

### Blocker 2: inMusic kernel source unknown

The stock 6.1.111-inmusic-2024-09-19-rt41 kernel contains unknown modifications:
- Rockchip RK3288 BSP patches (device tree, DRM, clock, PMIC)
- Audio driver stack (XMOS USB audio, AK4621 CODEC, AK4413 DAC)
- Mali GPU integration (r1p0 DDK bindings, `/sbin/az01-libmali-setup`)
- Denon-specific hardware support (ILI2117 touch, SD mux, power button)
- Possibly custom kernel APIs used by Engine OS

Without the exact GPL source, we're guessing. Even if we extract the config and
build vanilla 6.1.111 + RT, it almost certainly won't boot — the device tree and
driver patches are essential.

#### Where to get it

**The official GPL page is dead.** `https://inmusicbrands.com/gpl/` 301-redirects
to `www.inmusicbrands.com/gpl/` which returns 404. No Wayback Machine archive
exists. None of the brand sites (denondj.com, akaipro.com, numark.com) have
equivalent pages. The page appears to have been removed entirely.

**Practical options (best → worst):**

1. **Extract config from device kernel** — if we can get the zImage off the device,
   `extract-ikconfig.sh` (already in repo) can dump the `.config`. This gives us
   the config but NOT the patches.

2. **Contact inMusic support** — file a ticket at `support.denondj.com` referencing
   the GPL and requesting kernel source for Prime Go firmware 4.3.4. They are
   legally required to provide it. Include the specific kernel version string
   (`6.1.111-inmusic-2024-09-19-rt41`) and the product (Denon DJ Prime Go).

3. **Extract from firmware update image** — the `.img.dtb` files contain a zImage.
   Our `extract-ikconfig.sh` already extracts config from zImage. Same limitation:
   config only, no patches.

4. **Legal demand** — inMusic Brands, Cumberland, RI, USA. GPL Section 3 requires
   them to provide the "complete corresponding source code" for any GPL-licensed
   components they distribute (which includes the Linux kernel). A formal written
   request citing GPLv2 §3(b) may be necessary if support ignores the request.

**What the MPC hacking community does:** TheKikGen, henning/Hakai-MPC, and others
have been working with inMusic's Rockchip RK3288 platform (MPC Live/X/Force/One)
for years **without** kernel source access. They rely on:
- Reverse-engineering device trees from `/sys/firmware/devicetree/base/`
- Extracting config from boot images with `extract-ikconfig`
- Using stock inMusic kernels as-is, patching userspace instead
- Mount-binding over device tree properties for hardware spoofing

**Our buildroot doesn't use inMusic patches either.** The `jp11_defconfig` builds
vanilla 6.1.78 + RT patch only — no Rockchip BSP, no audio drivers, no Mali.
This works because the buildroot kernel *never boots on the device*. It's only
used for kernel headers during cross-compilation. The device boots inMusic's
stock 6.1.111 which has all hardware patches pre-applied at the factory.

This is viable: we don't *need* to rebuild the kernel to enable ftrace if we can
extract the config and see what's already compiled in (or if `debugfs` mount is
enough — `CONFIG_DEBUG_FS=y` is already set in our buildroot config).

#### Where to get the patches (if we must rebuild)

The patches are the diff between vanilla 6.1.111 and inMusic's 6.1.111-inmusic.
They contain Rockchip BSP, audio drivers (XMOS/AKM), Mali integration, and Denon
hardware support. Without them, a rebuilt kernel won't boot.

**Only path: inMusic's GPL source tarball.** There is no other source:
- No public repo (GitHub, GitLab, etc.)
- No leaked patchset in the MPC hacking community
- No device tree source files on the device (only compiled `.dtb`)
- `extract-ikconfig` gives config, NOT patches

A successful GPL request should yield a tarball containing the *exact* kernel
source tree inMusic used to build `6.1.111-inmusic-2024-09-19-rt41`. From that:
1. `diff -ruN vanilla-6.1.111/ inmusic-6.1.111/ > inmusic-patches.patch`
2. Apply those patches to vanilla 6.1.111
3. Apply matching RT patchset for 6.1.111
4. Merge our `linux.config` changes (FTRACE, SCHED_DEBUG, etc.) via `menuconfig`
5. Build → pack → flash

**What's legally required:** Under GPLv2 §3, inMusic must provide "the complete
corresponding machine-readable source code" for any GPL-licensed work they
distribute in binary form. The Linux kernel is GPLv2. The source must include
*all* modifications — device trees, drivers, and build scripts needed to
reproduce the binary. A tarball on a CD/DVD or download link satisfies this.
They cannot charge more than the cost of physically performing the source
distribution.

### Blocker 3: RT patch availability

PREEMPT_RT patches are maintained per kernel minor version. For 6.1:
- `patches-6.1.77-rt24.tar.xz` — we use this for 6.1.78
- Patches exist up to ~6.1.90-rt26+
- 6.1.111 may not have a published RT patchset

Options if no matching RT patch exists:
1. Find the closest patchset and fix rebase conflicts
2. Use a kernel version close to the device's that HAS an RT patch (e.g. 6.1.90-rt26)
3. Request inMusic's source which includes their RT patch

### Blocker 4: Config extraction

Our buildroot config has `CONFIG_IKCONFIG_PROC=y` — but the **device** runs inMusic's
kernel, not ours. If inMusic disabled IKCONFIG, `/proc/config.gz` won't exist.

Fallbacks:
1. `extract-ikconfig.sh` — extracts config from a zImage file (requires firmware unpack)
2. Dump running config via `cat /proc/sched_debug` header (if enabled)
3. Guess from `/proc` filesystem presence and kernel cmdline

### Blocker 5: Toolchain compatibility

We use `arm-buildroot-linux-gnueabihf-gcc 12.3.0` (from Buildroot 2021.02.10's GCC 12.x).
This should be fine for 6.1.111 — same architecture, similar compiler requirements.
Low risk.

### Blocker 6: Boot chain integration

Even if we rebuild and flash a kernel with ftrace enabled, the boot chain must still work:
- U-Boot must load our new zImage
- Device tree (`.dtb`) must match — we'd need to rebuild it too
- Our TKGL bootstrap / MIXXX launcher / Mali setup must still function
- A non-booting kernel on a sealed device means USB flashing back to stock

### Dependency graph

```
inMusic GPL source
  ├─ kernel 6.1.111 patches
  ├─ Rockchip BSP patches
  ├─ Audio driver patches
  └─ Denon hardware patches
       │
       ▼
  Full modified kernel source
       │
       ▼
  RT patchset for matching version ──► Apply PREEMPT_RT
       │
       ▼
  Device config (from /proc/config.gz or zImage)
       │
       ▼
  Enable ftrace + sched debug + nohz_full + rcu_nocb
       │
       ▼
  Rebuild zImage + DTB via buildroot
       │
       ▼
  Pack into .img.dtb firmware
       │
       ▼
  Flash via USB (Go updater)
       │
       ▼
  Verify: /sys/kernel/debug/tracing/ exists
```

**Bottom line**: The critical blocker is **inMusic's modified kernel source**. Everything
else (RT patch, config extraction, toolchain) is solvable once the source is available.

### First check: what's already on the device?

Before chasing a kernel rebuild, verify what the device kernel actually exposes.
This tells us whether `CONFIG_FTRACE` might already be enabled in the stock kernel
(different from our buildroot config):

```bash
# 1. Can we get the running config?
ssh root@192.168.42.1 'zcat /proc/config.gz 2>/dev/null | head -20 || echo "IKCONFIG_PROC not enabled"'

# 2. Does debugfs already have tracing?
ssh root@192.168.42.1 'mount -t debugfs none /sys/kernel/debug 2>/dev/null; ls /sys/kernel/debug/tracing/ 2>/dev/null || echo "ftrace not available"'

# 3. What scheduler interfaces exist?
ssh root@192.168.42.1 'ls /proc/schedstat /proc/sched_debug /proc/pressure 2>&1'

# 4. What's the kernel command line? (may reveal nohz_full, rcu_nocbs, etc.)
ssh root@192.168.42.1 'cat /proc/cmdline'
```

If `IKCONFIG_PROC=y` on the device kernel, we can get the exact config and check
whether `CONFIG_FTRACE`, `CONFIG_NO_HZ_FULL`, etc. are already set — without any
rebuild at all.
