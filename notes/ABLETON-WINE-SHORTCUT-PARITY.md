# Ableton Live shortcut support

This change fixes two types of shortcut conflict.

## Alt shortcuts in Wine

Live uses Alt with number keys and other keys. Live handles these shortcuts
itself. Wine must not open the menu after Live handles a shortcut.

Wine now clears a pending menu action when the application handles another key
or a mouse click. It clears the action before other input processing can stop
the key or click.

Normal menu controls do not change:

- Alt by itself selects the menu bar.
- Alt with a menu letter opens that menu.
- An application can pass an Alt shortcut to the normal Windows menu code.
- F10 keeps its normal Windows behavior when the application does not use it.

## GNOME shortcuts

GNOME handles some key combinations before Wine can receive them. Live uses
Ctrl+Alt+Up and Ctrl+Alt+Down. Live 11 also uses Ctrl+Alt+Delete.

The launcher does not change GNOME shortcuts by default. Use this command to
let Live use the conflicting shortcuts:

```bash
ABLETON_SHORTCUTS=take ableton-live
```

The launcher changes only these entries:

- Ctrl+Alt+Up
- Ctrl+Alt+Down
- Ctrl+Alt+Delete for Live 11 only

Other entries in the same GNOME setting stay in place. For example, a Super
key shortcut stays in place.

The change applies to the complete GNOME session. Thus, other applications
cannot use a held shortcut while Live runs. The launcher restores the settings
after all Live sessions exit.

The helper saves recovery data before it changes a setting. It uses one state
for the GNOME session because all Wine installations share these settings.

The helper restores a setting only if it still has the held value. If the user
changes the setting while Live runs, the helper keeps the user change. If a
restore operation fails, the helper keeps the recovery data and tries again on
the next launch.

The helper checks for the required system tools and private temporary storage.
If a requirement is not available, the helper does not change the desktop.
The launcher confirms that Live exists before it holds a shortcut. Recovery
can still run after Live is removed.

## Saved verification tools

The repository contains the two tools used for this change.

Run the GNOME hold and recovery tests:

```bash
scripts/test-shortcut-hold.sh
```

The test uses temporary data. It does not change the current GNOME settings.

Build and run the Wine menu test:

```bash
winegcc -Wall -Wextra -Werror -o altnum-menu-repro tools/altnum-menu-repro.c
./altnum-menu-repro.exe swallow
./altnum-menu-repro.exe pass
```

The `swallow` test represents Live. It checks two Alt-key release orders and an
Alt-click. It also checks Alt with a menu letter and Alt by itself. The `pass`
test checks normal Windows menu control.

The Wine test needs a working Wine display session. The shell test does not.

## Test status

The Wine patch applies to the Wine 11.13 source and builds without an error.
Both modes of the saved Wine test pass with the patched build. The shell test
checks normal use, safe restore, failed restore, and changes made by the user.

The change has not yet had a test in Ableton Live itself.
