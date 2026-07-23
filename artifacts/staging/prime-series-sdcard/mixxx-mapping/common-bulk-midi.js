midi = new Object();

midi.sendShortMsg = function(status, a, b) {
    controller.send([status, a, b], 3);
}

midi.sendSysexMsg = function(data, length) {
    controller.send(data, length);
}
