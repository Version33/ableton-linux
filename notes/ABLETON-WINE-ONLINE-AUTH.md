# Online authorisation and `.auz` files

Status: the installer and launcher implement the return route. Automated
checks cover handler registration and prefix dispatch. The browser, desktop
portal, and a real account authorisation still need manual checks. A real check
consumes an authorisation.

## How the return path works

Live sends an online authorisation request through the host browser. The
result must return to the same prefix:

1. Live opens an Ableton HTTPS address. `winebrowser` passes it to `xdg-open`,
   which starts the host browser.
2. Ableton sends an `ableton:` address after login. The website can also
   provide an `.auz` response file.
3. The desktop MIME system runs `~/.local/bin/ableton-live` through one of the
   project-specific `io.github.shibco.ableton-linux.*.desktop` handlers.
4. The launcher sends the response through the packaged runtime and selected
   prefix. The prefix registry then starts Live.

The prefix stores a `MachineGuid`. Ableton binds the response to that value,
so another prefix cannot use it.

## What failed in older releases

On 20 July 2026, a Live 12.4.5b7 beta in a separate prefix replaced the
installed handler with:

    Exec=env "WINEPREFIX=/path/to/scratch-prefix" wine start %u

Four gaps broke the return path:

1. `winemenubuilder` gives every handler for the same scheme the global
   `wine-protocol-<scheme>.desktop` name. The beta prefix overwrote
   `wine-protocol-ableton.desktop` and routed the response through the wrong
   runtime and prefix.
2. The installer kept the overwritten file.
3. The installer did not set a default handler in `mimeapps.list`. A second
   handler therefore made the result depend on cache order.
4. The host had no MIME registration for `.auz`. `wine start <unix-path>` also
   failed because `start.exe` only converts a Unix path after `/unix`.

## Implementation

- `scripts/install.sh` installs
  `io.github.shibco.ableton-linux.protocol.desktop` and
  `io.github.shibco.ableton-linux.auz.desktop`. `winemenubuilder` does not
  generate these project IDs for other prefixes.
- The installer keeps known copies in `~/.local/share/ableton-wine/`. It
  removes an older global handler only when that file runs `ableton-live`.
- The installer registers `application/x-wine-extension-auz`, refreshes both
  host databases, sets each default, and checks the result. It stops and rolls
  back when registration fails.
- The launcher restores a missing or changed project handler. It resets and
  checks both defaults every time Live starts.
- The installer writes the selected runtime and prefix to
  `${XDG_CONFIG_HOME:-$HOME/.config}/ableton-wine/config`. A desktop callback
  therefore uses a custom prefix after the installer exits.
- The launcher sends `ableton:` and `.auz` callbacks to the prefix before it
  searches for a Live executable. Two editions of the same Live major version
  cannot block the callback.
- The launcher sends an existing `.auz` path through `wine start /unix`. It
  sends Live Sets, Clips, and Packs straight to the selected Live executable.
- `scripts/uninstall.sh` removes the project handlers and restores the previous
  defaults when they still point to this project.

## Check the host handlers

Run:

```bash
xdg-mime query default x-scheme-handler/ableton
xdg-mime query default application/x-wine-extension-auz
sh -c 'apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
grep "^Exec=" "$apps/io.github.shibco.ableton-linux.protocol.desktop"
grep "^Exec=" "$apps/io.github.shibco.ableton-linux.auz.desktop"'
```

The commands must print these desktop IDs:

```text
io.github.shibco.ableton-linux.protocol.desktop
io.github.shibco.ableton-linux.auz.desktop
```

Both `Exec` lines must run `~/.local/bin/ableton-live`.

## Check the full return path

Start Live, choose online authorisation, complete the browser login, and
confirm that Live reports the licence. Use a fresh browser profile or compare
a native package with a Flatpak or Snap package when only one browser package
fails.
