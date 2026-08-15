# PipeASIO 1.2.2 integration record

This file records the driver integration shipped in July 2026. The current
driver is PipeASIO 1.5.0; use [PIPEASIO-15.md](PIPEASIO-15.md) for current
requirements and behaviour.

## Why WineASIO was replaced

WineASIO required JACK registration and a separate JACK graph. PipeASIO is a
native PipeWire client and fits the audio service used by current Linux
desktops. The initial integration vendored PipeASIO 1.2.2, verified its source
hash, built it with the patched Wine toolchain, registered it in the prefix,
and selected it through Live's ASIO settings.

Installer and build checks covered both `pipeasio.dll` and Wine's ALSA driver.
The launcher kept host PipeWire and WirePlumber configuration outside the
prefix.

## Recorded July 2026 checks

The initial release opened PipeASIO in Live, played audio through PipeWire,
enumerated the configured devices, and exercised the installer and removal
paths. It also exposed limitations later addressed by 1.5, including restricted
buffer choices and awkward graph-quantum changes.

Do not use this historical record to diagnose the current driver. PipeASIO 1.5
accepts 32 to 8192 frames, handles foreign graph quantums, reports clock
domains, ships its settings panel, and requires PipeWire 1.4.2 or newer in this
project.
