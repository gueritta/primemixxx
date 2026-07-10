# Denon Prime Go (JP11) — Mixxx Controller Mapping

Adapted from the [Denon Prime 4 mapping](https://github.com/mixxxdj/mixxx/wiki/Denon-Prime-4) by Levi "Whanake" Williams (whanake-music) and RattyDAVE.

## Changes from Prime 4 Mapping

- **4 decks → 2 decks**: The Prime Go has 2 channel strips. All Deck 3/4 MIDI controls, mixer strips, and deck color entries have been removed.
- **`deckColors`**: Reduced from 4 colors (`["green", "blue", "red", "yellow"]`) to 2 (`["green", "blue"]`).
- **Mixer strips**: Only `mixerA` and `mixerB` are initialized (vs A–D on Prime 4).
- **Sweep FX filter**: Only targets Channel 1 and 2.
- **Namespace**: `PrimeGo` instead of `Prime4`.

## What Needs Hardware Verification

The Prime Go likely uses **different MIDI Note/CC numbers** than the Prime 4. The values in this mapping were copied directly from the Prime 4 and **MUST be verified against the actual JP11 device**.

### How to capture actual MIDI output

```bash
# List MIDI devices
amidi -l

# Capture raw MIDI (adjust device ID as needed)
amidi -d -p hw:1,0,0 | hexdump -C
```

### Key items to verify

| Control | Notes |
|---------|-------|
| Play/Cue buttons | Check status byte and note numbers |
| Jog wheels | 14-bit MSB/LSB MIDI CC numbers |
| Channel faders | CC numbers for volume |
| EQ knobs | CC numbers for high/mid/low |
| Deck load buttons | Status byte and note numbers |
| Performance pads | Pad grid MIDI addresses |
| FX knobs & buttons | FX unit encoder addresses |

### SysEx Identity

The `denonId` prefix `[0x00, 0x02, 0x0b]` in `Denon-Prime-Go-scripts.js` and `denonHeader` in the jog wheel script are copied from the Prime 4. The Prime Go may use a different SysEx identity. Use `amidi -d` to capture SysEx traffic and confirm.

## Installation on Device

Copy all files into Mixxx's controller configuration directory:

```bash
mkdir -p ~/.mixxx/controllers/Denon-Prime-Go/
cp prime-go/*.js prime-go/*.midi.xml ~/.mixxx/controllers/Denon-Prime-Go/
```

Restart Mixxx and the mapping should appear in **Preferences → Controllers**.

## Files

- `Denon-Prime-Go.midi.xml` — Main MIDI mapping (controls, group bindings)
- `Denon-Prime-Go-scripts.js` — JavaScript controller logic
- `Denon-Prime-Go-jog-wheel-scripts.js` — Jog wheel display SysEx handler
- `Denon-Prime-Go-Jog-Wheels.midi.xml` — Jog wheel display controller preset
- `common-controller-scripts.js` — Shared controller utilities (unchanged)
- `common-hid-packet-parser.js` — HID packet parser (unchanged)
- `common-hid-devices.js` — Generic HID device templates (unchanged)
- `common-bulk-midi.js` — Bulk MIDI helper (unchanged)
