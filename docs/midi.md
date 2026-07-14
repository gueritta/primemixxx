# Prime Go MIDI Mapping Reference

Authoritative source: `/usr/Engine/AssignmentFiles/PresetAssignmentFiles/JP11/JP11_Controller_Assignments.qml`
(Engine OS native mapping, QML format, 0-indexed MIDI channels)

## Channel Layout

| MIDI Channel | QML Index | Purpose |
|:---:|:---:|:---|
| 1 | 0 | Mixer Channel 1 (PFL, EQ, fader, sweep FX) |
| 2 | 1 | Mixer Channel 2 |
| 3 | 2 | Left Deck (transport, pads, jog, tempo) |
| 4 | 3 | Right Deck (transport, pads, jog, tempo) |
| 5 | 4 | DJ FX (select, time, wet/dry, activate) |
| 16 | 15 | Global (back, forward, browse, view, shift, load) |

## Left Deck — MIDI Channel 3 (0x92 Note On / 0x82 Note Off)

| Control | Note (dec) | Note (hex) | Notes |
|---------|:---:|:---:|:---|
| Load | 1 | 0x01 | |
| Sync | 8 | 0x08 | Hold = KeySync |
| Cue | 9 | 0x09 | Shift = Set Cue Point |
| Play | 10 | 0x0A | |
| Pad Mode CUES | 11 | 0x0B | Alt = STEMS |
| Pad Mode LOOPS | 12 | 0x0C | Alt = AUTO |
| Pad Mode ROLL | 13 | 0x0D | Shift = SAMPLER |
| Action Pads | 15–22 | 0x0F–0x16 | 8 pads |
| Pitch Bend – | 29 | 0x1D | |
| Pitch Bend + | 30 | 0x1E | |
| Jog Touch | 33 | 0x21 | |
| Vinyl | 35 | 0x23 | Hold = GridCueEdit, Shift = SlipMode |
| AutoLoop Push | 39 | 0x27 | Shift = IncreaseBeatJumpSize |

### Left Deck CC

| Control | CC (hex) | Notes |
|---------|:---:|:---|
| Tempo Slider Upper | 0x1F | Inverted |
| Tempo Slider Lower | 0x4B | |
| AutoLoop Turn | 0x20 | Shift = BeatJump |
| Jog Wheel Upper | 0x37 | |
| Jog Wheel Lower | 0x4D | |

## Right Deck — MIDI Channel 4 (0x93 Note On / 0x83 Note Off)

Same note/CC layout as Left Deck, except:
- Load: note 2 (0x02)

## Mixer Channel 1 — MIDI Channel 1 (0x90 Note On / 0x80 Note Off)

| Control | Note/CC | Value |
|---------|:---:|:---|
| PFL (Cue Monitor) | Note 13 | 0x0D |
| Trim (Gain) | CC 3 | |
| Treble (High EQ) | CC 4 | |
| Mid EQ | CC 6 | |
| Bass (Low EQ) | CC 8 | |
| Channel Fader | CC 14 | |
| Sweep FX Knob | CC 11 | |
| Sweep FX Select 1 | Note 14 | 0x0E |
| Sweep FX Select 2 | Note 15 | 0x0F |

## Mixer Channel 2 — MIDI Channel 2 (0x91 Note On / 0x81 Note Off)

Same layout as Mixer Channel 1.

## DJ FX — MIDI Channel 5 (0x94 Note On)

| Control | Note/CC | Value |
|---------|:---:|:---|
| FX Select Push | Note 7 | |
| FX Select Touch | Note 9 | |
| FX Select Turn | CC 33 | |
| FX Time Push | Note 8 | |
| FX Time Turn | CC 34 | |
| FX Wet/Dry | CC 4 | |
| FX Activate | Note 6 | ch 5 |
| FX Assign 1 | Note 11 | |
| FX Assign 2 | Note 12 | |

## Global — MIDI Channel 16 (0x9F Note On / 0x8F Note Off)

| Control | Note/CC | Value |
|---------|:---:|:---|
| Back | Note 3 | 0x03 |
| Forward | Note 4 | 0x04 | Shift = Quantize |
| Browse Encoder Push | Note 6 | 0x06 |
| Browse Encoder Turn | CC 5 | 0x05 |
| View | Note 7 | 0x07 | Hold = ControlCenter, Shift = SwitchLayout |
| Shift | Note 8 | 0x08 |
| Eject/Source | Note 20 | 0x14 |

## Mixer (Global CC)

| Control | CC | Value |
|---------|:---:|:---|
| Cue Mix | CC 12 | |
| Cue Gain | CC 13 | |
| Crossfader | CC 14 | |

## Mic

| Control | Note | Value |
|---------|:---:|:---|
| Mic 1 | Note 36 | 0x24 |
| Mic 2 | Note 37 | 0x25 |

## Notes

- All MIDI channels in Engine OS QML are **0-indexed** (0 = MIDI ch 1). MIXXX uses standard 1-indexed status bytes (0x90 = ch 1).
- The Mixxx `Denon-Prime-Go.midi.xml` and `Denon-Prime-Go-scripts.js` must match these channel/note assignments.
- The `MIDI Learned` XML entries captured from the hardware have correct note numbers but may have wrong channels (learned during a session with different MIDI configuration).
- The authoritative reference is the Engine OS QML file — it defines the actual hardware firmware MIDI layout.
