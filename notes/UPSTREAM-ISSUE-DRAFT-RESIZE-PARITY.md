# Draft report for 2x Xwayland resize rounding

This draft was prepared on 2026-07-21. No filed Mutter or Wine issue URL is
recorded. Patch 0042 handles the observed loop in this Wine build.

## Suggested Mutter title

Odd X11 configure requests round up with Xwayland native scaling and can form
a resize feedback loop

## Report text

Environment:

- GNOME Shell and Mutter 50.3
- xorg-xwayland 24.1.13
- Wayland session on CachyOS
- one monitor at 125 per cent with a 2x Xwayland framebuffer
- `scale-monitor-framebuffer` and `xwayland-native-scaling` enabled

An X11 request with odd physical height was granted one pixel larger:

```text
requested: (1182,132)-(3210,2613), height 2481
ConfigureNotify height: 2482
```

Ableton Live under Wine then repeated this sequence:

1. Live accepted only even physical client sizes at per-monitor 2x DPI.
2. Wine added an odd offset between client and outer geometry.
3. Live requested one pixel more than the previous grant.
4. Mutter rounded the odd request up again.

The outer window grew two physical pixels per cycle. One trace grew from 2390
to more than 6600 pixels before capture stopped. Both seven-pixel and
eight-pixel menu bands reproduced the loop.

Questions for Mutter:

- Is rounding odd X11 geometry up the intended result of native scaling?
- Can an unrepresentable size be rounded without exceeding the request?
- Is there an acknowledgement method for grid-aligned clients?

A standalone reproducer should request `H + 1` after each even-height
`ConfigureNotify` and compare 2x with 1x behaviour.

## Wine-side report

winex11 returns the rounded host grant to Win32. A per-monitor-aware
application can round again and request another size. Patch 0042 records the
host rectangle but retains the requested Win32 rectangle when the difference
is smaller than one compositor scale unit on aligned edges.

The supporting private traces are named `live-trace-interactive-20260721.log`,
`ratchet-segment.log`, `live-trace-band8-20260721.log`, and
`band8-segment.log`. Regenerate them before filing if they are no longer
available.
