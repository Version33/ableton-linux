# Build Ableton Live on Linux

This page covers the current source build, tests, packaging, and maintainer options.

## Build

Install Podman, Git, Bash, Python 3, GNU Coreutils, GNU Findutils, GNU grep, GNU tar, binutils, and `zstd`. Allow about 10 GB of free disk space.
Then run:

```bash
./build.sh
```

Set `ENGINE` to another compatible container command if needed. Set `JOBS` to limit parallel work:

```bash
env JOBS=8 ./build.sh
```

The build verifies the vendored Wine, PipeASIO, PipeWire SDK, ntsync, and Ableton Link inputs. It then creates the container image, builds Wine and PipeASIO, runs the compiled test suites and patch audit, and writes the runtime and build records to `dist/`.

ThreadSanitizer must complete successfully in the default build. If ThreadSanitizer cannot start on a local host, this command permits only a recognised startup limitation and records a non-release build:

```bash
env PIPEASIO_TSAN_MODE=auto ./build.sh
```

Official packages require the default ThreadSanitizer result.

## Install a source build

Install `cabextract`, then run the installer dispatcher after a successful build:

```bash
./scripts/installer.sh install \
  --live-installer "/path/to/Ableton Live 12 Suite Installer.zip" \
  --live-major 12 \
  --link=session
```

The dispatcher validates the new files before changing the current installation. If an operation fails before it commits, it restores the files and configuration recorded at the start.

Use one component directly when a full install is not needed:

```bash
./scripts/installer.sh runtime install
./scripts/installer.sh prefix create --live-major 12
./scripts/installer.sh prefix update --live-major 12
./scripts/installer.sh prefix repair-live11
./scripts/installer.sh link enable --mode=session
./scripts/installer.sh link disable
./scripts/installer.sh link status
```

Preview any supported operation without changing files:

```bash
./scripts/installer.sh plan update
./scripts/installer.sh plan uninstall --delete-prefix
```

Run `./scripts/installer.sh --help` for the complete current command list.

## Test

Run the repository policy, launcher, installer, and PipeASIO checks:

```bash
make test
```

Verify all pinned build and packaging inputs:

```bash
make verify
```

The container build also runs PipeASIO's non-integration CTest suite, a no-Qt build, ASan and UBSan tests, ThreadSanitizer unit tests, relocation and registration checks, and the final runtime audit. These checks do not replace a run with Live and real audio hardware.

## Package

After a successful `./build.sh`, create the single-file installer:

```bash
./scripts/make-installer.sh
```

This writes `dist/ableton-wine-setup-<version>.run` and its SHA-256 file. Packaging refuses a build that lacks the required sanitizer result or fails the runtime audit.

## Current configuration

The installer saves the runtime root, Wine prefix, selected Live major version, and Link mode. For these values, a command-line option overrides an exported `ABLETON_*` variable, which overrides the saved XDG configuration and then the default.

- `ABLETON_WINE_ROOT` selects the Wine runtime. The default is `~/.local/opt/wine-d2d1-nspa-11.13`.
- `ABLETON_WINEPREFIX` selects the Wine prefix. The default is `~/.wine-ableton`.
- `ABLETON_LIVE_VERSION=11|12` selects a Live major version for the launcher.
- `ABLETON_LINK_MODE=off|session|always` controls when Ableton Link runs.

These environment variables change one launch without changing the saved installer configuration:

- `ABLETON_LIVE_EXE` selects one exact Live executable.
- `ABLETON_SHORTCUTS=take` lets Live use the GNOME shortcuts documented in [Troubleshooting](TROUBLESHOOTING.md#gnome-handles-a-live-shortcut-instead-of-live).
- `ABLETON_DPI_MODE=auto|preserve|100|fractional|dpi<N>|fractional<N>` overrides display-scale detection.
- `ABLETON_THEME_MODE=auto|dark|light|preserve` controls desktop theme matching.
- `ABLETON_RT=off` disables Wine real-time scheduling for one launch.
- `ABLETON_POWER=off` leaves the computer's power mode unchanged for one launch.
- `PIPEASIO_*` values override PipeASIO's saved settings for one launch.

The build-only `ENGINE` variable selects the container command. Its default is `podman`.

PipeASIO stores its settings in `${XDG_CONFIG_HOME:-$HOME/.config}/pipeasio/config.ini`. The installer creates a 256-frame, two-input, two-output configuration only when that file does not exist. The driver accepts buffer sizes from 32 to 8192 frames.

The optional `scripts/setup-realtime.sh` asks for `sudo`, adds the current user to the real-time audio group, writes the project audio limits and swappiness settings under `/etc`, and enables `rtirq` when it is installed. Run it only when you want those system changes, then log out and back in.

## Repository layout

- [`patches`](patches/): ordered Wine and PipeASIO patches, checksums, and provenance
- [`scripts`](scripts/): build, install, launch, test, and release scripts
- [`vendor`](vendor/): pinned source inputs
- [`tools`](tools/): diagnostic and build tools
- [`desktop`](desktop/): application and file-type integration
- [`dist`](dist/): generated build output

The authoritative patch list and provenance are in [patches/BASE.txt](patches/BASE.txt).
