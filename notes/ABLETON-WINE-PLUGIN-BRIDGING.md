# Test Linux-native plug-ins through Carla

Ableton Linux does not yet load Linux VST or CLAP plug-ins inside Live. This
experimental route runs the plug-in in Carla and connects audio and MIDI
through PipeWire.

## Try the route

1. Install Carla and the Linux plug-in through the distribution.
2. Start Carla with PipeWire support and load the plug-in.
3. Start Live with PipeASIO.
4. Connect a Live or MIDI-controller output to Carla's MIDI input.
5. Connect Carla's audio outputs to the intended PipeWire playback or recording
   inputs.

Use `qpwgraph`, `helvum`, or `pw-link` to inspect and create links. Save the
Carla rack separately from the Live Set.

## What this does not provide

Live does not see the Linux plug-in as a device. It cannot store the plug-in
state in the Set, automate parameters through its plug-in API, compensate its
latency as an in-host device, or reopen its editor from the device rack. Links
may need restoring after either application restarts.

Measure round-trip latency and check transport, sample rate, graph quantum,
and reconnect behaviour before using the route in a performance.
