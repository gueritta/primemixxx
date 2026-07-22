// eslint-disable-next-line-no-var
var PrimeGo = {};

// Polyfill: Array.includes for older JS engines (MIXXX Qt QJSEngine)
if (!Array.prototype.includes) {
    Array.prototype.includes = function(searchElement) {
        for (var i = 0; i < this.length; i++) {
            if (this[i] === searchElement) return true;
        }
        return false;
    };
}

// MIDI Spy: set to true to log all incoming MIDI messages (XML-based).
// Requires XML <control> entries binding PrimeGo.midiSpy to the desired MIDI channels.
PrimeGo.MIDI_SPY = false;
PrimeGo.midiSpy = function(channel, control, value, status, group) {
    print("MIDI_SPY: status=0x" + status.toString(16) + " data1=0x" + control.toString(16) + " data2=0x" + value.toString(16));
};

// Would you like each deck to show the colour of its loaded track (if specified)?
// (Choose between true or false)
//const showTrackColor = false; // NOT IMPLEMENTED YET

// What default colour would you like each deck to be?
/*
 * "red",
 * "green",
 * "blue",
 * "yellow",
 * "magenta",
 * "cyan",
 * "orange",
 * "aqua",
 * "violet",
 * "white",
 */

const deckColors = [

    // Deck 1
    "green",

    // Deck 2
    "blue",

];

// Would you like the TRACK SKIP ([|<<] and [>>|] buttons) to jump to the start and
// end of the track, or seek through it? (Choose "seek" or "skip")
const skipButtonBehaviour = "skip";

// How sensitive should the jog wheel be when nudging (while playing) or navigating
// (while paused) a track? (NOTE: 0.2 is a good value to start with. The larger the
// number, the more sensitive the wheel will be.)
const wheelSensitivity = 0.5;

// Edit the values in this list to choose which tempo fader ranges you would like
// to toggle through using [SHIFT} + Pitch bend [-] / [+] (0.5 = 50%).
const rateRanges = [
    0.04,
    0.08,
    0.24,
    0.5,
    0.9
];

/**************************************************
 *                                                *
 *                   WARNING!!!                   *
 *                                                *
 *      DO NOT EDIT ANYTHING PAST THIS POINT      *
 *       UNLESS YOU KNOW WHAT YOU'RE DOING.       *
 *                                                *
 **************************************************/

///////////// FX SCREEN LIBRARY /////////////

/*
const effectNames = ["---", "Autopan", "Balance", "Bessel4 ISO", "Bessel8 ISO", "Bitcrusher", "BQ EQ", "BQ EQ/ISO",
    "Distortion", "Echo", "Filter", "Flanger", "Graphic EQ", "Loudness", "LRB ISO", "Metronome", "Moog Filter",
    "Param EQ", "Phaser", "Pitch Shift", "Reverb", "Tremolo", "White Noise"];
*/

// TODO: The denonId SysEx prefix [0x00, 0x02, 0x0b] was copied from the Prime 4 mapping.
// This MUST be verified against the actual JP11 (Prime Go) device. The Prime Go may use
// a different SysEx identity. Use `amidi -d -p hw:1,0,0` to capture SysEx traffic and confirm.
const denonId = [0x00, 0x02, 0x0b];

// Shorthand for sending SysEx message to FX screens
const fxSendMsg = function(msg) {
    midi.sendSysexMsg(msg, msg.length);
};

// Add final layer to SysEx message (f0, 00, 02, 0b, ..., 0xf7)
const wrapFinalMsg = function(msg) {
    msg.unshift(...denonId);
    msg.unshift(0xf0);
    msg.push(0xf7);
    return msg;
};

// Show text
const fxText = function(screen, text, size = 0x02, align = 0x01) {
    const textBytes = [];

    // Convert text to ASCII
    for (const i in text) {
        textBytes[i] = text.charCodeAt(i);
    }

    // Alignment (0x00 = Left, 0x01 = Centre, 0x02 = Right)
    const position = 0x00; // top of screen
    const msg = [0x00, 0x08, 0x08, 0x00, 0, screen, size, align, position, ...textBytes];
    msg[4] = msg.length - 5;
    return (wrapFinalMsg(msg));
};

// Clear screen
const fxClear = function(screen) {
    return (fxText(screen, "", 0x03));
};

// Draw meter
const fxMeter = function(screen, end, start = 0) {
    const width = 0x7f;
    const height = 0x00;
    const fillColour = 0x01;
    const emptyColour = 0x00;
    const position = 0x03;
    const msg = [0x00, 0x08, 0x09, 0x00, 0x09, screen, width, height, 0x01, fillColour, emptyColour, position, start, end];
    return (wrapFinalMsg(msg));
};

/////////////////////////////////////////////

// Convert user-preference for `skipButtonBehaviour` into appropriate keys for components
let trackSkipMode = [];
if (skipButtonBehaviour === "skip") {
    trackSkipMode = ["start", "end"];
} else if (skipButtonBehaviour === "seek") {
    trackSkipMode = ["back", "fwd"];
}

// Beatjump sizes
const jumpSizes = [1/32, 1/16, 1/8, 1/4, 1/2, 1, 2, 4, 8, 16, 32, 64];

// Beatloop sizes
const loopSizes = [1/32, 1/16, 1/8, 1/4, 1/2, 1, 2, 4, 8, 16, 32, 64];

// Component re-jigging for pad mode purposes
components.ComponentContainer.prototype.reconnectComponents = function(operation, recursive) {
    this.forEachComponent(function(component) {
        component.disconnect();
        if (typeof operation === "function") {
            operation.call(this, component);
        }
        if (component.outConnect) { component.connect(); }
        if (component.outTrigger) { component.trigger(); }
    }, recursive);
};

// 'Off' value sets lights to dim instead of off
components.Button.prototype.off = 0x01;

// Function to send specific RGB values through SysEx messages
const sendSysexRGB = function(channel, control, red, green, blue) {
    const msg = [0xf0, 0x00, 0x02, 0x0b, 0x7f, 0x0C, 0x03, 0x00, 0x05, channel, control, red, green, blue, 0xf7];
    midi.sendSysexMsg(msg, msg.length);
};

// Internal MIDI colour palette
PrimeGo.rgbCode = {
    black: 0,
    blueDark: 1,
    blueDim: 2,
    blue: 3,
    greenDark: 4,
    cyanDark: 5,
    aquaDark: 5,
    greenDim: 8,
    cyanDim: 10,
    green: 12,
    aqua: 14,
    cyan: 15,
    redDark: 16,
    magentaDark: 17,
    violetDark: 17,
    yellowDark: 20,
    whiteDark: 21,
    redDim: 32,
    magentaDim: 34,
    purple: 35,
    violet: 35,
    orangeDark: 36,
    yellowDim: 40,
    whiteDim: 42,
    red: 48,
    magenta: 51,
    orange: 56,
    yellow: 60,
    white: 63,
};

// SysEx RGB values for more precise colour control
PrimeGo.rgbCodeSysex = {
    red: [0x7f, 0x00, 0x00],
    redDark: [0x0f, 0x00, 0x00],

    green: [0x00, 0x7f, 0x00],
    greenDark: [0x00, 0x0f, 0x00],

    blue: [0x00, 0x00, 0x7f],
    blueDark: [0x00, 0x00, 0x0f],

    yellow: [0x7f, 0x7f, 0x00],
    yellowDark: [0x0f, 0x0f, 0x00],

    magenta: [0x7f, 0x00, 0x7f],
    magentaDark: [0x0f, 0x00, 0x0f],

    cyan: [0x00, 0x7f, 0x7f],
    cyanDark: [0x00, 0x0f, 0x0f],

    orange: [0x7f, 0x2f, 0x00],
    orangeDark: [0x0f, 0x06, 0x00],

    aqua: [0x00, 0x7f, 0x2f],
    aquaDark: [0x00, 0x0f, 0x06],

    violet: [0x2f, 0x00, 0x7f],
    violetDark: [0x06, 0x00, 0x0f],

    white: [0x7e, 0x7e, 0x7f],
    whiteDark: [0x0e, 0x0e, 0x0f],
};

// Reverse lookup: rgbCode integer value → color name string
PrimeGo._rgbCodeToName = {};
for (var k in PrimeGo.rgbCode) {
    if (PrimeGo.rgbCode.hasOwnProperty(k)) {
        PrimeGo._rgbCodeToName[PrimeGo.rgbCode[k]] = k;
    }
}
// Convert an rgbCode integer to the corresponding SysEx RGB array
PrimeGo.rgbCodeToSysex = function(code) {
    var name = PrimeGo._rgbCodeToName[code];
    if (name && PrimeGo.rgbCodeSysex[name]) {
        return PrimeGo.rgbCodeSysex[name];
    }
    // Fallback: dim white
    return [0x01, 0x01, 0x01];
};

// Used in Swiftb0y's NS6II mapping for tempo fader LEDs
PrimeGo.physicalSliderPositions = {
    left: 0.5,
    right: 0.5,
};

// Set active values for user-defined deck colours
const colDeck = [
    PrimeGo.rgbCode[deckColors[0]],
    PrimeGo.rgbCode[deckColors[1]],
];

const colDeckSysex = [
    PrimeGo.rgbCodeSysex[deckColors[0]],
    PrimeGo.rgbCodeSysex[deckColors[1]],
];

// Set inactive values for user-defined deck colours
const colDeckDark = [
    PrimeGo.rgbCode[deckColors[0] + "Dark"],
    PrimeGo.rgbCode[deckColors[1] + "Dark"],
];

const colDeckDarkSysex = [
    PrimeGo.rgbCodeSysex[deckColors[0] + "Dark"],
    PrimeGo.rgbCodeSysex[deckColors[1] + "Dark"],
];

// Register '0x9n' as a button press and '0x8n' as a button release
components.Button.prototype.isPress = function(channel, control, value, status) {
    return (status & 0xF0) === 0x90;
};

PrimeGo.DeckAssignButton = function(options) {
    components.Button.call(this, options);

    if (!Number.isInteger(this.deckIndex)) {
        throw `invalid deckIndex: ${this.deckIndex}`;
    }
    if (!(this.toDeck instanceof PrimeGo.Deck)) {
        throw "invalid toDeck";
    }

    const deckSide = (this.deckIndex % 2) === 0 ? "leftDeck" : "rightDeck";
    if (!(PrimeGo[deckSide] instanceof PrimeGo.Deck)) {
        throw "invalid deckIndex or structure; We expect PrimeGo.leftDeck and PrimeGo.rightDeck to be valid decks representing the physical left and right decks";
    }
    const isActive = () => {
        return PrimeGo[deckSide] === this.toDeck;
    };

    this.output = function(sysexColour) {
        sendSysexRGB(this.midi[0], this.midi[1], ...sysexColour);
    };

    this.trigger = function() {
        this.output(this.outValueScale(isActive()));
    };

    this.outValueScale = function(value) {
        return value ? this.on : this.off;
    };

    this.input = function(channel, control, value, status, _group) {
        if (!this.isPress(channel, control, value, status) || isActive()) {
            return;
        }
        PrimeGo[deckSide].forEachComponent(c => { c.disconnect(); });
        PrimeGo[deckSide] = this.toDeck;
        this.assignmentButtons.forEachComponent(btn => btn.trigger());
        PrimeGo[deckSide].forEachComponent(c => { c.connect(); c.trigger(); });
    };
};
PrimeGo.DeckAssignButton.prototype = Object.create(components.Button.prototype);

// Provide functions for encoders to cycle through an array of values, like beatjump size
// See NS6II mapping
PrimeGo.CyclingArrayView = class {
    constructor(indexable, startIndex) {
        this.indexable = indexable;
        this.index = startIndex || 0;
    }
    advanceBy(n) {
        this.index = script.posMod(this.index + n, this.indexable.length);
        return this.current();
    }
    next() {
        if (this.index !== (this.indexable.length - 1)) {
            return this.advanceBy(1);
        } else {
            return this.current;
        }
    }
    previous() {
        if (this.index !== 0) {
            return this.advanceBy(-1);
        } else {
            return this.current;
        }
    }
    current() {
        return this.indexable[this.index];
    }
};

PrimeGo.WrappingArrayView = class {
    constructor(indexable, startIndex) {
        this.indexable = indexable;
        this.index = startIndex || 0;
    }
    advanceBy(n) {
        this.index = script.posMod(this.index + n, this.indexable.length);
        return this.current();
    }
    next() {
        return this.advanceBy(1);
    }
    previous() {
        return this.advanceBy(-1);
    }
    current() {
        return this.indexable[this.index];
    }
};

// Re-interpret incoming MIDI messages from the Prime Go's effect unit knobs
PrimeGo.EffectUnitEncoderInput = function(_channel, _control, value, _status, _group) {
    const signedValue = value > (0x80 / 2) ? value - 128 : value;
    this.inSetParameter(this.inGetParameter() + (signedValue / 100));
};

// SysEx message for returning position of all components
// SysEx sequences from JP11_Controller_Device.qml (authoritative reference)
// Subsystem ID: 0x0C (NOT 0x08 — 0x08 was wrong in the original JS)
const PrimeGo_sysex = {
    // Universal Device Identity Request (MMC)
    deviceQuery:       [0xF0, 0x7E, 0x00, 0x06, 0x01, 0xF7],
    // Send initialization to controller (configures LEDs, modes, etc.)
    init:              [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x0C, 0x60, 0x00, 0x04, 0x04, 0x01, 0x01, 0x04, 0xF7],
    // Request all absolute control positions (faders, knobs report current state)
    queryControls:     [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x0C, 0x04, 0x00, 0x00, 0xF7],
    // Check if power-on button held (for test mode entry)
    powerOnState:      [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x0C, 0x42, 0x00, 0x00, 0xF7],
};

// Send RGB color to a pad LED (channel=deck, index=0-7 pad, color component 0-1)
// Format: F0 00 02 0B 7F 0C 03 00 05 <ch> <idx> <R> <G> <B> F7
PrimeGo.sendPadColor = function(channel, index, r, g, b) {
    var msg = [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x0C, 0x03, 0x00, 0x05,
               channel & 0x7F, index & 0x7F,
               Math.min(127, Math.max(0, r)) & 0x7F,
               Math.min(127, Math.max(0, g)) & 0x7F,
               Math.min(127, Math.max(0, b)) & 0x7F, 0xF7];
    midi.sendSysexMsg(msg, msg.length);
};

// Meters on OLED screens to visualize effects
const fxScreen = function(offset, bank) {
    components.Deck.call(this, bank);
    const effectMeta = [];
    for (let i = 1; i <= 3; i++) {
        effectMeta[i - 1] = new components.Component({
            group: "[EffectRack1_EffectUnit" + bank + "_Effect" + i + "]",
            outKey: "meta",
            output: function() {
                const barFill = ((engine.getParameter("[EffectRack1_EffectUnit" + bank + "_Effect" + i + "]", "meta")) * 127);
                fxSendMsg(fxMeter(i + offset - 1, barFill));
            },
        });
    }
    new components.Component({
        group: "[EffectRack1_EffectUnit" + bank + "]",
        outKey: "mix",
        output: function() {
            const barFill = ((engine.getParameter("[EffectRack1_EffectUnit" + bank + "]", "mix")) * 127);
            fxSendMsg(fxMeter(3 + offset, barFill));
        },
    });
};
fxScreen.prototype = new components.Deck();

PrimeGo.init = function(_id, _debug) {
    // Universal Device Identity Request (helps PortMidi enumeration)
    midi.sendSysexMsg(PrimeGo_sysex.deviceQuery, PrimeGo_sysex.deviceQuery.length);

    // Turn off all LEDs
    midi.sendShortMsg(0x90, 0x75, 0x00);

    // Clear OLED screens
    for (let i = 0; i < 8; i++) {
        fxSendMsg(fxClear(i));
    }

    // Send controller initialization (from JP11_Controller_Device.qml)
    midi.sendSysexMsg(PrimeGo_sysex.init, PrimeGo_sysex.init.length);

    // After init, request all absolute control positions
    // (so MIXXX syncs with hardware fader/knob positions)
    engine.beginTimer(1000, function() {
        midi.sendSysexMsg(PrimeGo_sysex.queryControls, PrimeGo_sysex.queryControls.length);
    }, true);

    const decks = [
        new PrimeGo.Deck(1, 2),
        new PrimeGo.Deck(2, 3),
    ];

    PrimeGo.fxScreens1 = new fxScreen(0, 1);
    PrimeGo.fxScreens2 = new fxScreen(4, 2);
    for (let j = 0; j <= 1; j++) {
        for (let i = 0; i <= 2; i++) {
            fxSendMsg(fxText(i + (j * 4), ("Effect " + (i + 1))));
        }
        fxSendMsg(fxText(3 + (j * 4), "Dry / Wet"));
    }

    // Disconnect all decks at first so they don't fight with each other
    decks.forEach(deck => deck.forEachComponent(comp => { console.log(`disconnecting "${comp.group}, ${comp.inKey}"`); comp.disconnect(); }));

    // Assign each console deck to Mixxx decks 1 and 2 on startup
    PrimeGo.leftDeck = decks[0];
    PrimeGo.rightDeck = decks[1];

    // Initialize deck toggle buttons
    PrimeGo.assignmentButtons = new components.ComponentContainer();
    for (let i = 0; i < decks.length; i++) {
        PrimeGo.assignmentButtons[i] = new PrimeGo.DeckAssignButton({
            midi: [0x0F, 0x1C + i],
            deckIndex: i,
            toDeck: decks[i],
            assignmentButtons: this.assignmentButtons,
            off: colDeckDarkSysex[i],
            on: colDeckSysex[i],
        });
        PrimeGo.assignmentButtons[i].trigger();
    }

    // Initialize mixer channel strips (Prime Go has 2 channels)
    PrimeGo.mixerA = new mixerStrip(1, 0);
    PrimeGo.mixerB = new mixerStrip(2, 1);

    // Initialize effect banks
    PrimeGo.effectBank = [];
    for (let i = 0; i <= 1; i++) {
        PrimeGo.effectBank[i] = new components.EffectUnit([i + 1, i + 3]);
        for (let j = 0; j < 3; j++) {
            PrimeGo.effectBank[i].enableButtons[j + 1].midi = [0x96 + i, 0x06 + j];
            PrimeGo.effectBank[i].knobs[j + 1].midi = [0xB6 + i, 0x01 + j];
            PrimeGo.effectBank[i].knobs[j + 1].input = PrimeGo.EffectUnitEncoderInput;
        }
        PrimeGo.effectBank[i].dryWetKnob.midi = [0xB6 + i, 0x04];
        PrimeGo.effectBank[i].dryWetKnob.input = PrimeGo.EffectUnitEncoderInput;
        PrimeGo.effectBank[i].effectFocusButton.midi = [0x96 + i, 0x0A];
        PrimeGo.effectBank[i].init();
    }

    // ===== FX PARAMETER FOCUS =====
    // Pre-seed COs (must exist before skin XML references them)
    for (var e = 1; e <= 3; e++) {
        engine.setValue("[Skin]", "fx_param_knob_focus_" + e, 0);
        engine.setValue("[Skin]", "fx_param_button_focus_" + e, 0);
    }

    PrimeGo.fxFocus = {
        effect: 1,
        paramIndex: 0
    };

    PrimeGo.fxParamNames = [
        "parameter1", "parameter2", "parameter3", "parameter4",
        "parameter5", "parameter6", "parameter7", "parameter8"
    ];

    PrimeGo.fxUpdateDisplay = function() {
        var eff = PrimeGo.fxFocus.effect;
        var idx = PrimeGo.fxFocus.paramIndex;
        for (var e = 1; e <= 3; e++) {
            engine.setValue("[Skin]", "fx_param_knob_focus_" + e, 0);
            engine.setValue("[Skin]", "fx_param_button_focus_" + e, 0);
        }
        if (eff > 0 && idx > 0) {
            engine.setValue("[EffectRack1_EffectUnit1]", "focused_effect", eff);
            engine.setValue("[Skin]", "fx_param_knob_focus_" + eff, idx);
        } else {
            engine.setValue("[EffectRack1_EffectUnit1]", "focused_effect", 0);
        }
    };

    PrimeGo.fxCycleParam = function(direction) {
        var eff = PrimeGo.fxFocus.effect;
        if (eff === 0) return;
        var group = "[EffectRack1_EffectUnit" + (eff <= 2 ? "1" : "2");
        group += "_Effect" + eff + "]";
        var loaded = [];
        for (var p = 0; p < 8; p++) {
            if (engine.getValue(group, PrimeGo.fxParamNames[p] + "_loaded") > 0) {
                loaded.push(p + 1);
            }
        }
        if (loaded.length === 0) {
            PrimeGo.fxFocus.paramIndex = 0;
            PrimeGo.fxUpdateDisplay();
            return;
        }
        var cur = loaded.indexOf(PrimeGo.fxFocus.paramIndex);
        if (cur === -1) {
            PrimeGo.fxFocus.paramIndex = loaded[0];
        } else {
            cur += direction;
            if (cur < 0) cur = loaded.length - 1;
            if (cur >= loaded.length) cur = 0;
            PrimeGo.fxFocus.paramIndex = loaded[cur];
        }
        PrimeGo.fxUpdateDisplay();
    };

    // FX Select encoder: turn to cycle effect slots (ch5 note 0x09, CC 0x21)
    // TODO: capacitive touch (note 0x09) — re-add fxSelectTouch to reveal effect on touch
    PrimeGo.fxSelectTouch = function(channel, control, value, status) {
        // capacitive touch disabled for now
    };

    PrimeGo.fxSelectTurn = function(channel, control, value, status) {
        var dir = (value === 0x7F) ? -1 : 1;
        var eff = PrimeGo.fxFocus.effect + dir;
        if (eff > 3) eff = 1;
        if (eff < 1) eff = 3;
        PrimeGo.fxFocus.effect = eff;
        PrimeGo.fxFocus.paramIndex = 1;
        PrimeGo.fxUpdateDisplay();
    };

    // FX Time encoder: touch cycles params, turn always adjusts value, push toggles button
    PrimeGo.fxTimeTouch = function(channel, control, value, status) {
        if (value !== 0x7F) return;
        PrimeGo.fxCycleParam(1);
    };

    PrimeGo.fxTimeTurn = function(channel, control, value, status) {
        var dir = (value === 0x01) ? 1 : -1;
        var eff = PrimeGo.fxFocus.effect;
        var idx = PrimeGo.fxFocus.paramIndex;
        if (eff > 0 && idx > 0) {
            var unit = eff <= 2 ? 1 : 2;
            var eNum = eff <= 2 ? eff : eff - 2;
            var group = "[EffectRack1_EffectUnit" + unit + "_Effect" + eNum + "]";
            var cur = engine.getValue(group, "parameter" + idx);
            var delta = dir * 0.05;
            engine.setValue(group, "parameter" + idx, Math.min(1.0, Math.max(0.0, cur + delta)));
        }
    };

    PrimeGo.fxTimePush = function(channel, control, value, status) {
        if (value !== 0x7F) return;
        var eff = PrimeGo.fxFocus.effect;
        var idx = PrimeGo.fxFocus.paramIndex;
        if (eff > 0 && idx > 0) {
            var unit = eff <= 2 ? 1 : 2;
            var eNum = eff <= 2 ? eff : eff - 2;
            var group = "[EffectRack1_EffectUnit" + unit + "_Effect" + eNum + "]";
            engine.setValue(group, "button_parameter" + idx,
                engine.getValue(group, "button_parameter" + idx) > 0 ? 0 : 1);
        }
    };

    // FX Select push: toggle focused effect on/off (ch5 CC 0x21 push)
    PrimeGo.fxSelectPush = function(channel, control, value, status) {
        if (value !== 0x7F) return;
        var eff = PrimeGo.fxFocus.effect;
        if (eff > 0) {
            var unit = eff <= 2 ? 1 : 2;
            var eNum = eff <= 2 ? eff : eff - 2;
            engine.setValue("[EffectRack1_EffectUnit" + unit + "_Effect" + eNum + "]", "enabled",
                engine.getValue("[EffectRack1_EffectUnit" + unit + "_Effect" + eNum + "]", "enabled") > 0 ? 0 : 1);
        }
    };

    PrimeGo.fxActivate = function(channel, control, value, status) {
        if (value !== 0x7F) return;
        var eff = PrimeGo.fxFocus.effect;
        if (eff > 0) {
            var unit = eff <= 2 ? 1 : 2;
            engine.setValue("[EffectRack1_EffectUnit" + unit + "]", "group_[Channel1]_enable",
                engine.getValue("[EffectRack1_EffectUnit" + unit + "]", "group_[Channel1]_enable") > 0 ? 0 : 1);
        }
    };

    PrimeGo.fxWetDry = function(channel, control, value, status) {
        var eff = PrimeGo.fxFocus.effect;
        if (eff > 0) {
            var unit = eff <= 2 ? 1 : 2;
            engine.setValue("[EffectRack1_EffectUnit" + unit + "]", "mix", value / 127);
        }
    };

    PrimeGo.fxAssign1 = function(channel, control, value, status) {
        if (value !== 0x7F) return;
    };

    PrimeGo.fxAssign2 = function(channel, control, value, status) {
        if (value !== 0x7F) return;
    };

    // Press down on the library encoder, acts as 'Enter' key in Mixxx library
    PrimeGo.encoderLoad = new components.Button({
        midi: [0x9F, 0x06],
        group: "[Library]",
        key: "GoToItem",
    });

    // Browse encoder with shift acceleration
    PrimeGo.browseEncoder = function(channel, control, value, status, group) {
        // value: 0x01 = clockwise (down), 0x7F = counter-clockwise (up)
        var step = PrimeGo.shift ? 20 : 1;
        if (value === 0x01) {
            for (var i = 0; i < step; i++) {
                engine.setValue("[Library]", "MoveDown", 1);
            }
        } else if (value === 0x7F) {
            for (var i = 0; i < step; i++) {
                engine.setValue("[Library]", "MoveUp", 1);
            }
        }
    };

    // VIEW Button (QML: holdAction=ToggleControlCenter, shiftAction=SwitchMainViewLayout)
    PrimeGo.maxView = new components.Button({
        midi: [0x9F, 0x07],
        outConnect: true,
        input: function(channel, control, value, status, _group) {
            if (!this.isPress(channel, control, value, status)) return;
            if (PrimeGo.shift) {
                // Shift+VIEW: toggle skin menubar visibility
                engine.setValue("[Skin]", "show_menubar",
                    engine.getValue("[Skin]", "show_menubar") > 0 ? 0 : 1);
            } else {
                // VIEW: toggle maximize library
                engine.setValue("[Master]", "maximize_library",
                    engine.getValue("[Master]", "maximize_library") > 0 ? 0 : 1);
            }
        },
        output: function() {
            this.send(engine.getValue("[Master]", "maximize_library") > 0 ? 0x02 : 0x01);
        },
        connect: function() {
            components.Button.prototype.connect.call(this);
            this.output();  // no outKey — manually init LED
        },
    });

    // BACK Button
    PrimeGo.moveBack = new components.Button({
        midi: [0x9F, 0x03],
        group: "[Library]",
        key: "MoveFocusBackward",
        outConnect: true,
        output: function() {
            // Always dimly lit (Simple LED, note 3)
            this.send(0x02);
        },
        connect: function() {
            components.Button.prototype.connect.call(this);
            this.output();  // no outKey — manually init LED
        },
    });

    // FWD Button (QML: shiftAction: Action.Quantize)
    PrimeGo.moveForward = new components.Button({
        midi: [0x9F, 0x04],
        outConnect: true,
        input: function(channel, control, value, status, _group) {
            if (PrimeGo.shift) {
                // QML: shiftAction: Action.Quantize
                if (this.isPress(channel, control, value, status)) {
                    engine.setValue("[Master]", "quantize",
                        engine.getValue("[Master]", "quantize") > 0 ? 0 : 1);
                }
            } else {
                engine.setValue("[Library]", "MoveFocusForward", 1);
            }
        },
        output: function() {
            // Always dimly lit (Simple LED, note 4)
            this.send(0x02);
        },
        connect: function() {
            components.Button.prototype.connect.call(this);
            this.output();  // no outKey — manually init LED
        },
    });

    PrimeGo.quickEffectPresetIndexes = {
        filter: 11,
        echo: 10,
        wash: 17,
        noise: 19,
    };

    PrimeGo.selectQuickEffectPreset = function(presetName) {
        const presetIndex = PrimeGo.quickEffectPresetIndexes[presetName];
        if (presetIndex === undefined) {
            return;
        }

        for (let i = 1; i <= 2; i++) {
            const effect = "[QuickEffectRack1_[Channel" + i + "]]";
            let currentPreset = engine.getValue(effect, "loaded_chain_preset");
            const numPresets = engine.getValue(effect, "num_chain_presets");

            if (currentPreset < 0) {
                currentPreset = 0;
            }

            if (numPresets > 0 && currentPreset !== presetIndex) {
                const forwardSteps = script.posMod(presetIndex - currentPreset, numPresets);
                const backwardSteps = script.posMod(currentPreset - presetIndex, numPresets);
                const direction = forwardSteps <= backwardSteps ? 1 : -1;
                const steps = Math.min(forwardSteps, backwardSteps);

                for (let step = 0; step < steps; step++) {
                    engine.setValue(effect, "chain_selector", direction);
                }
            }

            engine.setParameter(effect, "enabled", 1);
        }
    };

    // Sweep FX - Filter Button
    PrimeGo.sweepFilter = new components.Button({
        midi: [0x9F, 0x0C],
        group: "[QuickEffectRack1_[Channel1]]",
        key: "enabled",
        on: 0x02,
        off: 0x01,
        input: function(channel, control, value, status, _group) {
            if (!this.isPress(channel, control, value, status)) return;
            PrimeGo.selectQuickEffectPreset("filter");
        },
    });

    // Sweep FX - Echo Button
    PrimeGo.sweepEcho = new components.Button({
        midi: [0x9F, 0x0D],
        input: function(channel, control, value, status, _group) {
            if (!this.isPress(channel, control, value, status)) return;
            PrimeGo.selectQuickEffectPreset("echo");
        },
    });
    // Sweep FX - Wash Button
    PrimeGo.sweepWash = new components.Button({
        midi: [0x9F, 0x0E],
        input: function(channel, control, value, status, _group) {
            if (!this.isPress(channel, control, value, status)) return;
            PrimeGo.selectQuickEffectPreset("wash");
        },
    });
    // Sweep FX - Noise Button
    PrimeGo.sweepNoise = new components.Button({
        midi: [0x9F, 0x0F],
        input: function(channel, control, value, status, _group) {
            if (!this.isPress(channel, control, value, status)) return;
            PrimeGo.selectQuickEffectPreset("noise");
        },
    });

    // Eject / Source Button (QML: Media { name='Eject', shift='Source', note=20, hasLed=true })
    PrimeGo.ejectButton = new components.Button({
        midi: [0x9F, 0x14],
        outConnect: true,
        input: function(channel, control, value, status, _group) {
            if (!this.isPress(channel, control, value, status)) return;
            if (PrimeGo.shift) {
                // QML: shift='Source' — jump to source/device tree
                engine.setValue("[Library]", "MoveUp", 1);
                engine.setValue("[Library]", "MoveFocusForward", 1);
            } else {
                // Eject track from all decks
                for (var d = 1; d <= 2; d++) {
                    engine.setValue("[Channel" + d + "]", "eject", 1);
                }
            }
        },
        output: function() {
            // LED: dim when no track, green when any track loaded
            var loaded = false;
            for (var d = 1; d <= 2; d++) {
                if (engine.getValue("[Channel" + d + "]", "track_loaded") > 0) {
                    loaded = true;
                    break;
                }
            }
            this.send(loaded ? 0x0C : 0x01);
        },
        connect: function() {
            components.Button.prototype.connect.call(this);
            this.output();  // no outKey — manually init LED
        },
    });

    // Mic 1 Button (QML: HardwareMixerMic { note: 36; canToggleTalkover: true })
    PrimeGo.mic1Button = new components.Button({
        midi: [0x9F, 0x24],
        input: function(channel, control, value, status, _group) {
            if (this.isPress(channel, control, value, status)) {
                var mic = "[Microphone]";
                engine.setValue(mic, "talkover",
                    engine.getValue(mic, "talkover") > 0 ? 0 : 1);
            }
        },
    });

    // Mic 2 Button (QML: HardwareMixerMic { note: 37 })
    PrimeGo.mic2Button = new components.Button({
        midi: [0x9F, 0x25],
        outConnect: false,
    });

    // Headphone Split Button
    PrimeGo.split = new components.Button({
        midi: [0x9F, 0x0B],
        group: "[Master]",
        key: "headSplit",
        type: components.Button.prototype.types.toggle,
    });

    PrimeGo.leftDeck.reconnectComponents();
    PrimeGo.rightDeck.reconnectComponents();

    // LED Initialization — QML Shift is global ch15 note 8
    midi.sendShortMsg(0x9F, 0x08, 0x01); // Shift button dim

};

PrimeGo.shutdown = function() {
    // From JP11_Controller_Device.qml: Component.onDestruction
    // Sends Note Off on channel 0, note 118 (0x76) to cleanly disconnect
    midi.sendShortMsg(0x80, 0x76, 0x00);

    // Dim all LEDs to initial state
    midi.sendShortMsg(0x90, 0x75, 0x01);

    // Clear OLED screens
    for (var i = 0; i < 8; i++) {
        fxSendMsg(fxClear(i));
    }
};

// All components contained in each mixer strip
const mixerStrip = function(deckNumber, midiOffset) {
    components.Deck.call(this, deckNumber);

    // FX Assign Buttons
    this.fxBankSelect = new components.ComponentContainer;
    for (let u = 1; u <= 2; u++) {
        this.fxBankSelect[u] = new components.EffectAssignmentButton({
            midi: [0x90 + midiOffset, 0x00 + u],
            effectUnit: u,
            group: "[Channel" + deckNumber + "]",
        });
    }

    // Gain Knob
    this.gain = new components.Pot({
        midi: [0xB0 + midiOffset, 0x03],
        group: "[Channel" + deckNumber + "]",
        inKey: "pregain",
    });

    // High EQ Knob
    this.eqHigh = new components.Pot({
        midi: [0xB0 + midiOffset, 0x04],
        group: "[EqualizerRack1_[Channel" + deckNumber + "]_Effect1]",
        inKey: "parameter3",
    });

    // Mid EQ Knob
    this.eqMid = new components.Pot({
        midi: [0xB0 + midiOffset, 0x06],
        group: "[EqualizerRack1_[Channel" + deckNumber + "]_Effect1]",
        inKey: "parameter2",
    });

    // Low EQ Knob
    this.eqLow = new components.Pot({
        midi: [0xB0 + midiOffset, 0x08],
        group: "[EqualizerRack1_[Channel" + deckNumber + "]_Effect1]",
        inKey: "parameter1",
    });

    // VU Meters
    this.vuMeter = new components.Component({
        midi: [0xB0 + midiOffset, 0x0A],
        group: "[Channel" + deckNumber + "]",
        outKey: "VuMeter",
        output: function(value, group) {
            if (engine.getValue(group, "PeakIndicator") === 1) {
                value = 0x7f;
            } else {
                const meter = Math.round(value * 127);
                value = (meter - ((meter - 1) % 13));
                if (value === 1) {
                    value = 0;
                }
            }
            this.send(value);
        },
    });

    // QuickEffect Knob (QML: SweepFxKnob { cc: 11 })
    this.sweepFxKnob = new components.Pot({
        midi: [0xB0 + midiOffset, 0x0B],
        group: "[QuickEffectRack1_[Channel" + deckNumber + "]]",
        inKey: "super1",
    });

    // Sweep FX Select Buttons (QML: SweepFxSelect notes 14=DualFilter, 15=Wash)
    this.sweepFxFilter = new components.Button({
        midi: [0x90 + midiOffset, 0x0E],
        group: "[QuickEffectRack1_[Channel" + deckNumber + "]]",
        key: "enabled",
        on: 0x02,
        off: 0x01,
        type: components.Button.prototype.types.toggle,
    });

    this.sweepFxWash = new components.Button({
        midi: [0x90 + midiOffset, 0x0F],
        group: "[QuickEffectRack1_[Channel" + deckNumber + "]]",
        key: "enabled",
        on: 0x02,
        off: 0x01,
        type: components.Button.prototype.types.toggle,
    });

    // PFL Button — QML: pflNote=13, LedType.Simple
    this.headphoneCue = new components.Button({
        midi: [0x90 + midiOffset, 0x0D],
        key: "pfl",
        type: components.Button.prototype.types.toggle,
        output: function(value) {
            if (value > 0) {
                this.send(colDeck[midiOffset]);       // bright deck color
            } else {
                this.send(0x01);                       // dim, not off
            }
        },
    });

    // Volume Fader
    this.volumeFader = new components.Pot({
        midi: [0x90 + midiOffset, 0x0E],
        inKey: "volume",
        inSetParameter: function(value) {
            print("DBG_VOL: deck=" + deckNumber + " ch=" + (0x90 + midiOffset).toString(16) + " val=" + value.toFixed(4));
            engine.setParameter(this.group, this.inKey, value);
        },
    });

    // Crossfader Assign Switch
    this.xFaderSwitch = new components.Button({
        midi: [0x90 + midiOffset, 0x0F],
        inKey: "orientation",
        input: function(_channel, _control, value, _status, _group) {
            this.inSetValue(value);
        },
    });

    this.reconnectComponents(function(c) {
        if (c.group === undefined) {
            c.group = this.currentDeck;
        }
    });
};

mixerStrip.prototype = new components.Deck();

// All components contained on each deck
PrimeGo.Deck = function(deckNumbers, midiChannel) {
    components.Deck.call(this, deckNumbers);
    const theDeck = this;

    // Used in Swiftb0y's NS6II mapping for tempo fader LEDs
    const makeSliderPosAccessors = function() {
        const lr = midiChannel % 2 === 0 ? "left" : "right";
        return {
            setter: function(pos) {
                PrimeGo.physicalSliderPositions[lr] = pos;
            },
            getter: function() {
                return PrimeGo.physicalSliderPositions[lr];
            }
        };
    };
    const sliderPosAccessors = makeSliderPosAccessors();

    // Censor Button
    this.censorButton = new components.Button({
        midi: [0x90 + midiChannel, 0x01],
        unshift: function() {
            this.inKey = "reverseroll";
            this.outKey = this.inKey;
        },
        shift: function() {
            this.inKey = "reverse";
            this.outKey = this.inKey;
        },
    });

    // Skip Backward
    this.skipBackButton = new components.Button({
        midi: [0x90 + midiChannel, 0x04],
        key: trackSkipMode[0],
    });

    // Skip Forward
    this.skipFwdButton = new components.Button({
        midi: [0x90 + midiChannel, 0x05],
        key: trackSkipMode[1],
    });

    // Beatjump Buttons
    const currentJumpSize = new PrimeGo.CyclingArrayView(jumpSizes, 2);
    this.bjumpBackButton = new components.Button({
        midi: [0x90 + midiChannel, 0x06],
        unshift: function() {
            this.inKey = "beatjump_backward";
            this.outKey = this.inKey;
            this.input = components.Button.prototype.input;
            this.outTrigger = true;
            this.outConnect = true;
        },
        shift: function() {
            this.inKey = "beatjump_size";
            this.outKey = this.inKey;
            this.input = function(channel, control, value, status, group) {
                if (this.isPress(channel, control, value, status, group)) {
                    this.inSetValue(currentJumpSize.previous());
                }
                this.send(value / 2 + 0.5); // Hacky way to get LEDs to respond properly
            };
            this.outTrigger = false;
            this.outConnect = false;
        },
    });
    this.bjumpFwdButton = new components.Button({
        midi: [0x90 + midiChannel, 0x07],
        unshift: function() {
            this.inKey = "beatjump_forward";
            this.outKey = this.inKey;
            this.input = components.Button.prototype.input;
            this.outTrigger = true;
            this.outConnect = true;
        },
        shift: function() {
            this.inKey = "beatjump_size";
            this.outKey = this.inKey;
            this.input = function(channel, control, value, status, group) {
                if (this.isPress(channel, control, value, status, group)) {
                    this.inSetValue(currentJumpSize.next());
                }
                this.send(value / 2 + 0.5); // Hacky way to get LEDs to respond properly
            };
            this.outTrigger = false;
            this.outConnect = false;
        },
    });

    // Sync Button (QML: Sync { syncNote: 8; syncHoldAction: Action.KeySync })
    // QML Sync uses default LedType (no explicit ledType) → Simple Note On
    this.syncButton = new components.SyncButton({
        midi: [0x90 + midiChannel, 0x08],
        shift: function() {
            // QML: syncHoldAction: Action.KeySync
            this.inKey = "sync_key";
        },
        unshift: function() {
            this.inKey = "sync_enabled";
        },
        output: function(value) {
            print("DBG_SYNC: ch=" + midiChannel + " val=" + value);
            // Simple Note On LED (no RGB SysEx)
            if (value > 0) {
                this.send(0x3F);  // bright
            } else {
                this.send(0x01);  // dim
            }
        },
    });

    // Cue Button (QML: cueNote=9, cueShiftAction=SetCuePoint)
    this.cueButton = new components.CueButton({
        midi: [0x90 + midiChannel, 0x09],
        input: function(channel, control, value, status, _group) {
            print("DBG_CUE: ch="+channel+" ctrl=0x"+control.toString(16)+" val="+value+" st=0x"+status.toString(16));
            components.CueButton.prototype.input.call(this, channel, control, value, status, _group);
        },
        shift: function() {
            this.inKey = "cue_set";
        },
        output: function(value) {
            print("DBG_CUE_OUT: val="+value+" ch="+midiChannel);
            // QML PlayCue uses LedType.Simple — Note On with color value
            if (value > 0) {
                this.send(0x1A);  // orange-ish (redDim=32 is close)
            } else {
                this.send(0x01);  // dim, not off
            }
        },
    });

    // Play Button
    this.playButton = new components.PlayButton({
        midi: [0x90 + midiChannel, 0x0A],
        input: function(channel, control, value, status, group) {
            print("DBG_PLAY: ch="+channel+" ctrl=0x"+control.toString(16)+" val="+value+" st=0x"+this.midi[0].toString(16));
            components.PlayButton.prototype.input.call(this, channel, control, value, status, group);
        },
        unshift: function() {
            components.PlayButton.prototype.unshift.call(this);
            this.type = components.Button.prototype.types.toggle;
        },
        shift: function() {
            this.inKey = "play_stutter";
            this.type = components.Button.prototype.types.push;
        },
        output: function(value) {
            print("DBG_PLAY_OUT: val="+value+" ch="+midiChannel);
            // QML PlayCue uses LedType.Simple
            if (value > 0) {
                this.send(0x0C);  // green
            } else {
                this.send(0x01);  // dim, not off
            }
        },
    });

    // Performance Pads
    this.padGrid = new PrimeGo.PadSection(this, midiChannel - 2);

    //this.gridEditMode = true;

    // Beatgrid edit mode
    this.gridEditButton = new components.Button({
        midi: [0x90 + midiChannel, 0x1B],
        //key: "show_beatgrid_controls",
        //group: "[Skin]",
        type: components.Button.prototype.types.toggle,
    });

    // Beatgrid shift buttons
    this.gridShiftLeft = new components.Button({
        midi: [0x90 + midiChannel, 0x19],
        key: "beats_translate_earlier",
    });
    this.gridShiftRight = new components.Button({
        midi: [0x90 + midiChannel, 0x1A],
        key: "beats_translate_later",
    });

    // Pitch Bend Buttons
    const currentRateRange = new PrimeGo.CyclingArrayView(rateRanges, 2);
    this.pitchBendUp = new components.Button({
        midi: [0x90 + midiChannel, 0x1E],
        type: components.Button.prototype.types.push,
        unshift: function() {
            this.inKey = "rate_temp_up";
            this.outKey = this.inKey;
            this.input = components.Button.prototype.input;
            this.outTrigger = true;
            this.outConnect = true;
        },
        shift: function() {
            this.inKey = "rateRange";
            this.outKey = this.inKey;
            this.input = function(channel, control, value, status, group) {
                if (this.isPress(channel, control, value, status, group)) {
                    this.inSetValue(currentRateRange.next());
                }
                this.send(value / 2 + 0.5); // Hacky way to get LEDs to respond properly
            };
            console.log("Sifted");
            this.outTrigger = false;
            this.outConnect = false;
        },
    });
    this.pitchBendDown = new components.Button({
        midi: [0x90 + midiChannel, 0x1D],
        type: components.Button.prototype.types.push,
        unshift: function() {
            this.inKey = "rate_temp_down";
            this.outKey = this.inKey;
            this.input = components.Button.prototype.input;
            this.outTrigger = true;
            this.outConnect = true;
        },
        shift: function() {
            this.inKey = "rateRange";
            this.outKey = this.inKey;
            this.input = function(channel, control, value, status, group) {
                if (this.isPress(channel, control, value, status, group)) {
                    this.inSetValue(currentRateRange.previous());
                }
                this.send(value / 2 + 0.5); // Hacky way to get LEDs to respond properly
            };
            console.log("Shifted");
            this.outTrigger = false;
            this.outConnect = false;
        },
    });

    // Tempo Fader (14-bit via XML Script-Bindings — no JS midi: to avoid conflict)
    this.tempoFader = new components.Pot({
        inKey: "rate",
        invert: false,
        inSetParameter: function(value) {
            print("DBG_PITCH: deck=" + deckNumbers + " key=" + this.inKey + " val=" + value.toFixed(4));
            sliderPosAccessors.setter(value);
            engine.setParameter(this.group, this.inKey, value);
            theDeck.takeoverLeds.trigger();
        },
    });

    const takeoverLEDValues = {
        OFF: 0,
        DIMM: 1,
        FULL: 2,
    };
    const takeoverLEDControls = {
        up: 0x35,
        center: 0x34,
        down: 0x33,
    };

    this.takeoverLeds = new components.Component({
        midi: [0x90 + midiChannel, takeoverLEDControls.center],
        outKey: "rate",
        off: 0,
        output: function(softwareSliderPosition) {
            // rate slider centered?
            this.send(softwareSliderPosition === 0 ? takeoverLEDValues.FULL : takeoverLEDValues.OFF);

            const distance2Brightness = function(distance) {
                // src/controllers/softtakeover.cpp
                // SoftTakeover::kDefaultTakeoverThreshold = 3.0 / 128;
                const takeoverThreshold = 3 / 128;
                if (distance > takeoverThreshold && distance < 0.10) {
                    return takeoverLEDValues.DIMM;
                } else if (distance >= 0.10) {
                    return takeoverLEDValues.FULL;
                } else {
                    return takeoverLEDValues.OFF;
                }
            };

            const normalizedPhysicalSliderPosition = sliderPosAccessors.getter()*2 - 1;
            const distance = Math.abs(normalizedPhysicalSliderPosition - softwareSliderPosition);
            const directionLedBrightness = distance2Brightness(distance);

            if (normalizedPhysicalSliderPosition > softwareSliderPosition) {
                midi.sendShortMsg(this.midi[0], takeoverLEDControls.up, takeoverLEDValues.OFF);
                midi.sendShortMsg(this.midi[0], takeoverLEDControls.down, directionLedBrightness);
            } else {
                midi.sendShortMsg(this.midi[0], takeoverLEDControls.down, takeoverLEDValues.OFF);
                midi.sendShortMsg(this.midi[0], takeoverLEDControls.up, directionLedBrightness);
            }
        },
    });

    // Keylock Button
    this.keylockButton = new components.Button({
        midi: [0x90 + midiChannel, 0x22],
        key: "keylock",
        type: components.Button.prototype.types.toggle,
    });

    // Vinyl Mode Button (QML: holdAction=GridCueEdit, shiftAction=SlipMode)
    // Vinyl mode is ALWAYS ON for proper jog wheel scratching.
    this.vinylButton = new components.Button({
        midi: [0x90 + midiChannel, 0x23],
        type: components.Button.prototype.types.toggle,
        outConnect: true,
        outTrigger: false,
        input: function(channel, control, value, status, _group) {
            print("DBG_VINYL_IN: ch=0x"+channel.toString(16)+" ctrl=0x"+control.toString(16)+" val="+value+" shift="+PrimeGo.shift);
            // QML actions: normal=GridCueEdit (hold), shift=SlipMode (toggle)
            if (PrimeGo.shift) {
                if (this.isPress(channel, control, value, status)) {
                    engine.setValue(theDeck.currentDeck, "slip_enabled",
                        engine.getValue(theDeck.currentDeck, "slip_enabled") > 0 ? 0 : 1);
                }
            }
        },
        output: function() {
            print("DBG_VINYL_OUT: shift="+PrimeGo.shift);
            if (PrimeGo.shift) {
                this.send(0x09);  // yellow = slip mode via shift
            } else {
                this.send(0x40);  // bright red = vinyl mode always on
            }
        },
        connect: function() {
            components.Button.prototype.connect.call(this);
            // outKey is undefined, so parent connect makes no connection.
            // Explicitly light the LED on connect.
            print("DBG_VINYL_CONNECT: midi=0x"+this.midi[0].toString(16)+" n=0x"+this.midi[1].toString(16));
            this.send(0x03);
        },
    });

    // Jog Wheel — Prime Go (QML: touchNote=33/0x21, ccUpper=0x37, ccLower=0x4D)
    this.jogWheel = new components.JogWheelBasic({
        deck: script.deckFromGroup(this.currentDeck),
        midi: [0x92 + (midiChannel - 2), 0x21],  // for isPress in inputTouch
        inputTouch: function(channel, control, value, status, group) {
            // Guard against uninitialized deck (NaN or 0) to prevent
            // engine.scratchEnable(NaN) → [Channel0] scratch2_enable flood
            if (isNaN(this.deck) || this.deck < 1) {
                print("DBG_JOG_TOUCH: SKIPPED — deck=" + this.deck + " (not initialized)");
                return;
            }
            print("DBG_JOG_TOUCH: ch="+channel+" ctrl=0x"+control.toString(16)+" val="+value+" st=0x"+status.toString(16)+" midi0=0x"+this.midi[0].toString(16)+" vinylMode="+theDeck.jogWheel.vinylMode+" deck="+this.deck+" group="+this.group);
            return components.JogWheelBasic.prototype.inputTouch.call(this, channel, control, value, status, group);
        },
        wheelResolution: 1000,
        alpha: 1/8,
        beta: 1/8/32,
        rpm: 33 + 1/3,
        // Instead of relative movements between this and the last position,
        // the controller reports the absolute position of the wheel with
        // 14-bit precision. Because of that, we need to reconstruct the value
        // and then transform it into the relative directions expected by Mixxx.
        inputWheelMSB: function(_channel, _control, value, _status, _group) {
            this.wheelMSB = value;
        },
        inputWheelLSB: function(channel, control, value, status, group) {
            this.inputWheel(channel, control, (this.wheelMSB << 7) + value, status, group);
        },
        previousPosition: null,
        wrappingValue: Math.pow(2, 14),
        relativeFromAbsolute: function(value) {
            // The first value of the controller will probably be random
            // and thus we just have to swallow it until we have the second value
            // to find the difference
            if (this.previousPosition === null) {
                this.previousPosition = value;
                return 0;
            }
            // This finds the shortest distance between the current value
            // and the last one, and preserves the orientation
            const delta = value - this.previousPosition;
            let remainder = ((delta % this.wrappingValue) + this.wrappingValue) % this.wrappingValue;
            //let remainder = script.posMod(delta, this.wrappingValue);
            if (remainder * 2 > this.wrappingValue) {
                remainder -= this.wrappingValue;
            }
            this.previousPosition = value;
            return remainder;
        },
        jogScale: function(val) {
            // wheelSensitivity is user-configurable, see top of file.
            return val * wheelSensitivity;
        },
        inputWheel: function(channel, control, value, _status, _group) {
            value = this.relativeFromAbsolute(value);
            if (engine.isScratching(this.deck)) {
                engine.scratchTick(this.deck, value);
            } else {
                this.inSetValue(this.jogScale(value));
            }
        },
        connect: function() {
            // Force deck from group BEFORE parent connect, since 
            // script.channelRegEx can produce NaN on this MIXXX build.
            if (this.group) {
                var match = /\[Channel(\d+)\]/.exec(this.group);
                if (match) {
                    this.deck = parseInt(match[1], 10);
                }
            }
            var prevDeck = this.deck;
            components.JogWheelBasic.prototype.connect.call(this);
            // Re-force deck after parent may have overwritten with NaN
            if (isNaN(this.deck) && this.group) {
                var match2 = /\[Channel(\d+)\]/.exec(this.group);
                if (match2) {
                    this.deck = parseInt(match2[1], 10);
                }
            }
            print("DBG_JOG_CONNECT: prevDeck="+prevDeck+" deck="+this.deck+" group="+this.group);
        },
    });

    // No jog wheel LED on Prime Go — touchNote 33 (0x21) is capacitive sense only

    // Slip Mode Button
    this.slipButton = new components.Button({
        midi: [0x90 + midiChannel, 0x24],
        key: "slip_enabled",
        type: components.Button.prototype.types.toggle,
    });

    // Loop Encoder (QML: turnCC: 32, loopInactiveShiftTurnAction: Action.BeatJump)
    const currentLoopSize = new PrimeGo.CyclingArrayView(loopSizes, 6);
    this.loopEncoder = new components.Pot({
        midi: [0x90 + midiChannel, 0x20],
        key: "beatloop_size",
        input: function(channel, control, value, _status, _group) {
            if (PrimeGo.shift) {
                // QML: loopInactiveShiftTurnAction: Action.BeatJump
                if (value === 0x01) {
                    engine.setValue(theDeck.currentDeck, "beatjump_forward", 1);
                } else if (value === 0x7f) {
                    engine.setValue(theDeck.currentDeck, "beatjump_backward", 1);
                }
            } else {
                if (value === 0x01) {
                    this.inSetValue(currentLoopSize.next());
                } else if (value === 0x7f) {
                    this.inSetValue(currentLoopSize.previous());
                }
            }
        },
    });

    // Loop Encoder Button (QML: pushNote: 39, shiftPushAction: Action.IncreaseBeatJumpSize)
    this.beatLoopTrigger = new components.Button({
        midi: [0x90 + midiChannel, 0x27],
        type: components.Button.prototype.types.push,
        shift: function() {
            // QML: shiftPushAction: Action.IncreaseBeatJumpSize
            this.input = function(channel, control, value, status, _group) {
                if (this.isPress(channel, control, value, status)) {
                    currentJumpSize.next();
                }
            };
        },
        unshift: function() {
            this.inKey = "beatloop_activate";
            this.outKey = this.inKey;
            this.input = components.Button.prototype.input;
        },
    });

    // Loop In Button
    this.loopInButton = new components.Button({
        midi: [0x90 + midiChannel, 0x25],
        key: "loop_in",
    });

    // Loop Out Button
    this.loopOutButton = new components.Button({
        midi: [0x90 + midiChannel, 0x26],
        key: "loop_out",
    });

    // Load Buttons (QML: LedType.Simple — Note On with velocity=color)
    this.deckLoad = new components.Button({
        midi: [0x9F, midiChannel - 1],  // loadNote=1 for ch2, 2 for ch3
        key: "LoadSelectedTrack",
        outKey: "track_loaded",
        shift: function() {
            this.inKey = "eject";
        },
        unshift: function() {
            this.inKey = "LoadSelectedTrack";
        },
        output: function(value) {
            if (value > 0) {
                this.send(0x0C);  // green = track loaded
            } else {
                this.send(0x01);  // dim = empty
            }
        },
    });

    this.reconnectComponents(function(c) {
        if (c.group === undefined) {
            c.group = this.currentDeck;
        }
    });

};

PrimeGo.Deck.prototype = new components.Deck();

// Shift button on global channel 15 (0x9F), note 8 (QML: JP11_Controller_Assignments.qml)
// ALSO spying on ch2/ch3 note 0x1C to find what hardware actually sends
PrimeGo.shiftButton = new components.Button({
    midi: [0x9F, 0x08],
    input: function(channel, control, value, status, group) {
        print("DBG_SHIFT: ch=0x" + channel.toString(16) + " ctrl=0x" + control.toString(16) + " val=" + value + " status=0x" + status.toString(16));
        PrimeGo.shiftState(15, control, value);
    }
});

PrimeGo.shift = false;
PrimeGo.shiftState = function(channel, control, value) {
    print("DBG_SHIFT: ch=0x" + channel.toString(16) + " ctrl=0x" + control.toString(16) + " val=" + value);
    PrimeGo.shift = value === 0x7F;
    if (PrimeGo.shift) {
        midi.sendShortMsg(0x90 + channel, control, 0x02);
        PrimeGo.leftDeck.shift();
        PrimeGo.rightDeck.shift();
        //PrimeGo.effectBank[0].shift();
        //PrimeGo.effectBank[1].shift();
        PrimeGo.leftDeck.reconnectComponents();
        PrimeGo.rightDeck.reconnectComponents();
        // Refresh vinyl LEDs (no outKey, so not auto-triggered)
        PrimeGo.leftDeck.vinylButton.output();
        PrimeGo.rightDeck.vinylButton.output();
    } else {
        midi.sendShortMsg(0x90 + channel, control, 0x01);
        PrimeGo.leftDeck.unshift();
        PrimeGo.rightDeck.unshift();
        //PrimeGo.effectBank[0].unshift();
        //PrimeGo.effectBank[1].unshift();
        PrimeGo.leftDeck.reconnectComponents();
        PrimeGo.rightDeck.reconnectComponents();
        // Refresh vinyl LEDs
        PrimeGo.leftDeck.vinylButton.output();
        PrimeGo.rightDeck.vinylButton.output();
    }
};

//========== PERFORMANCE PADS ==========//

// Access the appropriate mode-select pad without remembering MIDI values
PrimeGo.padMode = {
    HOTCUE: 0x0B,
    LOOP: 0x0C,
    ROLL: 0x0D,
    SLICER: 0x0E,
};

PrimeGo.PadSection = function(deck, offset) {
    components.ComponentContainer.call(this);
    const theContainer = this;

    // Create component containers for each pad mode
    const modes = new components.ComponentContainer({
        "hotcue": new PrimeGo.WrappingArrayView([new PrimeGo.hotcueMode(deck, offset)], 0),
        "loop": new PrimeGo.WrappingArrayView([new PrimeGo.savedLoopMode(deck, offset), new PrimeGo.autoloopMode(deck, offset)], 0),
        "roll": new PrimeGo.WrappingArrayView([new PrimeGo.rollMode(deck, offset), new PrimeGo.samplerMode(deck, offset)], 0),
        "slicer": new PrimeGo.WrappingArrayView([new PrimeGo.extraCueModeA(deck, offset), new PrimeGo.extraCueModeB(deck, offset)], 0),
        "rollShift": new PrimeGo.WrappingArrayView([new PrimeGo.samplerMode(deck, offset)], 0),
    });

    modes.forEachComponent(c => c.disconnect());

    const controlToPadMode = control => {
        // If a pad selector button has multiple modes, go to the first mode
        // by default. Otherwise, go to the next mode in that button's list.
        const nextPadMode = (a) => {
            console.log(a);
            if (a.indexable.includes(this.currentMode)) {
                return a.next();
            } else {
                a.index = 0;
                return a.current();
            }
        };

        let mode;

        switch (control) {
        case PrimeGo.padMode.HOTCUE:
            mode = nextPadMode(modes.hotcue);
            break;
        case PrimeGo.padMode.LOOP:
            mode = nextPadMode(modes.loop);
            break;
        case PrimeGo.padMode.ROLL:
            if (PrimeGo.shift) {
                mode = nextPadMode(modes.rollShift);
            } else {
                mode = nextPadMode(modes.roll);
            }
            break;
        case PrimeGo.padMode.SLICER:
            mode = nextPadMode(modes.slicer);
            break;
        }

        return mode;
    };

    this.offset = offset;

    this.padModeSelectLeds = new components.Component({
        trigger: function() {
            // QML PerformanceModes uses LedType.RGB — must send SysEx RGB
            var ch = 2 + offset; // deck MIDI channel
            for (var modeLayers in modes) {
                if (!modes.hasOwnProperty(modeLayers)) continue;
                var mode = modes[modeLayers].current();
                var rgb = PrimeGo.rgbCodeToSysex(
                    theContainer.currentMode === mode ? mode.colourOn : mode.colourOff
                );
                sendSysexRGB(ch, mode.ledControl, rgb[0], rgb[1], rgb[2]);
            }
        },
    }, false);

    // Function for switching between pad modes
    this.setPadMode = function(control) {
        const newMode = controlToPadMode(control);

        // Exit early if requested mode is already active or unavailable
        if (newMode === this.currentMode || newMode === undefined) {
            return;
        }

        // Connect pads to new mode and trigger LED refresh
        // (pads are always outConnect:true, so we only need trigger)
        newMode.forEachComponent(function(component) {
            component.trigger();
        });

        // Assign mode select buttons in XML file
        this.padModeButtonPressed = function(channel, control, value, _status, _group) {
            print("DBG_PAD_MODE: channel="+channel+" control=0x"+control.toString(16)+" value="+value+" status="+_status);
            if (value) {
                this.setPadMode(control);
            }
        };

        this.currentMode = newMode;
        console.log(this.currentMode);

        theContainer.padModeSelectLeds.trigger();
    };

    // Listen for track loads to refresh pad LEDs (hotcue state changes, etc.)
    this.trackLoadedListener = new components.Component({
        group: deck.currentDeck,
        outKey: "track_loaded",
        outConnect: true,
        output: function() {
            if (theContainer.currentMode) {
                theContainer.currentMode.forEachComponent(function(c) { c.trigger(); });
            }
        },
    });

    // Start in Hotcue mode
    this.setPadMode(PrimeGo.padMode.HOTCUE);

};

PrimeGo.PadSection.prototype = Object.create(components.ComponentContainer.prototype);

// Worry about parameter buttons later
//PrimeGo.PadSection.prototype.paramButtonPressed = function(channel, control, value, status, group) {};

// Assign pads mapped in XML file
PrimeGo.PadSection.prototype.performancePad = function(channel, control, value, status, group) {
    const i = (control - 0x0E);
    print("DBG_PERF_PAD: channel="+channel+" padIdx="+i+" control=0x"+control.toString(16)+" value="+value+" status="+status);
    this.currentMode.pads[i].input(channel, control, value, status, group);
};

// HOTCUE MODE — each pad has distinct color like Prime Go standalone
PrimeGo.hotcueMode = function(deck, offset) {
    components.ComponentContainer.call(this);
    this.ledControl = PrimeGo.padMode.HOTCUE;
    this.colourOn = PrimeGo.rgbCode.green; // mode select button color
    this.colourOff = PrimeGo.rgbCode.greenDark;
    const padColoursOn = [
        PrimeGo.rgbCodeSysex.red,
        PrimeGo.rgbCodeSysex.orange,
        PrimeGo.rgbCodeSysex.yellow,
        PrimeGo.rgbCodeSysex.green,
        PrimeGo.rgbCodeSysex.aqua,
        PrimeGo.rgbCodeSysex.blue,
        PrimeGo.rgbCodeSysex.violet,
        PrimeGo.rgbCodeSysex.magenta,
    ];
    const padColoursOff = [
        PrimeGo.rgbCodeSysex.redDark,
        PrimeGo.rgbCodeSysex.orangeDark,
        PrimeGo.rgbCodeSysex.yellowDark,
        PrimeGo.rgbCodeSysex.greenDark,
        PrimeGo.rgbCodeSysex.aquaDark,
        PrimeGo.rgbCodeSysex.blueDark,
        PrimeGo.rgbCodeSysex.violetDark,
        PrimeGo.rgbCodeSysex.magentaDark,
    ];
    this.pads = new components.ComponentContainer();
    for (let i = 1; i <= 8; i++) {
        const padIndex = i;  // capture for closure
        this.pads[padIndex] = new components.HotcueButton({
            number: padIndex,
            group: deck.currentDeck,
            midi: [0x92 + offset, 0x0E + padIndex],
            on: padColoursOn[padIndex-1],
            off: padColoursOff[padIndex-1],
            sendRGB: function(color_obj) {
                const msg = [0xf0, 0x00, 0x02, 0x0b, 0x7f, 0x0C, 0x03, 0x00, 0x05, 0x02 + offset, 0x0E + padIndex,
                    color_obj.red>>1, color_obj.green>>1, color_obj.blue>>1, 0xf7];
                midi.sendSysexMsg(msg, msg.length);
            },
            output: function(value) {
                var outval = this.outValueScale(value);
                if (outval > 0 && this.colorKey !== undefined) {
                    var colorCode = engine.getValue(this.group, this.colorKey);
                    if (colorCode !== undefined && colorCode >= 0) {
                        this.sendRGB(colorCodeToObject(colorCode));
                        return;
                    }
                }
                var off = this.off;
                this.sendRGB({red: off[0], green: off[1], blue: off[2]});
            },
            outConnect: true,
        });
    }
    // Also connect to color keys so hotcue LEDs update immediately when color is set
    for (let j = 1; j <= 8; j++) {
        (function(btn) {
            engine.makeConnection(btn.group, btn.colorKey, function() {
                if (btn.inGetValue() > 0) btn.output(1.0);
            });
        })(this.pads[j]);
    }
};
PrimeGo.hotcueMode.prototype = Object.create(components.ComponentContainer.prototype);

// SAVED LOOP MODE — distinct colors per pad (hotcues 9-16)
PrimeGo.savedLoopMode = function(deck, offset) {
    components.ComponentContainer.call(this);
    this.ledControl = PrimeGo.padMode.LOOP;
    this.colourOn = PrimeGo.rgbCode.green;
    this.colourOff = PrimeGo.rgbCode.greenDark;
    const padColoursOn = [
        PrimeGo.rgbCodeSysex.red,
        PrimeGo.rgbCodeSysex.orange,
        PrimeGo.rgbCodeSysex.yellow,
        PrimeGo.rgbCodeSysex.green,
        PrimeGo.rgbCodeSysex.aqua,
        PrimeGo.rgbCodeSysex.blue,
        PrimeGo.rgbCodeSysex.violet,
        PrimeGo.rgbCodeSysex.magenta,
    ];
    const padColoursOff = [
        PrimeGo.rgbCodeSysex.redDark,
        PrimeGo.rgbCodeSysex.orangeDark,
        PrimeGo.rgbCodeSysex.yellowDark,
        PrimeGo.rgbCodeSysex.greenDark,
        PrimeGo.rgbCodeSysex.aquaDark,
        PrimeGo.rgbCodeSysex.blueDark,
        PrimeGo.rgbCodeSysex.violetDark,
        PrimeGo.rgbCodeSysex.magentaDark,
    ];
    this.pads = new components.ComponentContainer();
    for (let i = 1; i <= 8; i++) {
        const padIndex = i;  // capture for closure
        this.pads[padIndex] = new components.HotcueButton({
            number: padIndex + 8,
            group: deck.currentDeck,
            midi: [0x92 + offset, 0x0E + padIndex],
            on: padColoursOn[padIndex-1],
            off: padColoursOff[padIndex-1],
            sendRGB: function(color_obj) {
                const msg = [0xf0, 0x00, 0x02, 0x0b, 0x7f, 0x0C, 0x03, 0x00, 0x05, 0x02 + offset, 0x0E + padIndex,
                    color_obj.red>>1, color_obj.green>>1, color_obj.blue>>1, 0xf7];
                midi.sendSysexMsg(msg, msg.length);
            },
            output: function(value) {
                var outval = this.outValueScale(value);
                if (outval > 0 && this.colorKey !== undefined) {
                    var colorCode = engine.getValue(this.group, this.colorKey);
                    if (colorCode !== undefined && colorCode >= 0) {
                        this.sendRGB(colorCodeToObject(colorCode));
                        return;
                    }
                }
                var off = this.off;
                this.sendRGB({red: off[0], green: off[1], blue: off[2]});
            },
            outConnect: true,
        });
    }
    // Also connect to color keys so hotcue LEDs update immediately when color is set
    for (let j = 1; j <= 8; j++) {
        (function(btn) {
            engine.makeConnection(btn.group, btn.colorKey, function() {
                if (btn.inGetValue() > 0) btn.output(1.0);
            });
        })(this.pads[j]);
    }
};
PrimeGo.savedLoopMode.prototype = Object.create(components.ComponentContainer.prototype);

// AUTOLOOP MODE
PrimeGo.autoloopMode = function(deck, offset) {
    components.ComponentContainer.call(this);
    this.ledControl = PrimeGo.padMode.LOOP;
    this.colourOn = PrimeGo.rgbCode.green;
    this.colourOff = PrimeGo.rgbCode.greenDark;
    this.pads = new components.ComponentContainer();
    this.loopSize = [0.0625, 0.125, 0.25, 0.5, 1, 2, 4, 8];
    for (let i = 1; i <= 8; i++) {
        const padIndex = i;  // capture for closure
        const loopSize = (this.loopSize[padIndex - 1]);
        this.pads[padIndex] = new components.Button({
            midi: [0x92 + offset, 0x0E + padIndex],
            group: deck.currentDeck,
            outKey: "beatloop_" + loopSize + "_enabled",
            inKey: "beatloop_" + loopSize + "_toggle",
            on: PrimeGo.rgbCode.white,
            off: PrimeGo.rgbCode.greenDark,
            outConnect: true,
            sendRGB: function(color_obj) {
                const msg = [0xf0, 0x00, 0x02, 0x0b, 0x7f, 0x0C, 0x03, 0x00, 0x05,
                    0x02 + offset, 0x0E + padIndex, color_obj.red>>1, color_obj.green>>1, color_obj.blue>>1, 0xf7];
                midi.sendSysexMsg(msg, msg.length);
            },
            output: function(value) {
                var outval = this.outValueScale(value);
                var rgb = outval > 0 ? PrimeGo.rgbCodeToSysex(this.on) : PrimeGo.rgbCodeToSysex(this.off);
                this.sendRGB({red: rgb[0], green: rgb[1], blue: rgb[2]});
            },
        });
    }
};
PrimeGo.autoloopMode.prototype = Object.create(components.ComponentContainer.prototype);

// ROLL MODE
PrimeGo.rollMode = function(deck, offset) {
    components.ComponentContainer.call(this);
    this.ledControl = PrimeGo.padMode.ROLL;
    this.colourOn = PrimeGo.rgbCode.green;
    this.colourOff = PrimeGo.rgbCode.greenDark;
    this.pads = new components.ComponentContainer();
    // NOTE: The Prime Go's standalone Roll mode includes triplet loop rolls, but
    //       Mixxx doesn't support those yet.
    this.rollSize = [0.0625, 0.125, 0.25, 0.5, 1, 2, 4, 8];
    for (let i = 1; i <= 8; i++) {
        const padIndex = i;  // capture for closure
        const rollSize = (this.rollSize[padIndex - 1]);
        this.pads[padIndex] = new components.Button({
            midi: [0x92 + offset, 0x0E + padIndex],
            group: deck.currentDeck,
            outKey: "beatloop_" + rollSize + "_enabled",
            inKey: "beatlooproll_" + rollSize + "_activate",
            on: PrimeGo.rgbCode.white,
            off: PrimeGo.rgbCode.green,
            outConnect: true,
            sendRGB: function(color_obj) {
                const msg = [0xf0, 0x00, 0x02, 0x0b, 0x7f, 0x0C, 0x03, 0x00, 0x05,
                    0x02 + offset, 0x0E + padIndex, color_obj.red>>1, color_obj.green>>1, color_obj.blue>>1, 0xf7];
                midi.sendSysexMsg(msg, msg.length);
            },
            output: function(value) {
                var outval = this.outValueScale(value);
                var rgb = outval > 0 ? PrimeGo.rgbCodeToSysex(this.on) : PrimeGo.rgbCodeToSysex(this.off);
                this.sendRGB({red: rgb[0], green: rgb[1], blue: rgb[2]});
            },
        });
        if (padIndex % 2 === 0 && padIndex < 8) {
            this.pads[padIndex].off = 0x23;
        }
    }
};
PrimeGo.rollMode.prototype = Object.create(components.ComponentContainer.prototype);

// SAMPLER MODE
PrimeGo.samplerMode = function(deck, offset) {
    components.ComponentContainer.call(this);
    this.ledControl = PrimeGo.padMode.ROLL;
    this.colourOn = PrimeGo.rgbCode.green;
    this.colourOff = PrimeGo.rgbCode.greenDark;
    this.pads = new components.ComponentContainer();
    const colourArray = [PrimeGo.rgbCode.yellow, PrimeGo.rgbCode.orange, PrimeGo.rgbCode.purple, PrimeGo.rgbCode.red,
        PrimeGo.rgbCode.green, PrimeGo.rgbCode.teal, PrimeGo.rgbCode.cyan, PrimeGo.rgbCode.blue];
    for (let i = 1; i <= 8; i++) {
        const padIndex = i;  // capture for closure
        this.pads[padIndex] = new components.SamplerButton({
            number: padIndex,
            midi: [0x92 + offset, 0x0E + padIndex],
            on: colourArray[padIndex - 1],
            off: PrimeGo.rgbCode.greenDark,
            outConnect: true,
            sendRGB: function(color_obj) {
                const msg = [0xf0, 0x00, 0x02, 0x0b, 0x7f, 0x0C, 0x03, 0x00, 0x05,
                    0x02 + offset, 0x0E + padIndex, color_obj.red>>1, color_obj.green>>1, color_obj.blue>>1, 0xf7];
                midi.sendSysexMsg(msg, msg.length);
            },
            output: function(value) {
                var outval = this.outValueScale(value);
                var rgb = outval > 0 ? PrimeGo.rgbCodeToSysex(this.on) : PrimeGo.rgbCodeToSysex(this.off);
                this.sendRGB({red: rgb[0], green: rgb[1], blue: rgb[2]});
            },
        });
    }
};
PrimeGo.samplerMode.prototype = Object.create(components.ComponentContainer.prototype);

/*
 * TODO: Add slicer mode
 *
 * Thanks to the new controls added in 2.4, I believe I can create a custom
 * pad mode that behaves just like Slicer Mode in the Prime Go's standalone
 * mode. It would involve setting 8 hotcues across the next 8 beats on the
 * beatgrid, then clearing and re-setting those hotcues every 8 beats.
 * Slicer Loop mode could work in a similar way, but instead of re-setting
 * the hotcues every 8 beats, I just set the 8 hotcues once, then make an
 * 8-beat loop starting from the first new hotcue, and activate a 1-beat
 * loop roll whenever one of the hotcue pads get pressed. I need to
 * familiarize myself with these new Mixxx Controls first, but I'm pretty
 * sure it's possible. Hopefully this can then be implemented in
 * ComponentsJS so that it can easily be added to other hardware in the
 * future.
 *
 * For now, I'll just make the Slicer pad mode control hotcues 17 to 24,
 * like how Loop mode controls hotcues 9 to 16 for the time-being.
 */

PrimeGo.extraCueModeA = function(deck, offset) {
    components.ComponentContainer.call(this);
    this.ledControl = PrimeGo.padMode.SLICER;
    this.colourOn = PrimeGo.rgbCode.green;
    this.colourOff = PrimeGo.rgbCode.greenDark;
    this.pads = new components.ComponentContainer();
    for (let i = 1; i <= 8; i++) {
        const padIndex = i;  // capture for closure
        this.pads[padIndex] = new components.HotcueButton({
            number: padIndex + 16,
            group: deck.currentDeck,
            midi: [0x92 + offset, 0x0E + padIndex],
            on: this.colourOn,
            off: this.colourOff,
            outConnect: true,
            sendRGB: function(color_obj) {
                const msg = [0xf0, 0x00, 0x02, 0x0b, 0x7f, 0x0C, 0x03, 0x00, 0x05,
                    0x02 + offset, 0x0E + padIndex, color_obj.red>>1, color_obj.green>>1, color_obj.blue>>1, 0xf7];
                midi.sendSysexMsg(msg, msg.length);
            },
            output: function(value) {
                var outval = this.outValueScale(value);
                if (outval > 0 && this.colorKey !== undefined) {
                    var colorCode = engine.getValue(this.group, this.colorKey);
                    if (colorCode !== undefined && colorCode >= 0) {
                        this.sendRGB(colorCodeToObject(colorCode));
                        return;
                    }
                }
                var rgb = PrimeGo.rgbCodeToSysex(this.off);
                this.sendRGB({red: rgb[0], green: rgb[1], blue: rgb[2]});
            },
        });
    }
    // Also connect to color keys so hotcue LEDs update immediately when color is set
    for (let j = 1; j <= 8; j++) {
        (function(btn) {
            engine.makeConnection(btn.group, btn.colorKey, function() {
                if (btn.inGetValue() > 0) btn.output(1.0);
            });
        })(this.pads[j]);
    }
};
PrimeGo.extraCueModeA.prototype = Object.create(components.ComponentContainer.prototype);

PrimeGo.extraCueModeB = function(deck, offset) {
    components.ComponentContainer.call(this);
    this.ledControl = PrimeGo.padMode.SLICER;
    this.colourOn = PrimeGo.rgbCode.green;
    this.colourOff = PrimeGo.rgbCode.greenDark;
    this.pads = new components.ComponentContainer();
    for (let i = 1; i <= 8; i++) {
        const padIndex = i;  // capture for closure
        this.pads[padIndex] = new components.HotcueButton({
            number: padIndex + 24,
            group: deck.currentDeck,
            midi: [0x92 + offset, 0x0E + padIndex],
            on: this.colourOn,
            off: this.colourOff,
            outConnect: true,
            sendRGB: function(color_obj) {
                const msg = [0xf0, 0x00, 0x02, 0x0b, 0x7f, 0x0C, 0x03, 0x00, 0x05,
                    0x02 + offset, 0x0E + padIndex, color_obj.red>>1, color_obj.green>>1, color_obj.blue>>1, 0xf7];
                midi.sendSysexMsg(msg, msg.length);
            },
            output: function(value) {
                var outval = this.outValueScale(value);
                if (outval > 0 && this.colorKey !== undefined) {
                    var colorCode = engine.getValue(this.group, this.colorKey);
                    if (colorCode !== undefined && colorCode >= 0) {
                        this.sendRGB(colorCodeToObject(colorCode));
                        return;
                    }
                }
                var rgb = PrimeGo.rgbCodeToSysex(this.off);
                this.sendRGB({red: rgb[0], green: rgb[1], blue: rgb[2]});
            },
        });
    }
    // Also connect to color keys so hotcue LEDs update immediately when color is set
    for (let j = 1; j <= 8; j++) {
        (function(btn) {
            engine.makeConnection(btn.group, btn.colorKey, function() {
                if (btn.inGetValue() > 0) btn.output(1.0);
            });
        })(this.pads[j]);
    }
};
PrimeGo.extraCueModeB.prototype = Object.create(components.ComponentContainer.prototype);
