# Audio device reconnect behaviour

PipeASIO talks to PipeWire directly. PipeWire keeps device and graph changes
outside Wine, so reconnecting an interface does not require WineASIO's JACK
port restoration helper.

If an interface disappears while Live runs, wait for PipeWire and WirePlumber
to restore it, then set Live's Audio Device to None and back to PipeASIO. Run
`pw-top` or `wpctl status` to confirm that the device has returned before
diagnosing Live.

The older WineASIO setup exposed JACK ports owned by Wine. A reconnect could
replace those ports, so `tools/jacklinkd.c` watched the graph and restored
links. Current launchers do not start that helper.

Two input and output devices can still use different PipeWire clock domains.
PipeASIO 1.5 reports those domains and anchors capture timing to the playback
clock. Test reconnects with both devices active; do not reduce a two-device
report to a single-device setup.
