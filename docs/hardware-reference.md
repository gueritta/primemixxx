# Denon Prime Go — Hardware MIDI Reference

> Source: Engine OS QML files (`JP11_Controller_Device.qml`, `JP11_Controller_Assignments.qml`)
> Verified against: `mixxx-bundle/controllers/Denon-Prime-Go-scripts.js`

---

## LED Protocols

### SysEx RGB (`LedType.RGB`)
```
F0 00 02 0B 7F 0C 03 00 05 <ch> <idx> <r> <g> <b> F7
```
- Gamma: 3.5 (Pads: `padGamma` also 3.5)
- Color calculation: `Math.floor(Math.pow(c, gamma) * 127)` where c = normalized 0-1
- JS equivalent: `sendSysexRGB(channel, index, r_7bit, g_7bit, b_7bit)`
- Used by: PerformanceModes, ActionPads (pads 15-22)

### Simple Note On/Off (`LedType.Simple`)
```
Note On:  9<ch> <idx> <vel>   (vel > 0 = ON with color=vel)
Note Off: 8<ch> <idx> 00       (fully OFF)
```
- Color = velocity byte (7-bit hardware palette)
- vel=0 → Note Off → LED fully off
- vel=1-127 → Note On → LED lit with color from device palette
- Used by: Back, Forward, BrowseEncoder, View, Shift, Load, AutoLoop, PFL, AND confirmed for Cue/Play (Simple works!)

### Device Init SysEx
```
F0 00 02 0B 7F 0C 60 00 04 04 01 01 04 F7  (initialization)
F0 00 02 0B 7F 0C 04 00 00 F7            (query absolute controls)
F0 00 02 0B 7F 0C 42 00 00 F7            (request power-on button state)
F0 7E 00 06 01 F7                          (Midi Device Inquiry)
```

---

## Channel Map

| Channel | Hex Note On | Usage |
|---------|-------------|-------|
| 0 | 0x90 | Mixer Channel 1 (Left) |
| 1 | 0x91 | Mixer Channel 2 (Right) |
| 2 | 0x92 | Deck 1 (Left) |
| 3 | 0x93 | Deck 2 (Right) |
| 4 | 0x94 | FX Unit |
| 15 | 0x9F | Global |

---

## Deck Controls (per deck, channel 2=Left, 3=Right)

| Control | Note | CC | LED Type | Input | Output (MIXXX) |
|---------|------|----|----------|-------|----------------|
| **Load** | 0x01 (L) / 0x02 (R) | — | Simple | `LoadSelectedTrack` / shift=`eject` | `send()` 0x00=off, deckColor=on |
| **Sync** | 0x08 | — | ? (Engine default) | `sync_enabled` toggle | via `SyncButton` proto |
| **Cue** | 0x09 | — | Simple ✅ | `cue_default` / shift=`set_cue_point` | `send(0x1A)`=on, `send(0x00)`=off |
| **Play** | 0x0A | — | Simple ✅ | `play` toggle | `send(0x0C)`=on, `send(0x00)`=off |
| **HotCue Mode** | 0x0B | — | RGB | Pad mode: CUES | SysEx RGB |
| **Loop Mode** | 0x0C | — | RGB | Pad mode: LOOPS | SysEx RGB |
| **Roll Mode** | 0x0D | — | RGB | Pad mode: ROLL | SysEx RGB |
| **Slicer Mode** | 0x0E | — | Not in QML | Pad mode: SLICER | SysEx RGB |
| **Pads 1-8** | 0x0F–0x16 | — | **RGB** | `hotcue_N_activate` / shift=`hotcue_N_clear` | SysEx RGB via `sendRGB()` |
| **Pitch Bend −** | 0x1D | — | ? | `rate_temp_down_small` | — |
| **Pitch Bend +** | 0x1E | — | ? | `rate_temp_up_small` | — |
| **Jog Touch** | 0x21 | — | ? | `engine.scratchEnable` | — |
| **Vinyl** | 0x23 | — | Simple (trial) | Toggle `vinylMode` (edge-detect) | `send(0x40)`=on, `send(0x00)`=off |
| **AutoLoop push** | 0x27 | — | Simple | `beatloop_activate` / shift=`beatlooproll` | via Button proto |
| **AutoLoop turn** | — | 0x20 | Simple | `beatloop_size` / shift=`beatjump_size` | — |
| **Pitch fader MSB** | — | 0x1F | — | `rate` (14-bit with LSB) | — |
| **Pitch fader LSB** | — | 0x4B | — | `rate` LSB | — |
| **Jog wheel MSB** | — | 0x37 | — | `jogWheel.inputWheelMSB` | — |
| **Jog wheel LSB** | — | 0x4D | — | `jogWheel.inputWheelLSB` | — |

> **Note**: Deck controls are on channel `2 + offset` where offset=0 for Left, 1 for Right.
> Notes use `0x90 + midiChannel`, pads use `0x92 + offset`.

---

## Mixer Channel Controls (per channel, ch0=Left, ch1=Right)

| Control | Note | CC | LED Type | MIXXX Input |
|---------|------|----|----------|-------------|
| **Trim** | — | 0x03 | — | `pregain` |
| **Treble** | — | 0x04 | — | `[EqualizerRack1_ChannelN_Effect1], parameter3` |
| **Mid** | — | 0x06 | — | `parameter2` |
| **Bass** | — | 0x08 | — | `parameter1` |
| **Filter/Sweep** | — | 0x0A | — | `[QuickEffectRack1_ChannelN], super1` |
| **Sweep FX knob** | — | 0x0B | — | `[QuickEffectRack1_ChannelN], super1` |
| **PFL** | 0x0D | — | **Simple** | `pfl` toggle | `send(deckColor)`=on, `send(0x00)`=off |
| **Filter FX Select** | 0x0E | — | ? | Filter effect on | via `sweepFilter` |
| **Wash FX Select** | 0x0F | — | ? | Wash effect on | via `sweepWash` |
| **Fader** | — | 0x0E | — | `volume` |
| **VU Meter** | — | 0x20 (L) / 0x21 (R) | CC out | `VuMeter` engine output |

---

## Global Controls (Channel 15 = 0x9F)

| Control | Note | CC | LED Type | MIXXX Input |
|---------|------|----|----------|-------------|
| **Back** | 0x03 | — | **Simple** | `[Library], MoveFocusBackward` |
| **Forward** | 0x04 | — | **Simple** | `[Library], MoveFocusForward` (shift=Quantize) |
| **Browse Encoder push** | 0x06 | — | **Simple** | `[Library], GoToItem` |
| **Browse Encoder turn** | — | 0x05 | **Simple** | `PrimeGo.browseEncoder` (shift=15-step scroll) |
| **View** | 0x07 | — | **Simple** | `[Master], maximize_library` toggle |
| **Shift** | 0x08 | — | **Simple** | `PrimeGo.shiftButton` |
| **Filter FX on** | 0x0C | — | ? | `[QuickEffectRack1_Channel1], enabled` |
| **Filter FX 2** | 0x0D | — | ? | Filter enable ch2 |
| **Wash FX on** | 0x0E | — | ? | Wash enable ch1 |
| **Wash FX 2** | 0x0F | — | ? | Wash enable ch2 |
| **Sweep knob** | 0x0B | — | ? | `[QuickEffectRack1_Channel1], super1` |
| **Eject/Source** | 0x14 | — | hasLed | Eject (shift=Source select) |
| **Cue Mix** | — | 0x0C | — | `[Master], headMix` |
| **Cue Gain** | — | 0x0D | — | `[Master], headVolume` |
| **Crossfader** | — | 0x0E | — | `[Master], crossfader` |
| **Mic 1** | 0x24 | — | — | Mic on/off + talkover |
| **Mic 2** | 0x25 | — | — | Mic on/off |

---

## FX Controls (Channel 4 = 0x94)

| Control | Note | CC | LED Type |
|---------|------|----|----------|
| **FX Select push** | 0x07 | — | ? |
| **FX Select touch** | 0x09 | — | ? |
| **FX Select turn** | — | 0x21 | ? |
| **FX Time push** | 0x08 | — | ? |
| **FX Time turn** | — | 0x22 | ? |
| **FX Wet/Dry** | — | 0x04 | ? |
| **FX Activate** | 0x06 | — | Flash |
| **FX Assign 1** | 0x0B | — | ? |
| **FX Assign 2** | 0x0C | — | ? |

---

## Jog Wheel Details

- **Touch**: Note 0x21 (33) on deck channel — enables `engine.scratchEnable()`
- **MSB**: CC 0x37 (55) on deck channel — upper 7 bits of 14-bit position
- **LSB**: CC 0x4D (77) on deck channel — lower 7 bits
- **Gate**: `inputTouch` requires BOTH `isPress()` AND `vinylMode === true`
- **Vinyl mode default**: `_vinylMode: true`
- **Vinyl button**: Note 0x23 (35) — edge-detected toggle of `vinylMode`

---

## SysEx RGB Color Format (Detailed)

Per `JP11_Controller_Device.qml`:
```
F0 00 02 0B 7F 0C 03 00 05 <ch_hex> <idx_hex> <r_hex> <g_hex> <b_hex> F7
```
- Channel and index converted to hex with `d2h()`
- Gamma applied: `Math.floor(Math.pow(c, gamma) * 127)` per channel
- Pad indices 15-22 (0x0F-0x16) use `padGamma` (3.5)
- All other indices use `gamma` (3.5)

### MIXXX JS equivalent:
```javascript
const sendSysexRGB = function(channel, control, red, green, blue) {
    const msg = [0xf0, 0x00, 0x02, 0x0b, 0x7f, 0x0C, 0x03, 0x00, 0x05,
                 channel, control, red, green, blue, 0xf7];
    midi.sendSysexMsg(msg, msg.length);
};
```

---

## Simple LED Color Values (Known Working)

| Value | Color/Effect | Used For |
|-------|-------------|----------|
| 0x00 | Fully off | Cue off, Play off, PFL off |
| 0x09 | Yellow | Shift off (dim yellow) |
| 0x0C | Green | Play on |
| 0x1A | Orange/amber | Cue on |
| 0x40 | Red | Vinyl on |
| 1-8 | Deck colors | PFL on (colDeck[] values) |

Hardware color palette is device-specific. Values 1-127 map to different colors and brightness levels.

---

## Known States / Fixes

| Issue | Status | Solution |
|-------|--------|----------|
| PFL left always on | ✅ Fixed | `output()` sends 0x00 (Note Off) instead of dim green |
| Vinyl rapid toggle | ✅ Fixed | Edge detection: `_lastVinylState`, only 0→127 triggers |
| Cue LED | ✅ Fixed | Simple Note On (0x1A) works |
| Play LED | ✅ Fixed | Simple Note On (0x0C) works |
| `scratch2_enable` Channel0 error | ✅ Fixed | Removed `outKey` from vinyl button |
| Pad/hotcue LEDs | ❌ Broken | Only update on pad mode switch, not on track load |
| Jog touch error | ❌ Open | `vinylMode` might be false; needs debug |
| Load/Back/Fwd LEDs | ❌ Open | Still use SysEx or no output; need Simple |
---

## All Known SysEx Messages

### RGB LED Color (sendColor)
```
F0 00 02 0B 7F 0C 03 00 05 <ch> <idx> <r> <g> <b> F7
```
- Args: channel, index, red, green, blue (7-bit per channel)
- Gamma: 3.5 (padGamma also 3.5 for indices 15-23)
- Color calc: `Math.floor(Math.pow(c, gamma) * 127)`
- Used for: PerformanceModes (notes 0x0B-0x0D), ActionPads (notes 0x0F-0x16)

### Device Initialization
```
F0 00 02 0B 7F 0C 60 00 04 04 01 01 04 F7
```

### Query Absolute Controls
```
F0 00 02 0B 7F 0C 04 00 00 F7
```

### Request Power-On Button State
```
F0 00 02 0B 7F 0C 42 00 00 F7
```

### MIDI Device Inquiry
```
F0 7E 00 06 01 F7
```

### Serato Loopback (f_midi virtual device)
- All MIDI forwarded to `f_midi` virtual device
- Active Sense every 300ms

---

## Known Working Simple LED Color Values

| Value | Effect | Used For |
|-------|--------|----------|
| 0x00 | Fully off | Avoid — use dim instead |
| 0x01 | Very dim glow | Cue off, Play off, PFL off, Load empty |
| 0x02 | Subtle dim | Back, Forward (always lit) |
| 0x03 | Dim red | Vinyl mode active |
| 0x09 | Dim yellow | Shift active |
| 0x0C | Green | Play on, Load track loaded |
| 0x1A | Amber/Orange | Cue on |
| 0x20 | Bright green | Sync on |
| 0x40 | Red | Vinyl on (deprecated) |

Deck color palette (Simple):
- `colDeck = [1, 5]` (red, yellow per deck)
- `colDeckDark = [4, 6]` (dark green, dark yellow)
