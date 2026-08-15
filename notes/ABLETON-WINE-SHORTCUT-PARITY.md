# Live shortcuts under Wine and GNOME

Wine and the desktop can interfere at different points. The Wine change is
automatic; the GNOME change is opt-in because it temporarily affects the
whole desktop session.

## Alt shortcuts inside Wine

Earlier Wine builds could treat a Live-handled Alt chord as bare Alt and arm
the menu bar. Patch 0070 clears that pending action as soon as another key or
mouse button arrives. Alt shortcuts handled by Live should then perform only
their Live action. Alt plus a menu letter and bare Alt keep their normal menu
behaviour.

The standalone reproducer passes on the patched build. Real Live coverage was
still pending when this record was written.

## Let Live receive GNOME Ctrl+Alt shortcuts

GNOME takes Ctrl+Alt+Up and Ctrl+Alt+Down for workspace movement. It can also
take Ctrl+Alt+Delete, which Live 11 uses for Delete Fades.

Start Live with:

```bash
env ABLETON_SHORTCUTS=take ableton-live
```

The launcher removes only the exact conflicting accelerators. It retains
other entries, including Super-based workspace shortcuts. It restores the
saved values after all Live sessions exit and can recover them on a later
launch after a crash or logout. If the user changes a held setting while Live
runs, that new value is preserved.

The default `ABLETON_SHORTCUTS=preserve` changes nothing. The hold applies
only to GNOME. Other desktops need their own shortcut configuration.

Run `scripts/test-shortcut-hold.sh` for the settings, recovery, concurrency,
and user-change checks. Build and run `tools/altnum-menu-repro.c` on a working
Wine display for the Wine input path.
