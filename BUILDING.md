# Build and configure Ableton Live on Linux

This document explains how to build the project from source and change its
advanced settings.

## Requirements

The build requires:

- Podman
- about 10 GB of free disk space
- `zstd`
- `cabextract`
- `binutils`

## Build and install from source

Run:

```bash
./build.sh
./scripts/installer.sh install \
  --live-installer "/path/to/Ableton Live 12 Suite Installer.exe" \
  --live-major 12 --link=session
ableton-live
```

`build.sh` creates the patched Wine runtime and `dist/ableton-linkd`.
`installer.sh` checks the new files, prepares the installation beside the
current one, then moves it into place. If an earlier step fails, it restores
the previous files. Run `installer.sh` yourself. It calls `install.sh`,
`setup-prefix.sh`, and `setup-link.sh` when needed.

## Install or update one part

Use these commands when you do not want a complete installation:

```bash
./scripts/installer.sh runtime install
./scripts/installer.sh prefix create --live-major 12
./scripts/installer.sh prefix update --live-major 12
./scripts/installer.sh link enable --mode=session
./scripts/installer.sh link disable
./scripts/installer.sh link status
```

Select other locations with `--prefix PATH` and `--runtime-root PATH`. Show
what a command would change without changing any files or settings:

```bash
./scripts/installer.sh plan update
./scripts/installer.sh plan uninstall --delete-prefix
```

The installer does not grant real-time audio permissions. Run
`./scripts/setup-realtime.sh` separately to configure those permissions.

## Run the checks

Run all shortcut and installer checks:

```bash
make test
```

Build the Wine menu test with all compiler warnings enabled. Then run its two
modes:

```bash
winegcc -Wall -Wextra -Werror -o altnum-menu-repro tools/altnum-menu-repro.c
./altnum-menu-repro.exe swallow
./altnum-menu-repro.exe pass
```

The GNOME test uses temporary data and does not change the desktop settings.
The Wine test sends keys to its own window. It needs a working Wine display.
Each mode returns a non-zero status when a required result fails.

## Configure Ableton Link

Configure Ableton Link and choose when it runs:

```bash
./scripts/installer.sh link enable --mode=session
```

This asks for `sudo` only when the firewall needs to allow UDP port 20808 or an
older setup left a network setting that needs removing.

## Build the single-file installer

Run:

```bash
./scripts/make-installer.sh
```

The result is `dist/ableton-wine-setup-<version>.run`. The installer includes
the runtime, launchers, Ableton Link support, setup scripts, and corresponding
source required by bundled licences.

Verify pinned source inputs with:

```bash
make verify
```

## Environment variables

The installer reads settings in this order: command-line option, exported
variable, saved XDG configuration, then default value.

- `ABLETON_WINE_ROOT` selects the Wine runtime. The default is
  `~/.local/opt/wine-d2d1-nspa-11.13`.
- `ABLETON_WINEPREFIX` selects the Wine prefix. The default is
  `~/.wine-ableton`.
- `ABLETON_LIVE_VERSION=11|12` selects a Live major version.
- `ABLETON_LIVE_EXE` selects one exact Live executable.
- `ABLETON_LINK_MODE=off|session|always` chooses when Link runs. The installer,
  Live launcher, Max launcher, service, and uninstaller use the same value.
- `ABLETON_LINKD` selects the Link programme. The installer manages only the
  copy under the Ableton data directory. A path elsewhere must already exist
  and be executable. The installer can use that file but never changes or
  removes it.
- `ABLETON_SHORTCUTS=take` temporarily turns off exact Ctrl+Alt+Up and
  Ctrl+Alt+Down entries in the related GNOME settings. Live 11 also turns off
  the exact Ctrl+Alt+Delete entry. The default value, `preserve`, does not
  change desktop shortcuts.
- `ABLETON_DPI_MODE=auto|preserve|100|fractional|dpi<N>|fractional<N>`
  overrides display-scale detection.
- `ABLETON_THEME_MODE=auto|dark|light|preserve` controls desktop theme sync.
- `ABLETON_TOPBAR_MODE=live|system|preserve|'#RRGGBB #RRGGBB'` controls menu
  colours.
- `ABLETON_UI_FONT=auto|preserve|off|<family>` controls the Wine UI font.
- `ABLETON_DCOMP=off` disables DirectComposition for one launch.
- `WINE_X11_FORCE_OFFSCREEN_CLASS=off` disables the default Max for Live
  selection-flicker fix for one launch.
- `WINE_WIN32_FULLSCREEN_CLASS=off` disables the default Live fullscreen
  layout and exit-state fix for one launch.
- `WINE_WIN32_RESIZABLE_CLASS=off` disables the monitor-sized Live window
  resizability fix for one launch without disabling fullscreen normalisation.
- `ABLETON_RT=off` disables real-time scheduling for one launch.
- `ABLETON_POWER=off` keeps the computer's power mode unchanged for one
  launch.
- `ABLETON_LINKD_LINGER` sets how many seconds `ableton-linkd` waits with no
  Link peers before it exits. Whole seconds only. The default is 900; 0
  keeps it running.
- `PIPEASIO_*` variables override PipeASIO settings for one launch.
- `ENGINE` selects the container engine used by build scripts. The default is
  `podman`.

Adjust installer time limits with `ABLETON_WINE_COMMAND_TIMEOUT`,
`ABLETON_WINETRICKS_TIMEOUT`, `ABLETON_LIVE_INSTALL_TIMEOUT`,
`ABLETON_PAYLOAD_EXTRACT_TIMEOUT`, `ABLETON_RUNTIME_EXTRACT_TIMEOUT`,
`ABLETON_PAYLOAD_IO_TIMEOUT`, and `ABLETON_LAUNCH_TIMEOUT`. The installer checks
each value before use. When a process reaches its limit, the installer sends
`TERM`, waits five seconds, then sends `KILL` if the process is still running.

## Repository layout

- [`patches`](patches/): Wine and PipeASIO patches
- [`scripts`](scripts/): build, install, setup, and launch scripts
- [`vendor`](vendor/): pinned build inputs
- [`notes`](notes/): implementation records and investigations
- [`tools`](tools/): diagnostic and build tools
- [`bin`](bin/): installed launchers
- [`dist`](dist/): build output
- [`beta`](beta/): beta test kit

The patch list and provenance are in [`patches/BASE.txt`](patches/BASE.txt).
