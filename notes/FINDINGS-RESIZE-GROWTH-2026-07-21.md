# Fractional-scale resize growth, 2026-07-21

On the measured GNOME/Xwayland system, Live 12.4.3 grew by two physical pixels
per interactive resize cycle at 125 per cent scale.

Xwayland used a 2x framebuffer and granted even physical sizes. Live also
produced even sizes, but Wine's frame offset was odd. Each side rounded the
next request in a different direction. Both a seven-pixel and an eight-pixel
menu band reproduced the loop, so changing one frame constant could not make
it settle.

[Patch 0042](../patches/0042-winex11-alias-sub-scale-WM-config-rounding-instead-o.patch)
records the X11 request. When the host grant differs only by rounding smaller
than the compositor scale, Wine retains the requested Win32 rectangle and
avoids another equivalent X11 request.

After the patch, interactive resizing, tiling, and moving settled across the
recorded Live sessions. Patch 0040 remains necessary for the one-time menu
geometry calculation. See [the DPI note](ABLETON-WINE-DPI-SCALE-100.md) for
the surrounding scale setup.
