# Live theme preview exposes no external update, 2026-07-26

The native menu watcher follows `Preferences.cfg`, but Live previews a theme
inside the open Preferences dialogue before it writes that file. This check
looked for an earlier event.

`inotifywait` observed the complete per-version AppData tree while themes were
toggled repeatedly. Registry file modification times were checked before and
after the same actions.

Only an unrelated Ableton Link log write occurred during preview.
`Preferences.cfg` changed when the dialogue closed. `user.reg` did not change,
and a later `system.reg` write matched Wine's periodic flush rather than a
theme action.

Live performs the preview inside its process and exposes no observed file or
registry event. The watcher cannot update Wine's native menu until Live writes
`Preferences.cfg`. Closing Preferences is therefore the first usable trigger
without changing Live itself.
