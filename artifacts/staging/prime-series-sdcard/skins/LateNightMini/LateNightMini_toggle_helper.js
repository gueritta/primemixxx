/**
 * LateNightMini Toggle Helper
 *
 * Workaround for WPushButton toggle-mode buttons on the Prime Go embedded
 * platform. WPushButton getControlParameterLeft() returns stale values for
 * skin-created ControlPushButton COs, so toggle (read value > flip > write)
 * never sees the updated value.
 *
 * Uses the same manual-toggle pattern as the Prime Go View button
 * (engine.getValue + engine.setValue from Denon-Prime-Go-scripts.js).
 * Toolbar/settings buttons target _trig COs (PUSH, always emit 1.0).
 * This script listens for any positive value and manually toggles the
 * corresponding visibility CO.
 */
(function() {
    "use strict";

    var TOGGLE_MAP = {
        "show_waveforms_trig": "show_waveforms",
        "show_effectrack_trig": "show_effectrack",
        "show_samplers_trig": "show_samplers",
        "show_settings_trig": "show_settings",
        "max_lib_show_decks_trig": "max_lib_show_decks"
    };

    var GROUP = "[LateNightMini]";

    for (var trigKey in TOGGLE_MAP) {
        if (!TOGGLE_MAP.hasOwnProperty(trigKey)) continue;

        var target = TOGGLE_MAP[trigKey];

        engine.makeConnection(GROUP, trigKey, (function(targetKey) {
            return function(value) {
                if (value > 0) {
                    var current = engine.getValue(GROUP, targetKey);
                    var next = current > 0 ? 0 : 1;
                    engine.setValue(GROUP, targetKey, next);
                }
            };
        })(target));
    }
})();
