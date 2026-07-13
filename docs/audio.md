# Audio Architecture — Denon Prime Go + MIXXX

"Yes, routing Mixxx directly through **ALSA (Advanced Linux Sound Architecture)** is the absolute best—and essentially the only—way to wire the audio output for a professional, "native-grade" deployment on Denon Prime hardware. 

Here is a detailed breakdown of why this is the optimal strategy and how to execute it:

## 1. The OS Architecture Demands Direct ALSA Routing

Engine OS is a highly optimized, stripped-down Buildroot Linux environment. To conserve system resources and eliminate latency, the operating system completely omits heavy intermediary desktop audio servers (such as PulseAudio, JACK, or PipeWire). Instead, the system natively relies on `alsa-utils` (version 1.2.4) to handle low-level audio driver management and configuration directly.

## 2. Leveraging the Dedicated Hardware Signal Chain

By wiring Mixxx directly to ALSA, you take full advantage of the hardware's specialized audio design. The main Rockchip RK3288 processor does not handle the analog conversion; instead, ALSA routes the raw digital audio from Mixxx over an internal USB 2.0 bus directly to a dedicated XMOS controller (XS1-U6A-64-FB96). The XMOS chip then feeds the audio into professional-grade Asahi Kasei (AKM) converters—specifically the AK4621 CODEC for main inputs/outputs and the AK4413 DAC for secondary channels. This ensures the highest possible dynamic range and fidelity.

## 3. Execution: How to Wire Mixxx to ALSA

To properly connect Mixxx to these physical outputs, you must configure your deployment using the following steps:

### Release the ALSA Hardware Locks

By default, the proprietary Engine OS DJ application (internally codenamed "Planck") takes exclusive control over the ALSA interfaces. Before Mixxx can output any sound, you must kill the native UI by executing `systemctl stop engine` to release these hardware locks.

### Direct Device Mapping

As noted regarding hardware spoofing, proprietary inMusic apps hardcode their ALSA device targets (sometimes requiring hex edits to change strings like `HV01` to `HG02`). Because Mixxx is an open-source Qt/C++ application, you can bypass this headache completely. You simply configure Mixxx's audio backend to directly target the physical ALSA device identifiers (e.g., `hw:0,0`, `hw:0,1`) exposed by the XMOS controller. This allows you to individually map Mixxx's virtual decks to the physical Master, Booth, and Headphone DACs.

### Buffer Tuning & CPU Shielding

Denon Prime units run a custom Linux kernel heavily modified with the `PREEMPT_RT` patchset, which makes the kernel fully preemptible so real-time audio threads are never interrupted. To hit the project's strict requirement of **<5ms audio latency**, Mixxx's ALSA backend must be configured for a minimal buffer size. Furthermore, you must launch Mixxx using a bash wrapper script that implements **CPU shielding**. This guarantees that Mixxx's audio threads are locked to the ARM Cortex-A17 cores with absolute priority, preventing any system background tasks from causing audio dropouts during a live mix.

## Device Audio Hardware

```
Sound cards on Prime Go:
  card 0 [Surface] : USB-Audio - PRIME GO Control Surface
                     Denon DJ PRIME GO Control Surface at usb-ff540000.usb-1, full speed
  card 1 [JP11]    : JP11 - JP11
                     JP11
```

- **Card 0 (Surface)**: USB control surface — handles MIDI/HID communication with jog wheels, buttons, faders. Not for audio output.
- **Card 1 (JP11)**: Main XMOS audio interface — AK4621 CODEC + AK4413 DAC. Use `hw:1,0` for ALSA device targeting in MIXXX.

## Key ALSA Commands

```bash
# List all sound cards
cat /proc/asound/cards
aplay -l
aplay -L

# List PCM devices for JP11
aplay -D hw:JP11 --list-pcms

# Test audio output (be careful with volume!)
speaker-test -D hw:JP11 -c 2 -t sine -f 440

# Check ALSA controls/mixer
amixer -c JP11 contents
amixer -c JP11 controls
```

## PortAudio — Assertion Fix (NDEBUG)

The Buildroot portaudio package builds a debug version (`V19.7.0-devel`) with all
C `assert()` calls active. During ALSA device enumeration, PortAudio's `GropeDevice()`
probes plugin PCMs that return 0 channels on the JP11 hardware, triggering
`assert(maxChans > 0)` → SIGABRT → crash.

**Fix**: Add `-DNDEBUG` to PortAudio's CFLAGS in `package/portaudio/portaudio.mk`
via a post-configure hook. This disables all assertions in `pa_linux_alsa.c`.
See `patches/portaudio-ndebug.mk` for the full modified file.

**Verification**: A standalone test (`minipa_arm`, built from `test/minipa.c`)
calls `Pa_Initialize()` + `Pa_GetDeviceCount()` and confirms:
- 4 devices found
- JP11: PCM inmusic,jp11-audio-codec-0 (hw:1,0) — 2 in, 4 out

### Known Issue — Mixxx Startup Crash Regression

After the PortAudio NDEBUG fix, Mixxx crashes during Qt initialization (before
`main()` — during dynamic linker constructor phase). The crash is NOT caused by
PortAudio (standalone test works, removing PortAudio just changes the error).
Mixxx previously launched successfully with GUI (see `mixxx-now.log` at 21:37).

Suspected trigger: A change in the SD card bundle (Qt plugin, library version
mismatch, or Mali integration) deployed alongside the PortAudio rebuild.

### soundconfig.xml — Bypassing Enumeration

If PortAudio enumeration remains problematic, Mixxx can skip it entirely by
providing a pre-configured `soundconfig.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<SoundManagerConfig>
  <SoundDevice name="JP11: PCM inmusic,jp11-audio-codec-0 (hw:1,0)" api="ALSA">
    <output_channels>4</output_channels>
    <sample_rate>44100</sample_rate>
  </SoundDevice>
</SoundManagerConfig>
```

Place at `/media/az01-internal/mixxx/settings/soundconfig.xml` — Mixxx will
use this device directly without scanning ALSA hardware.
