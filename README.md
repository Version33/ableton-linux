# Ableton Live 12, Max For Live and Push on Linux

Run Ableton Live 12, Max for Live and Ableton Push 1 and 2 on a patched Wine. Featuring dozens of QoL fixes, reproducible builds, a single-file installer, and a beta test program with remote diagnostics. Very unofficial, not endorsed or affiliated in any way with Ableton. 

![screenshot.png](screenshot.png)

Follow me on [Mastodon](https://post.lurk.org/@shibacomputer) or [Bluesky](https://bsky.app/profile/shibco.newdesigncongress.org) to keep track of development.

DOWNLOAD HERE: https://github.com/shibco/ableton-linux/releases/latest/download/install-ableton-latest.run

Place this installer + an Ableton Live zip file downloaded from Ableton.com in the same directory, and run.

## Features

- Support for all Live 12 editions (Intro, Standard, Suite, Trial), and experimental Live 12 Beta support.
- Push 1 + 2 support.
- Device recovery: audio and MIDI devices (Push included) survive in-session disconnect and reconnect.
- Experimental Max/MSP and Max for Live support.
- File dialogues including open/save dialogs are handled by your system's native file picker. 
- Dark/light theme mode that follows your system's settings.
- System font support, Display Ableton's AI with your desktop interface fonts.
- Low-latency audio via autobuilt PipeASIO, a native PipeWire ASIO driver, at 256 frames, with additional hardening to prevent crashes. Live can record from any PipeWire source, no JACK layer needed.
- VST3/JUCE/OpenGL editor windows render, take input, and scale correctly.
- HiDPI support display scale auto-detected and recalibrated on every launch.
- Extensions SDK support.
- VST specific fixes for Autuira, Pianoteq, SWAM and KORG (with others to follow).
- Reproducible builds.

## Getting started

Most popular distros and configs are supported. Flatpak / steam-run / sandboxed environments are not supported!

1. Download Ableton Live
2. Download the latest installer: [install-ableton-latest.run](https://github.com/shibco/ableton-linux/releases/latest/download/install-ableton-latest.run) (versioned builds are on the Releases tab)
3. If your Ableton archive is in the same place (or in `~/Proprietary`), run the downloaded installer script and follow the instructions.

You can do that either by double clicking the `install-ableton-latest.run` installer, or running this command from your Downloads directory

```
sh ~/Downloads/install-ableton-latest.run
```

## Updating

You can update your existing installation by downloading a new version of the run script, and running it:

`sh install-ableton-latest.run --update`

## Nix and NixOS

The repo is also a Nix flake that builds the whole stack from source — the patched Wine, PipeASIO, and the launcher — as one package. The `.run` installer above remains the path for every other distro.

Quick start (flakes enabled, x86_64-linux only):

```bash
# 1. put your ableton_live*.zip (any edition, from ableton.com) in ~/Proprietary
# 2. build the runtime and create the prefix — installs Live from that zip
nix run github:shibco/ableton-linux#setup-prefix
# 3. launch
nix run github:shibco/ableton-linux
```

The first build compiles Wine from source (no binary cache) and takes a while; after that everything comes from your Nix store. The prefix step is per user and idempotent — rerunning it later heals the prefix without touching Live. Host requirements: a running PipeWire daemon and `/dev/ntsync` (kernel 6.14+ with the `ntsync` module; `scripts/check-ntsync.sh` verifies).

For daily use prefer `nix profile install github:shibco/ableton-linux` (or the NixOS config below) over bare `nix run`: `nix run` leaves no GC root, so a `nix-collect-garbage` deletes the compiled Wine and the next run rebuilds it.

### NixOS configuration

```nix
# flake.nix
inputs.ableton-linux.url = "github:shibco/ableton-linux";
# No nixpkgs.follows on purpose: the flake pins the nixpkgs its Wine was built
# and tested against; following your system nixpkgs rebuilds Wine from source
# on every channel bump.
```

```nix
# configuration.nix
{ inputs, ... }: {
  environment.systemPackages = [
    inputs.ableton-linux.packages.x86_64-linux.default
    # or pin per-machine settings:
    # (inputs.ableton-linux.packages.x86_64-linux.default.override {
    #   dpi = 120;                 # prefix LogPixels (96=100%, 112≈117%, 120=125%, 144=150%)
    #   pipeasioBufferSize = 256;  # match your PipeWire quantum
    #   pipeasioInputs = 2;
    #   pipeasioOutputs = 2;
    # })
  ];
  services.pipewire.enable = true;
}
```

This puts `ableton-live` on every user's PATH. Each user still runs the one-time `nix run github:shibco/ableton-linux#setup-prefix` — the prefix is per-user state in `~/.wine-ableton`, not something a system rebuild can produce. Desktop menu entries are not registered automatically; templates ship in the package under `share/ableton-wine/desktop/`.

## Issues?

File an issue on GitHub, there's some diagnostics scripts that will help diagnose the problem in ./beta/scripts.

## First launch

A few more things to do after you launch for the first time:

1. Ableton's Settings → untick Auto-Scale Plugin Window (prevents a plugin-window resize loop).
2. Preferences → Audio → Driver Type ASIO → Device PipeASIO.

If you encounter any unexpected audio behaviour, open an issue or +1 an existing one and I'll fix as a priority!

## Installing plugins

To run a plugin installer inside your Live environment:
```
WINEPREFIX=~/.wine-ableton ~/.local/opt/wine-d2d1-nspa-11.11/bin/wine \
    "/path/to/PluginInstaller.exe"
```
You can also manually install plugin .vst3 files inside the `~/.wine-ableton/drive_c/Program Files/Common Files/VST3/` directory.

## Push 1 + 2 support

This is built in. Use Preferences → Link, Tempo & MIDI → enable one `Push2` row, Live Port for both input and output, and enable the remote toggles. 

Like all other MIDI and Audio devices, Push will survive in-session disconnects. 


## Development

Requirements are:

- `podman` or `docker`
- ~10 GB disk.
- x86_64, glibc 2.35+ (any 2022+ distro)
- GNOME or KDE 
- `zstd`
- `pipewire` 0.3.56 or newer (1.6+ recommended for the lowest latency)
- `cabextract`,
- `binutils`

## Project structure

- [patches/](patches/): the Wine patch series + the pipeasio series
- [scripts/](scripts/): install, prefix setup, launcher
- [flake.nix](flake.nix) + [nix/](nix/): the Nix packaging (see "Nix and NixOS")
- [vendor/](vendor/): pinned build inputs
- [notes/](notes/): patch notes and investigations
- [tools/](tools/): diagnostic tools
- [bin/](bin/): launchers
- [dist/](dist/): build outputs
- [beta/](beta/): beta test program

## Development

If you're working on this and want to try building and installing:

```bash
./build.sh
./scripts/install.sh
./scripts/setup-prefix.sh
WINEPREFIX=~/.wine-ableton ~/.local/opt/wine-d2d1-nspa-11.11/bin/wine \
    "/path/to/Ableton Live 12 Suite Installer.exe"
ableton-live
```

### Nix build

`nix build` produces the same runtime as the container pipeline, from the same vendored sources and patch series, with build-time gates: the patch series must match `patches/SERIES.sha256`, ntsync must be compiled into wineserver and ntdll, and PipeASIO must register end to end in a throwaway prefix.

```bash
nix build .#wine-d2d1-nspa   # just the patched Wine
nix build .#pipeasio         # just the ASIO driver
nix build                    # full runtime: Wine + PipeASIO + launcher -> result/
```

### Single-file installer

`./scripts/make-installer.sh` compiles everything into `dist/ableton-wine-setup-<version>.run`.

It verifies itself, installs the runtime, detects the display scale, creates the prefix, then runs the Ableton installer it finds next to itself (pauses so you can add one; prints the manual commands otherwise). 

#### Display scale

`setup-prefix.sh` and the launcher auto-detect the display scale (GNOME, KDE, sway, Hyprland, niri, X11 `Xft.dpi`); the launcher recalibrates the prefix DPI on every start. Unfortunately, switching monitors still needs a Live restart if those monitors have different DPIs. You can manually override the default scaling behaviours with `ABLETON_DPI_MODE`.

### Other environment variables

Mostly unnecessary. But in case you need them: 

- `ABLETON_WINE_ROOT` runtime path (default `~/.local/opt/wine-d2d1-nspa-11.11`)
- `ABLETON_WINEPREFIX` prefix path (default `~/.wine-ableton`)
- `ABLETON_DPI_MODE` `auto` | `preserve` | `100` | `fractional`
- `ABLETON_THEME_MODE` `auto` | `dark` | `light` | `preserve` — the launcher syncs Live's light/dark theme key to the desktop scheme on every start; this overrides it
- `ABLETON_LIVE_EXE` full path to a Live exe inside the prefix, when more than one edition/version is installed (default: the newest found)
- `PIPEASIO_*` audio driver overrides, e.g. `PIPEASIO_PREFERRED_BUFFERSIZE=512` if you hear crackles; defaults live in `~/.config/pipeasio/config.ini`
- `ABLETON_INSTALLER_DIR` where `setup-prefix.sh` looks for your `ableton_live*.zip` (default `~/Proprietary`)
- `ABLETON_LIVE_AUTOINSTALL` set to `0` to stop `setup-prefix.sh` from running the Ableton installer it finds
- `ABLETON_INSTALLER_UI` set to `1` for the Ableton installer window instead of the default silent install
- `ENGINE=docker` for `build.sh` / `make-installer.sh`

### Steam Deck

Desktop Mode only. Add the host packages once, and (unfortunately) again after every SteamOS update.

```bash
sudo steamos-readonly disable
sudo pacman-key --init && sudo pacman-key --populate archlinux holo
sudo pacman -S cabextract binutils
sudo steamos-readonly enable
```

## More

You can learn all about the patches here: [patches/BASE.txt](patches/BASE.txt).

Questions? [cade@parare.al](mailto:cade@parare.al)

### AI Disclosure

Local models (Qwen 3.6) and Claude Opus were used during QA testing, documentation checking, and to help setup the build pipeline at the very end of this project's release.
