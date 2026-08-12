# Max for Live selection flash

Selecting away from and back to a Max for Live track could flash Live's whole
window black under Xwayland. The M4L child changed visibility and made winex11
detach and recreate the top-level client surface.

## Window transition and change

Live's top-level class moved between the normal client-surface path and Wine's
offscreen-composited path when the selected M4L view appeared. Unmapping and
remapping that X11 surface exposed a black frame.

[Patch 0062](../patches/0062-winex11-keep-a-selected-top-level-class-offscreen.patch)
lets the launcher keep one selected top-level class on the offscreen path. The
launcher sets `WINE_X11_FORCE_OFFSCREEN_CLASS` to Live's exact window class.

Compare the generic path for one launch with:

```bash
env WINE_X11_FORCE_OFFSCREEN_CLASS=off ableton-live
```

Check repeated track selection, M4L pane open and closed, plug-in editors,
resizing, and full screen. The selector must not affect unrelated Wine
applications or child windows.
