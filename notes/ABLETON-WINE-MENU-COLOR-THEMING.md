# Native menu colours follow Live's theme

The launcher maps Live theme colours to Wine's native menu bar and dropdowns.
Patches 0049 to 0052 make changes visible in a running process and remove two
old menu drawing behaviours that looked wrong with dark colours.

## Colours applied at launch

`scripts/ableton-live` reads the selected `.ask` file and writes Wine system
colours before Live starts:

| Wine value | Live theme value |
|---|---|
| `MenuBar`, `ActiveTitle`, `GradientActiveTitle` | `Desktop` |
| `Menu` | `ControlBackground` |
| `MenuText`, `TitleText` | `ControlForeground` |
| `MenuHilight`, `Hilight` | `SelectionBackground` |
| `HilightText` | `SelectionForeground` |
| `GrayText` | blend of menu background and text |

`ABLETON_TOPBAR_MODE=live` is the default. `system` uses host title-bar
colours, `preserve` leaves the prefix values alone, and two `#RRGGBB` values
select the bar background and text directly.

The launcher chooses the newest `Preferences.cfg` by modification time, not by
the version text in its parent directory. It then finds the named theme under
Live's installed `Themes` directory.

## Apply a theme after Live starts

A single watcher per prefix observes `Preferences.cfg` with `inotifywait` or a
two-second modification-time poll. When the resolved colours change, it runs
`setsyscolors.exe`, which calls `SetSysColors()` inside the Wine session.

Patch 0050 clears the receiving process's cached colours, brushes, and pens on
`WM_SYSCOLORCHANGE`. Patch 0051 includes the non-client frame in the repaint.
A registry write alone affects only later processes.

Live writes the chosen theme only after Preferences closes. No external file,
registry, window, or X11 property change was found during the in-dialogue
preview. See
[the theme preview findings](FINDINGS-LIVE-THEME-PREVIEW-SIGNAL-2026-07-26.md).

The visible repaint can still take several seconds after the file changes.
That delay has not been isolated.

## Menu drawing changes

Patch 0049 draws disabled text once in `COLOR_GRAYTEXT` instead of adding a
white offset bevel. Patch 0052 hides mnemonic underlines in the top-level menu
bar while keeping dropdown mnemonics.

After changes here, check launch-time colour, a theme change after closing
Preferences, light and dark themes, disabled items, selection colours, and Alt
navigation. Use `WINEDEBUG=+message` to confirm `WM_SYSCOLORCHANGE` delivery
when the registry changes but Live does not repaint.
