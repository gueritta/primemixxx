/**
 * LateNightMini Toggle Helper
 *
 * Workaround for WPushButton toggle-mode bugs on Prime Go EGLFS.
 * Toolbar buttons target _trig COs (PUSH mode, always emit 1.0).
 * This script listens for trigger COs and manually toggles the
 * corresponding visibility COs using engine.getValue/setValue,
 * bypassing WPushButton getControlParameterLeft() entirely.
 */
(function() {
    "use strict";

    var DEFAULT_GROUP = "[LateNightMini]";

    // Each trigger key maps to { group, target, sync[]? }
    var TOGGLE_TARGETS = {
        "maximize_library_trig": { group: "[Master]",   target: "maximize_library" },
        "show_waveforms_trig":   { target: "show_waveforms" },
        "show_effectrack_trig":  { target: "show_effectrack",
                                    sync: ["[EffectRack1]", "show"] },
        "show_samplers_trig":    { target: "show_samplers",
                                    sync: ["[Samplers]", "show_samplers"] },
        "show_settings_trig":    { target: "show_settings",
                                    sync: ["[Skin]", "show_settings"] },
        "max_lib_show_decks_trig": { target: "max_lib_show_decks" },

        // Skin settings submenu toggles (button_2state_touch)
        "timing_shift_buttons_trig":           { group: "[Skin]", target: "timing_shift_buttons" },
        "keep_consistent_waveform_heights_trig": { group: "[Skin]", target: "keep_consistent_waveform_heights" },
        "show_superknobs_trig":               { group: "[Skin]", target: "show_superknobs" },

        // Deck settings — full deck
        "show_hotcues_trig":                  { group: "[Skin]", target: "show_hotcues" },
        "show_loop_controls_trig":            { group: "[Skin]", target: "show_loop_controls" },
        "show_beatjump_controls_trig":        { group: "[Skin]", target: "show_beatjump_controls" },
        "show_rate_controls_trig":            { group: "[Skin]", target: "show_rate_controls" },
        "show_spinnies_trig":                 { group: "[Skin]", target: "show_spinnies" },
        "show_coverart_trig":                 { group: "[Skin]", target: "show_coverart" },

        // Samplers section labelbutton (separate from toolbar SAMPLERS)
        "show_samplers_section_trig":         { group: "[Skin]", target: "show_samplers" },

        // Deck settings — compact deck
        "show_loop_controls_compact_trig":    { group: "[Skin]", target: "show_loop_controls_compact" },
        "show_beatjump_controls_compact_trig": { group: "[Skin]", target: "show_beatjump_controls_compact" },
        "show_rate_controls_compact_trig":    { group: "[Skin]", target: "show_rate_controls_compact" },

        // Bottom bar visibility (overview + spinny)
        "show_bottom_bar_trig":              { target: "show_bottom_bar" },

        // Deck settings — [LateNightMini] COs (also ControlPushButton)
        "show_vumeters_compact_trig":         { target: "show_vumeters_compact" },
        "show_sync_button_compact_trig":      { target: "show_sync_button_compact" }
    };

    for (var trigKey in TOGGLE_TARGETS) {
        if (!TOGGLE_TARGETS.hasOwnProperty(trigKey)) continue;

        var cfg = TOGGLE_TARGETS[trigKey];
        var group = cfg.group || DEFAULT_GROUP;

        engine.makeConnection(DEFAULT_GROUP, trigKey, (function(group, cfg) {
            return function(value) {
                if (value > 0) {
                    var current = engine.getValue(group, cfg.target);
                    var next = current > 0 ? 0 : 1;
                    engine.setValue(group, cfg.target, next);

                    if (cfg.sync) {
                        for (var i = 0; i < cfg.sync.length; i += 2) {
                            engine.setValue(cfg.sync[i], cfg.sync[i+1], next);
                        }
                    }
                }
            };
        })(group, cfg));
    }
})();
