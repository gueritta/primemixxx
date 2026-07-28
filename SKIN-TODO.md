# Denon Prime 4 — Global TODO & Audit

Last updated: 2026-07-28

---

## Active Tasks

- [ ] **USB gadget cold boot test** — verify `WantedBy=multi-user.target` works after reboot
- [ ] **Cold boot verification** — confirm all 10 I/O & VM optimizations persist across reboot
- [ ] **Process trimming** — audit and disable unnecessary systemd units (149 processes is high)
- [ ] **Keylock MIDI mapping** — debug keylock behavior (possibly MIDI mapping bug)

## Deferred (requires kernel/DTS rebuild)

- [ ] `CONFIG_NO_HZ_FULL` — suppress arch_timer ticks on audio cores (1000×/sec preemption overhead)
- [ ] SD card at SDR25/SDR50 — currently locked at 25 MHz legacy mode
- [ ] CPU OPP step above 1.608 GHz — hardware-capped by InMusic, not thermal
- [ ] cgroups cpuset — prevent late-spawning threads from inheriting audio-core affinity

## Recently Completed

- [x] **10 I/O & VM optimizations** — scheduler none, read-ahead 512KB, dirty tuning, noatime, systemd limits
- [x] **Per-thread CPU pinning** — EngineWorkerSch/EngineSideChain on 2-3, all others banished to 0-1
- [x] **USB gadget boot fix** — `WantedBy=multi-user.target` (no `Before=`)
- [x] **TKGL soundconfig fix** — was latency=3 with wrong device, now latency=5 with hw:1,0
- [x] **5.8ms ALSA buffer stability** — verified stable at 256/512 period/buffer

## 🎨 SKIN (RoundCorners)

### ✅ DONE

- [x] Neon green + real black theme (#39ff14/#000000/#ffffff)
- [x] Bigger fonts (11→14, 13→16, 14→18, 16→20px)
- [x] Bigger margins/padding (~3× from original)
- [x] Touch scaling fix: MinimumSize 1024→800 (matches Qt logical width 1280)
- [x] Menubar SizeAwareStack breakpoints: 0-600/601-800/801+
- [x] Deck1 = Deck2 = same neon green (#77ff88/#5cff2e/#44dd55)
- [x] EffectUnit2 colors unified with Deck1
- [x] Sampler2 colors unified with Deck1
- [x] MASTER → M (all 3 XML locations)
- [x] Vinyl/microphone units hidden, air/aux disabled
- [x] Brand compacted (150f→90f, spacers 10→2px)
- [x] MIXXX version label removed, menubar buttons 23f→32f
- [x] **Deck XML flattening + boilerplate purge** (-1157 lines)
- [x] **44px touch target bumps** (search, tree items, headers, tables)
- [x] **100px phantom reserves dropped** from effect/mic/sampler units
- [x] **VIEW button split**: normal=maximize_library, shift+VIEW=show_menubar
- [x] **style.qss split into 5 modules** (_base, _library, _controls, _buttons, _deck2)
- [x] **Touch design system documented** (4px grid, 44px min, font/radius/spacing scale)

### 🔧 PENDING

- [ ] **Remove dead space at right** — brand section + spacers = ~94f
- [ ] EffectUnit1 hover color audit (#44dd55 match)
- [ ] **Touch verification on device** — test effect/sampler touch targets with 800px templates
- [ ] **Standardize XML button widths** to design system (15me/20me/25me → consistent scale)
- [ ] Drop or simplify sm/md breakpoints? Device always runs lg(801+) at 1280px

### 📐 Resolution Architecture

```
Physical display:  1280×800 landscape
GPU framebuffer:   800×1280 portrait (triple-buffered → 800×3840)
Qt logical screen: 1280×800 landscape (EGLFS_ROTATION=90 rotates the render)
Display HW:        rotates 800×1280 framebuffer → 1280×800 visible landscape
Touch input:       rotate=90 (ILI2117 physical landscape → Qt 1280×800 coords)
Skin SizeAwareStack: lg template active at 1280px width (≥801px breakpoint)
```

---

## 🎛️ HARDWARE MAPPING (Denon Prime Go)

### ✅ DONE

- [x] Mapping path fix: mixxx.cfg → `controllers/Denon-Prime-Go.midi.xml` (was `settings/controllers/`)
- [x] 146 MIDI mappings loaded, controller active
- [x] Deck1 LEDs = green, Deck2 LEDs = blue (deckColors in script)
- [x] SysEx RGB LED output (sendRGB with 7-bit encoding)
- [x] Cue/Play/Sync transport LEDs (SysEx)
- [x] Hotcue pad LEDs with color feedback
- [x] Saved Loop pad LEDs with distinct colors
- [x] Jog wheel touch detection + vinyl/scratch toggle
- [x] Shift layer (Channel 6) for secondary functions
- [x] Pitch fader (14-bit, dual-channel bindings)
- [x] LED dim/bright for on/off states
- [x] Vinyl toggle LED feedback (bright red = on, dim = off)
- [x] PFL/headphone cue button with LED
- [x] Pad mode switching (hotcue → savedLoop → roll → sampler → slicer)
- [x] Browse encoder with shift acceleration (×1 vs ×20)

### 🔧 PENDING

- [ ] **Slicer mode not implemented** (TODO at line 1791)
- [ ] **QuickEffect knob not implemented** (TODO at line 784)
- [ ] **QuickEffect preset selection for 2 decks** (TODO at line 619)
- [ ] **Denon SysEx ID verification** (line 85 — `[0x00, 0x02, 0x0b]` copied from Prime 4, may need different ID for Prime Go)
- [ ] **MIDI mapping count in XML** — `grep -c "midi="` returns 0 (attribute format may differ from expected)
- [ ] **`script.channelRegEx` NaN workaround** (line 1264 — may indicate MIXXX QJSEngine bug)
- [ ] **No debug log on device** — `print()` silent on Buildroot Qt5 EGLFS, need `console.warn()` or `engine.log()`

### ⚙️ Controller Architecture

```
PRIME_GO_Control_Surface (JavaScript)
  ├── Channel 1-4: Deck pads/controls per deck
  ├── Channel 5: Transport, mixer, browse, FX
  ├── Channel 6: Shift layer (secondary functions)
  ├── SysEx: RGB LED output (7-bit split values)
  └── Pad modes: hotcue | savedLoop | roll | sampler | slicer(nyi)
```

---

## 🚀 DEPLOYMENT

### ✅ DONE

- [x] `scripts/dev-deploy-to-device.sh` — full deploy + stale settings cleanup + config path fix
- [x] `scripts/dev-quick-fix-deploy.sh` — fast partial deploy for iteration
- [x] `scripts/dev-fix-device-libs.sh` — removes system-critical libs from bundle

### 🔧 PENDING

- [ ] Deploy scripts don't sync skin theme files (`style.qss`, XML changes) — user manually SCPs these
- [ ] No rollback mechanism for bad deploys

---

## ⚠️ CRITICAL PITFALLS

1. **Two MIXXX binaries**: Only `lib/bin/mixxx` (~10MB) works. `mixxx.real` (~17MB) crashes with EGL errors.
2. **System libs must NOT be in bundle**: libc/libm/libpthread/libdl/librt/libstdc++/libgcc/ld-linux/libatomic — must come from device `/lib`.
3. **Mali DDK mismatch**: Device has r1p0, Buildroot bundles r0p0. Fix: symlink to `/usr/lib/libmali.so.14.0`.
4. **Qt version**: SD card bundles Qt 5.15.8 with custom `libqeglfs-mali-integration.so`. Device Qt 5.15.2 + `eglfs_emu` = black screen.
5. **NO `QT_QPA_EGLFS_KMS_ATOMIC=1`** — breaks Mali integration.
6. **Touch: `rotate=90`** — ILI2117 reports in physical landscape orientation; Qt evdev plugin rotates 90° to match Qt's 1280×800 logical screen.
7. **`mixxx-app.service` must NOT be masked** — TKGL uses `systemd-run --unit=mixxx-app`.
8. **`--resourcePath` is `$BUNDLE` (root)**, NOT `$BUNDLE/bin`.
9. **`print()` is silent on device** — use `console.warn()` or `engine.log()` for debug output.
10. **SizeAwareStack breakpoints must match 800px world** — any breakpoint ≥800 triggers wrong template at native resolution.
11. **Startup "60% stall" is Mali GPU paint, not code**: MIXXX startup takes ~10s total. The progress bar stalls at ~60% for ~5 seconds with zero log output — this is the Mali-T76x GPU compositing/painting all widgets to the EGLFS framebuffer. It's NOT XML parsing, NOT JS, NOT controllers, NOT DB queries. Skin XML is ~9300 lines and the legacy skin parser + QPainter rendering on ARM Cortex-A17 is the bottleneck. Verified 2026-07-22 by removing controller mapping entirely (same stall) and replacing PlayButton widgets (zero warnings, same timing). Only a QML skin rewrite or MIXXX source-level rendering optimization would speed this up.
