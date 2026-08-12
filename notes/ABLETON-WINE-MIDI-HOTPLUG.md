# MIDI device reconnects

Wine's ALSA MIDI driver subscribed to devices present at startup but did not
restore the subscription after one disappeared and returned. Live then kept a
stale port or received no input from the reconnected controller.

[Patch 0028](../patches/0028-winealsa-re-subscribe-MIDI-devices-when-they-reappea.patch)
retains the selected device identity and subscribes again when the same ALSA
sequencer port reappears.

Check the host graph with `aconnect -l`; `amidi -l` covers raw MIDI devices and
does not show the sequencer connections Wine uses. Exercise disconnect and
reconnect while Live runs, then send notes, controls, and clock data.

The patch covers a device known when Wine started. Discovery of a completely
new MIDI device during the same Live process remains a separate case. A Live
process started while the audio stack was unavailable may need a restart even
after the host graph recovers.
