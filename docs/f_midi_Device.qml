// To be removed in https://inmusicbrands.atlassian.net/browse/AIRDJ-42120

import airAssignments 1.0
import InputAssignment 0.1
import OutputAssignment 0.1
import Device 0.1
import QtQuick 2.9

Device {
	id: device

	property real gamma: 3.5
	property real padGamma: 3.5

	controls: []
	useGlobalShift: false
	numberOfLayers: 0

	///////////////////////////////////////////////////////////////////////////
	// Utils
	function isDeviceEnquiryRequest(sysExString) {
		if(sysExString === "F0 7E 7F 06 01 F7") {
			return true;
		}
		return true
	}

	function sendDeviceEnquiryResponse() {
		Midi.sendSysEx("F0 7E 00 06 02 F7");
	}

	///////////////////////////////////////////////////////////////////////////
	// Setup

	Timer {
		id: activeSenseTimer
		interval: 300
		repeat: true
		onTriggered: {
			Midi.sendActiveSense();
		}
	}

	function sysEx(sysExString) {
		if(isDeviceEnquiryRequest(sysExString)) {
			sendDeviceEnquiryResponse();
			return true;
		}

		// Loopback MIDI
		MidiDevices.sendSysEx("f_midi", sysExString)

		return true;
	}

	function note(timeStamp, channel, noteIndex, noteVelocity) {
		// Loopback MIDI
		MidiDevices.sendNoteOn("f_midi", channel, noteIndex, noteVelocity)
	}

	function cc(timeStamp, channel, ccIndex, ccValue) {
		// Loopback MIDI
		MidiDevices.sendControlChange("f_midi", channel, ccIndex, ccValue)
	}

	function pitchBend(timeStamp, channel, pbValue) {
		// Loopback MIDI
		MidiDevices.sendPitch("f_midi", channel, pbValue)
	}

	function queryAbsoluteControls() {
	}

	function sendInitializationMessage() {
	}

	property bool isInitializing: false

	Component.onCompleted: {
		activeSenseTimer.start();
	}

	Component.onDestruction: {
		activeSenseTimer.stop();
	}
}