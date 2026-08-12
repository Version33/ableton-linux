# Beta release test plan

Use this plan to check a release candidate on real Linux systems before
publishing it. Record failures by test ID and keep one issue per failure.

## Test systems

Cover the environments available to the project. Prioritise variation in:

- distribution and desktop environment
- X11 and Xwayland sessions
- Intel, AMD, and NVIDIA graphics
- PipeWire and WirePlumber versions
- Live 11 and Live 12 editions
- audio interfaces, MIDI controllers, Push, and common plug-ins

Do not treat one handheld or one desktop environment as representative of all
Linux computers.

## Prepare the test

1. Save open work and note the current Ableton Linux release.
2. Use a separate prefix or account for a fresh-install run.
3. Confirm that the installer URL and checksum in the tester kit name the
   intended candidate.
4. List the automated checks without changing the system:

   ```bash
   ./beta/tester-kit/run-session --list
   ```

5. Run a normal session:

   ```bash
   ./beta/tester-kit/run-session --prefix "$HOME/.wine-ableton-beta"
   ```

The runner downloads the candidate over HTTPS, verifies its SHA-256, invokes
its `install --link=off` command, checks the distributed probes, and writes a
redacted report. It will not reuse a non-empty prefix without
`--reuse-prefix`.

## Check installation and update

For a release package outside the tester kit, use the current installer
commands:

```bash
sh install-ableton-latest.run install \
  --live-installer "$HOME/Downloads/Ableton Live Installer.zip" \
  --link=session
sh install-ableton-latest.run update
```

Confirm that:

- a fresh install starts Live and registers PipeASIO
- an update keeps Live, authorisation, projects, and user-edited settings
- cancelling or failing an update restores the previous managed files
- `link status` reports the selected `off`, `session`, or `always` mode
- uninstall with `--keep-prefix` leaves Live and its authorisation in place

Use `plan` before a lifecycle command when you only need to inspect its
intended actions:

```bash
sh install-ableton-latest.run plan update
```

## Check Live

Run the optional Live probes against an installed test prefix:

```bash
./beta/tester-kit/run-session --live-only \
  --prefix "$HOME/.wine-ableton-beta"
```

Then check these behaviours in Live:

- select PipeASIO and play a Set without drop-outs
- change the PipeASIO buffer and reconnect the audio device
- use input and output together when the machine has two audio devices
- open and close menus, plug-in editors, Learn View, and Max for Live devices
- resize the main window and use full screen
- disconnect and reconnect MIDI hardware
- open a file dialogue and use Show in Explorer
- enable Link and exchange tempo and transport state with another LAN peer
- save, close, and reopen a Set

Run a long session with representative projects and plug-ins. Record the exact
action, time, and visible result for any failure. Do not describe a problem as
fixed unless the same production path has been rerun successfully.

## Share the result

The session report removes common account paths, addresses, identifiers,
credentials, and window titles. Review it anyway. Never attach Ableton
installers, authorisation files, licence keys, Sets, samples, or plug-in
credentials.

Attach the unchanged report to the relevant issue. Include the Live edition,
Ableton Linux release, desktop environment, session type, and hardware needed
to reproduce the failure.

## Release decision

Do not publish while a required check fails or while a required platform has
not been exercised. Document skipped checks and the reason. Run the repository
release checks separately; the tester kit covers runtime behaviour, not every
build or provenance rule.
