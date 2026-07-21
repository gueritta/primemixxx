# LateNightMini Skin — WPushButton Toggle Fix

## The Bug: WPushButton Stale-Read on EGLFS

On the Denon Prime Go (Mixxx 2.5.6, Qt 5.15.8 EGLFS, Mali DDK r1p0), **WPushButton's `getControlParameterLeft()` returns the initial value of ControlPushButton COs every time** — it never sees updated values.

In TOGGLE mode, this makes every toggle button a "show-only" button:
- Press 1: reads stale `0` → flips to `1` → writes `1` (panel shows)
- Press 2: reads stale `0` AGAIN → flips to `1` → writes `1` again (no change, panel stays shown)
- **Toggle-off never happens.**

This affects ALL buttons that write to `[Skin],*` or `[LateNightMini],*` ControlPushButton COs via `<ButtonState>LeftButton</ButtonState>`.

## Why Some Buttons Still Work

**Recording button** (`[Recording],toggle_recording`): NOT a ControlPushButton — auto-detected as PUSH mode. WPushButton always emits `1.0` on press. `RecordingManager::slotToggleRecording` toggles internally on any positive value.

**MIDI View button** (hardware): `Denon-Prime-Go-scripts.js` does a manual toggle:
```js
engine.getValue("[Master]", "maximize_library") > 0 ? 0 : 1
```
This bypasses WPushButton entirely — `engine.getValue` reads the real current value.

## The Fix: `_trig` COs + JS Toggle Helper

### Pattern

Use `_trig`-suffixed COs (auto-created as plain `ControlObject`, NOT `ControlPushButton`) → WPushButton detects PUSH mode → always emits `1.0` on press → JS script manually toggles the target visibility CO via `engine.getValue`/`engine.setValue`.

### Files

| File | Role |
|------|------|
| `mixxx-bundle/controllers/LateNightMini_toggle_helper.js` | JS toggle helper — listens for `_trig` COs, toggles targets |
| `mixxx-bundle/controllers/Denon-Prime-Go.midi.xml` | Loads the helper via `<scriptfiles>` |
| `mixxx-bundle/skins/LateNightMini/helpers/skin_settings_button_2state_touch.xml` | Touch-friendly template — no `<ButtonState>`, 40f height |
| `mixxx-bundle/skins/LateNightMini/helpers/skin_settings_labelbutton_2state_touch.xml` | Section header template — no `<ButtonState>`, 60f height |

### Adding a New Toggle Button

1. **Add mapping** to `LateNightMini_toggle_helper.js` `TOGGLE_TARGETS`:
```js
"show_waveforms_trig": {
    target: "[LateNightMini],show_waveforms",
    sync: []  // add engine COs here if needed, e.g. ["[EffectRack1],show"]
}
```

2. **Button ConfigKey** writes to `[LateNightMini],<name>_trig`:
```xml
<Configure>
  <ConfigKey persist="true">
    <Control>[LateNightMini]</Control>
    <Setting>show_waveforms_trig</Setting>
    <EmitOnPressAndRelease>false</EmitOnPressAndRelease>
  </ConfigKey>
</Configure>
```

3. **Visibility binding** reads the REAL CO (not `_trig`):
```xml
<BindGroup>
  <Visible>false</Visible>
  <ConfigKey persist="true">
    <Control>[LateNightMini]</Control>
    <Setting>show_waveforms</Setting>
  </ConfigKey>
</BindGroup>
```

4. **Use the `_touch` template** (no `ButtonState`, 40f+ height):
```xml
<Template src="skin_settings_button_2state_touch.xml"/>
```

5. **If the target syncs an engine CO**, add it to the `sync` array:
```js
"show_effectrack_trig": {
    target: "[LateNightMini],show_effectrack",
    sync: ["[EffectRack1],show"]
}
```

### Rules

- **_trig COs are NEVER declared as `<attribute>` in skin.xml** — they're auto-created as plain ControlObject
- **Cover visibility elements** (`skin_settings_cover_inverted.xml`) MUST read the real CO, NOT `_trig` (which is momentary 1→0)
- **`skin_settings_numToggle.xml`** has the same stale-read bug (uses `<Transform><IsEqual>` wrapper) — use `_trig` instead
- **Labelbuttons** using `_trig` always show unchecked (they read the momentary CO) — visual feedback is a known limitation
- **Never use `<ButtonState>LeftButton</ButtonState>`** — it forces TOGGLE mode which triggers the bug
- **`EmitOnPressAndRelease` must be `false`** for `_trig` COs — prevents double-fire

## Converted Buttons

### Toolbar (toolbar.xml)
| Button | Trig CO | Target CO | Sync CO |
|--------|---------|-----------|---------|
| LIBRARY | `maximize_library_trig` | `[Master],maximize_library` | — |
| WAVEFORMS | `show_waveforms_trig` | `[LateNightMini],show_waveforms` | — |
| EFFECTS | `show_effectrack_trig` | `[LateNightMini],show_effectrack` | `[EffectRack1],show` |
| SAMPLERS | `show_samplers_trig` | `[LateNightMini],show_samplers` | `[Samplers],show_samplers` |
| DECKS | `max_lib_show_decks_trig` | `[LateNightMini],max_lib_show_decks` | — |
| SKIN SETTINGS | `show_settings_trig` | `[LateNightMini],show_settings` | `[Skin],show_settings` |

### Skin Settings (skin_settings.xml)
| Button | Trig CO | Target CO | Sync CO |
|--------|---------|-----------|---------|
| Waveforms label | `show_waveforms_trig` | `[LateNightMini],show_waveforms` | — |
| Effect Units label | `show_effectrack_trig` | `[LateNightMini],show_effectrack` | `[EffectRack1],show` |
| Hotcue Shift | `timing_shift_buttons_trig` | `[LateNightMini],timing_shift_buttons` | — |
| Enforce equal heights | `keep_consistent_waveform_heights_trig` | `[LateNightMini],keep_consistent_waveform_heights` | — |
| Super Knobs | `show_superknobs_trig` | `[LateNightMini],show_superknobs` | `[Skin],show_superknobs` |

### Deck Settings (3 files)
| File | Toggles |
|------|---------|
| `skin_settings_full_deck.xml` | Loop Controls, Beatjump Controls, Rate Controls, Spinny, Cover Art, Hotcues, VU meters (~10 toggles) |
| `skin_settings_compact_deck.xml` | Same subset for compact layout (~8 toggles) |
| `skin_settings_mini_deck.xml` | VU meters, Spinny, Cover Art (~3 toggles) |

## Known Limitations

- **Labelbutton visual state**: Always shows unchecked (reads `_trig` CO which is momentary `1→0`). Could use `ConfigKeyDisp` pattern reading from real CO while writing to `_trig`.
- **`skin_settings_numToggle.xml`** (4/8 Hotcues, deck size radio buttons): Still uses old template with stale-read bug. Same fix needed.
- **`skin_settings_deck_size_button.xml`** (Mini/Compact/Full): Same bug, not yet converted.
- **Press time**: ILI2117 touchscreen firmware debounce — no OS-level tunable. Minimum press time is hardware-limited.
