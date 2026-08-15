# Display scale calibration and stable window sizing

The launcher recalibrates the prefix before each Live start. Patches 0040 and
0042 then keep Live's main window stable across moves, tiles, and interactive
resizes on the measured GNOME/Xwayland fractional-scale setup.

## Keep Wine and Xwayland at the same scale

GNOME with `xwayland-native-scaling` uses an integer-scaled Xwayland
framebuffer. These values must describe the same mode:

| Setting | 125% GNOME scale | 100% scale |
|---|---:|---:|
| `HKCU\Control Panel\Desktop\LogPixels` | 192 | 96 |
| Live IFEO `dpiAwareness` | `2` | absent |
| Mutter `xwayland-native-scaling` | enabled | disabled |

Stale values can magnify Live, double the cursor, or make the main window move
by one or two pixels per configure cycle. `scripts/detect-scale.sh` detects
GNOME, KDE, sway, Hyprland, COSMIC, and an Xft DPI fallback. The launcher
updates the registry values but does not change the desktop setting.

For one comparison launch:

```bash
env ABLETON_DPI_MODE=100 ableton-live
env ABLETON_DPI_MODE=fractional ableton-live
```

`ABLETON_DPI_MODE=preserve` leaves the prefix values unchanged. Non-GNOME
modes use names such as `dpi120` for 125 per cent.

## Stop resize growth

Live derives its outer rectangle from the client size, the DPI-adjusted frame,
and an extra menu band. Patch 0040 scales that band with the menu DPI. At a 2x
Xwayland framebuffer, Live and the window manager could still round the same
odd offset in opposite directions and add two pixels per cycle.

[Patch 0042](../patches/0042-winex11-alias-sub-scale-WM-config-rounding-instead-o.patch)
records each configure request. When the granted rectangle differs only by
sub-scale rounding, Wine reports the requested rectangle to Live and avoids a
second X request for the equivalent size.

Live 12.4.3 was exercised at 125 per cent with interactive resizing, tiling,
and moving. Each action settled once in that test. See
[the resize findings](FINDINGS-RESIZE-GROWTH-2026-07-21.md) for the trace.

The relevant tools are `metricprobe.c`, `metricprobe2.c`, `wmresize.c`,
`wmresize2.c`, `menumeasure.c`, `showrestore.c`, and `xsettle.c` under
`tools/`.
