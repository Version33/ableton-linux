# Ableton Live on Linux

This project installs Ableton Live 11 or 12 with a patched Wine runtime, PipeASIO audio, Ableton Link, and Linux desktop integration.

It is not affiliated with or endorsed by Ableton GmbH.

[Download the latest installer](https://github.com/shibco/ableton-linux/releases/latest/download/install-ableton-latest.run)

## What works

- Live 11 and 12, including Max for Live and Max 9
- PipeASIO 1.5 audio through PipeWire
- Windows VST2 and VST3 plugins
- Push 1 and Push 2
- Ableton Link on the local network
- Linux file dialogs, file types, application launchers, display scaling, and desktop theme matching

## Requirements

You need:

- an x86-64 Linux computer
- glibc 2.35 or newer
- PipeWire 1.4.2 or newer, both the installed library and the running service
- GStreamer with its base and good plugin sets
- Bash, GNU `timeout`, and GNU `tar`
- `zstd`
- `unzip`, `bsdtar`, or Python 3 when the Ableton download is a ZIP file
- your Ableton installation files and activation details

PipeASIO Settings also needs Qt 6. Live can use PipeASIO without that settings window.

## Install

1. Download the Ableton Live installation ZIP from Ableton.
2. Download [the latest project installer](https://github.com/shibco/ableton-linux/releases/latest/download/install-ableton-latest.run).
3. Put both files in `~/Downloads`.
4. Run:

   ```bash
   sh ~/Downloads/install-ableton-latest.run install
   ```

The installer checks the downloads and system requirements before it changes the current installation. It installs the Wine runtime, Live integration, PipeASIO, and Ableton Link. Link starts with Live by default.

Start Live from the application menu or run:

```bash
ableton-live
```

On first launch, open **Settings > Audio**. Set **Driver Type** to **ASIO** and **Audio Device** to **PipeASIO**.

## Update

Ableton Live manages its own application updates. To update this project's runtime and integration, download the latest project installer and run:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

The update keeps Live, its authorisation, projects, and PipeASIO settings. It may update compatibility-related Wine and Live settings. The installed `~/.local/share/ableton-wine/rollback.sh` restores the previous managed runtime and its saved configuration if you need to go back.

## Uninstall

Remove the runtime and desktop integration while keeping Live and its Wine prefix:

```bash
sh ~/Downloads/install-ableton-latest.run uninstall --keep-prefix
```

Delete the managed Wine prefix, including Live, its Wine-side authorisation, Windows plugins, and any other files stored inside that prefix:

```bash
sh ~/Downloads/install-ableton-latest.run uninstall --delete-prefix
```

The second command asks for confirmation. Both commands leave Live Sets stored outside the prefix unchanged.

## Live 11 and Live 12 together

The installer can keep one Live 11 edition and one Live 12 edition in the same prefix. Select Live 11 during installation with:

```bash
sh ~/Downloads/install-ableton-latest.run install --live-major 11
```

When both major versions are present, the launcher starts the newest one. Start Live 11 with:

```bash
env ABLETON_LIVE_VERSION=11 ableton-live
```

Live 11 needs a one-time Max for Live repair after its first launch. It also has a known WMA and video limitation. Follow the [Live 11 troubleshooting steps](TROUBLESHOOTING.md#live-11-max-for-live-fails-after-the-first-launch).

## Windows plugins

Copy a Windows `.vst3` bundle to:

```text
~/.wine-ableton/drive_c/Program Files/Common Files/VST3/
```

Run a Windows plugin installer inside the same prefix with:

```bash
env WINEPREFIX="$HOME/.wine-ableton" \
  "$HOME/.local/opt/wine-d2d1-nspa-11.13/bin/wine" \
  "/path/to/PluginInstaller.exe"
```

This project does not provide direct Linux VST or CLAP hosting inside Live.

## Push and Link

Live detects Push 1 automatically. For Push 2, configure one **Push2** control-surface row in **Settings/Preferences > Link, Tempo & MIDI**. Select **Ableton Push 2 Live Port** for both input and output, then enable both **Remote** switches.

For Link, enable **Show Link Toggle** in the same settings page and turn on Link in Live's control bar. Link peers must share a local network that carries multicast traffic.

## Help and development

Read [Troubleshooting](TROUBLESHOOTING.md) for current user actions. If the problem remains, use the [GitHub issue form](https://github.com/shibco/ableton-linux/issues/new/choose) or the `#issues` forum in the [Ableton on Linux Discord](https://discord.gg/SZ2cQgV7U).

Contributors can read [Building](https://github.com/shibco/ableton-linux/blob/main/BUILDING.md), the [patch provenance](https://github.com/shibco/ableton-linux/blob/main/patches/BASE.txt), and the [Code of Conduct](https://github.com/shibco/ableton-linux/blob/main/CODE_OF_CONDUCT.md).

The project is maintained by [Cade Diehm](https://shiba.computer/about) and [Lucas Gillingham](https://github.com/ClickSentinel), with contributions listed in the [changelog](https://github.com/shibco/ableton-linux/blob/main/CHANGELOG.md). It builds on the `d2d1-dcomp` work in [giang17/wine](https://github.com/giang17/wine). ENCORE by [wowitsjack](https://github.com/wowitsjack) informed several early patches.

Licence: [LICENCE](LICENCE)

Contact: [cade@parare.al](mailto:cade@parare.al)
