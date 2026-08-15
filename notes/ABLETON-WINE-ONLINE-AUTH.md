# Online authorisation and `.auz` callbacks

The installer and launcher route browser and `.auz` responses back to the
selected Wine prefix. Automated checks cover handler registration and prefix
dispatch. A real account authorisation remains a manual check and can consume
an authorisation.

## Return path

1. Live opens Ableton's HTTPS page through the host browser.
2. Ableton returns an `ableton:` URL or an `.auz` file.
3. The desktop starts `~/.local/bin/ableton-live` through a project-specific
   handler.
4. The launcher passes the response to the configured runtime and prefix.

The prefix stores the `MachineGuid` used for authorisation. A response made for
one prefix cannot be moved to another.

## Handler ownership

Older releases used Wine's global `wine-protocol-ableton.desktop` name, which
another prefix could overwrite. Current installation uses:

```text
io.github.shibco.ableton-linux.protocol.desktop
io.github.shibco.ableton-linux.auz.desktop
```

The installer saves known copies, sets and verifies both MIME defaults, and
rolls back if registration fails. The launcher restores missing or changed
copies and checks the defaults on each start. It dispatches callbacks before
searching for a Live executable, so multiple editions cannot block the return.

An existing `.auz` path goes through `wine start /unix`. Sets, Clips, and Packs
go directly to the selected Live executable.

## Check the handlers

```bash
xdg-mime query default x-scheme-handler/ableton
xdg-mime query default application/x-wine-extension-auz
```

The commands should print the two desktop IDs above. Test without a real token:

```bash
ableton-live 'ableton://invalid-ableton-linux-probe'
xdg-open 'ableton://invalid-ableton-linux-probe'
```

The address cannot authorise Live. Both commands should hand it to the selected
prefix. Never publish a real callback URL or `.auz` file.
