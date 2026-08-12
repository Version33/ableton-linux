# Audio enumeration stops after construction

Live can stop after `Audio In Out: Constructor finished` when WirePlumber is
inactive or when an older prefix contains repeatedly wrapped endpoint names.
Check the host service before changing the prefix.

## Check the audio session

```bash
systemctl --user is-active wireplumber.service
pactl list short cards
```

If WirePlumber is inactive or no cards appear, restart it:

```bash
systemctl --user restart wireplumber.service
```

Without WirePlumber, PipeWire may expose only `auto_null`, and Wine can wait
while Live enumerates endpoints.

## Repair old endpoint names

Wine previously wrapped a disconnected endpoint's stored `FriendlyName` each
time it loaded the registry entry. Names more than 70 levels deep were
observed. [Patch 0021](../patches/0021-mmdevapi-stop-re-wrapping-reloaded-endpoint-Friendly.patch)
now preserves properties loaded from the registry and generates names only
from a raw driver name.

The patch prevents new growth but does not shorten existing values. Close Live
and clear the audio endpoint registry once:

```bash
env WINEPREFIX="$HOME/.wine-ableton" \
  "$HOME/.local/opt/wine-d2d1-nspa-11.13/bin/wine" reg delete \
  'HKLM\Software\Microsoft\Windows\CurrentVersion\MMDevices\Audio' /f
```

Use the configured prefix and runtime paths if they differ. Connected devices
return on the next launch; disconnected devices return when reconnected.
