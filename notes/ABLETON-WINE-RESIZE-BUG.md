# Main-window DPI layout loop

On GNOME with an upscaled Xwayland framebuffer, Live once mixed a 96-DPI
process default with a 192-DPI main window. It then issued 175 to 400 repeated
size requests per second, used most of one core, and either flashed or grew.

## Cause

Live selected per-monitor-v2 awareness on individual threads while embedded
Chromium set Wine's one-time process state to unaware. The main window kept
192 DPI, but later layout ran at the 96-DPI process default. Live combined a
96-DPI client rectangle with a 192-DPI frame, so the requested and returned
rectangles could not agree.

## Early process setup

For an upscaled GNOME Xwayland framebuffer, prefix setup writes
`dpiAwareness=2` under the Image File Execution Options key for each Live
executable. Wine reads it during process attach, before Live or Chromium can
set another process value. The launcher removes it again at 100 per cent
scale.

In the recorded run, resize calls stopped within 15 seconds and no Live thread
exceeded 0.5 per cent CPU during the final minute. This change addresses the
mixed-DPI loop. Patch 0042 addresses the separate window-manager rounding loop
described in [the scale note](ABLETON-WINE-DPI-SCALE-100.md).

Clamping the window, changing border colours, or re-enabling frame extents did
not remove the repeated layout work. The launcher must keep its scale
detection and the desktop's Xwayland scaling mode in agreement.
