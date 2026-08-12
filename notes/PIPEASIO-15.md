# PipeASIO 1.5 in Ableton Linux

Ableton Linux uses PipeASIO 1.5.0 as its 64-bit ASIO audio driver.

## Requirements

PipeASIO requires PipeWire 1.4.2 or newer. Before replacing the Wine runtime,
the installer checks both the PipeWire library on the computer and the running
PipeWire service. It leaves the current installation unchanged when either
version is too old or cannot be read.

Ubuntu 24.04 and Linux Mint 22 include PipeWire 1.0.5. They need a distribution
upgrade before this version can install. The project does not include a private
copy of PipeWire or a second driver for older systems.

The driver works without the PipeASIO Settings window. That window needs Qt 6
and a Qt display package. The installer reports the packages required by the
current Linux distribution when they are missing.

## Buffer size

Live can use every whole buffer size from 32 to 8192 frames. The value does not
have to be a power of two. PipeASIO Settings can show and save any value in
that range without changing it to a preset.

Set a buffer for one launch with:

```bash
env PIPEASIO_PREFERRED_BUFFERSIZE=512 ableton-live
```

PipeWire shares one buffer size between audio programmes. If another programme
changes it, PipeASIO asks Live to rebuild its audio buffers at the new size.
PipeASIO sends silence while the two sizes differ, so Live does not play at the
wrong speed. If Live ignores the request, PipeASIO tries again after five
seconds and sends no more than three requests in one minute.

When the other programme releases the shared size, PipeASIO asks Live to return
to the size selected in PipeASIO Settings.

`PIPEASIO_ALLOW_QUANTUM_MISMATCH=on` turns off this pause and automatic change
for one launch. This option is for diagnosis. Audio can run at the wrong speed
when Live and PipeWire use different sizes.

## Sample rate

Live can select the sample rate through its Audio settings. PipeASIO asks
PipeWire to use that rate and keeps the accepted rate when Live restarts its
audio engine.

If the selected device cannot provide the requested rate, PipeASIO keeps the
rate the device is using and reports that value to Live. It does not remember
the rejected request for the next restart.

## Input and output devices

An input and output selected in PipeASIO Settings always take priority.

If the user selects only an output, PipeASIO first looks for an input on the
same physical device. If that device has no input, it uses the system default
input, then the first available input. This reduces the chance of using two
unrelated hardware clocks by accident.

PipeASIO reports when input and output use different clocks. Two-device audio
remains supported, and PipeWire resamples one device to keep the two streams
aligned.

## Scheduling

PipeASIO real-time scheduling is off by default. With this setting off, the
driver returns its audio thread to normal Linux scheduling even when the Wine
launcher started with real-time scheduling.

Change the driver setting for one launch with:

```bash
env PIPEASIO_REALTIME=on ableton-live
env PIPEASIO_REALTIME=off ableton-live
```

`ABLETON_RT` controls Wine's scheduling. `PIPEASIO_REALTIME` controls the
PipeASIO audio thread. The two settings are independent.

## PipeASIO Settings

Open PipeASIO Settings from the application menu or Live's **Hardware Setup**
button. The window can change the input, output, channel counts, buffer size,
sample rate, and real-time setting.

The window does not allow both input and output channel counts to be zero. It
also refuses a buffer size outside 32 to 8192 instead of saving a different
value. If it cannot save the file, it shows an error with the configuration
path.

After saving, set Live's **Audio Device** to **None** and back to **PipeASIO**
to apply the change.

If the settings programme cannot start, Hardware Setup shows a message instead
of leaving an unseen process behind. Live can change or release the audio
driver while the settings window is open. The helper keeps the required driver
code loaded until it exits.

The default configuration file is `~/.config/pipeasio/config.ini`. When
`XDG_CONFIG_HOME` is set, PipeASIO uses
`$XDG_CONFIG_HOME/pipeasio/config.ini` instead.

## MIDI time

PipeASIO uses the same Wine clock that Live uses for MIDI timestamps. It keeps
that clock moving forwards when the 32-bit millisecond count returns to zero
after about 49.7 days.

## Installer commands

Run `scripts/installer.sh` for installation and maintenance. It provides
commands for a full install, an update, the Wine runtime, the Wine prefix,
Ableton Link, removal, and the Live 11 first-run repair.

The installer keeps one previous runtime. Run the installed `rollback.sh` to
return to it:

```bash
~/.local/share/ableton-wine/rollback.sh
```

The installer preserves files changed by the user. If an update or removal
cannot restore every saved file, it keeps the remaining information so the
command can be run again after the problem is corrected.

## Limits

PipeASIO 1.5 does not reduce the CPU used by Live or its plugins. A smaller
buffer gives Live less time to process audio and can cause gaps when the CPU
cannot finish in time.

The driver sends silence while it corrects a buffer-size disagreement. It
cannot promise continuous audio when the computer is overloaded, an audio
device disappears, or PipeWire stops.

This release is 64-bit only. Upstream has not yet confirmed PipeASIO 1.5 with
Ableton Live.
