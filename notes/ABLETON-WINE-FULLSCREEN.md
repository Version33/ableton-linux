# Live fullscreen layout and exit

Release 2026.08.04.1 shipped the fullscreen changes for issue 42. Contributors
reported correct entry and exit on GNOME, KDE, Niri, sway, and MangoHud setups.
This record describes the mechanism and the remaining comparisons.

## Correct the fullscreen rectangle

Live keeps its native menu attached in fullscreen. Wine's normal frame
calculation could retain a menu or non-client offset, shifting the content and
mouse targets.

[Patch 0065](../patches/0065-win32u-normalize-selected-fullscreen-window.patch)
normalises a monitor-sized window selected by the Live window class. Patch
0069 keeps a captioned monitor-sized Live window resizable without treating
every large window as fullscreen.

The launcher selects only `Ableton Live Window Class` through
`WINE_WIN32_FULLSCREEN_CLASS` and `WINE_WIN32_RESIZABLE_CLASS`.

## Finish fullscreen exit

A redundant X11 configure could leave the fullscreen image visible after Live
returned to a window. The selected path suppresses that stale transition and
lets the restored window repaint immediately.

Use one-launch overrides to compare the generic Wine path:

```bash
env WINE_WIN32_FULLSCREEN_CLASS=off ableton-live
env WINE_WIN32_RESIZABLE_CLASS=off ableton-live
```

## Checks still useful

Enter and leave fullscreen through both the menu and F11. Check click
alignment, menu access, repaint after exit, repeated cycles, more than one
monitor, fractional scaling, and a window that merely matches the monitor
size. Record the desktop, session type, scale, and monitor layout for any
failure.
