# Push 2 display support

[Patch 0032](../patches/0032-libusb-1.0-add-host-USB-bridge-for-Push-2.patch)
lets `Push2DisplayProcess.exe` reach Push 2's display interface through host
libusb. It is a narrow bridge for this 64-bit helper, not a general Wine libusb
implementation.

## Configure Live once

Use exactly one control-surface row:

- Control Surface: `Push2`
- Input: `Ableton Push 2 Live Port`
- Output: `Ableton Push 2 Live Port`

Enable both Remote switches. Do not add the User Port as another Push2 row;
two rows start two display helpers and only one can claim USB interface 0.

## USB path

Push 2 uses USB ID `2982:1967`. Interface 0 carries display bulk endpoints
`0x01` and `0x81`; interfaces 1 and 2 carry audio control and MIDI. The builtin
`libusb-1.0.dll` implements the 16 Win64 ABI calls used by Ableton's helper and
passes fixed-width requests to host `libusb-1.0.so.0`.

Prefix setup selects the builtin only for `Push2DisplayProcess.exe`. Live keeps
its own DLL, and ALSA keeps the MIDI interfaces.

## Check the bridge

`tools/push2usb-pe.c` verifies exports, ordinals, enumeration, repeated claims,
and cancellation. A physical check must also confirm that the display streams,
controls work through Live, MIDI remains connected, and the helper exits with
Live.

Use `aconnect -l` for Wine's ALSA sequencer path and `amidi -l` for raw MIDI.
`Shutting down because live didn't ack in time` is expected when the display
helper runs without Live.

To remove the per-application override for a comparison:

```bash
env WINEPREFIX="$HOME/.wine-ableton" \
  "$HOME/.local/opt/wine-d2d1-nspa-11.13/bin/wine" reg delete \
  'HKCU\Software\Wine\AppDefaults\Push2DisplayProcess.exe\DllOverrides' \
  /v libusb-1.0 /f
```

Do not keep that override with a runtime that lacks patch 0032. Disconnect and
`NO_DEVICE` recovery remain incompletely exercised. Raw USB traces can include
the controller serial number and must not be published.
