# Ableton Live on Linux

![Ableton Live running on Linux](screenshot.png)

Produce and perform with Ableton Live on a self-sovereign, open-source
stack. This project makes the popular Berlin-based DAW and its ecosystem of products a first-class Linux citizen, with zero compromises.

It is also absolutely **not affiliated with or endorsed in any way by Ableton
AG** and respects the Ableton terms of service.

[Download the latest installer](https://github.com/shibco/ableton-linux/releases/latest/download/install-ableton-latest.run)

## Features

- Live 12 Intro, Standard, Suite, Lite, Trial, and beta support
- Experimental Live 11, Max for Live, and Max 9 support
- Push 1 and Push 2 support (Push 3 and Move support coming soon!)
- Local-network Ableton Link support
- Experimental support for Ableton's forthcoming Extensions SDK
- Compatibility with Ableton's Splice integration
- Automatic recovery when in-use audio hardware or startup-detected MIDI
  controllers briefly disconnect
- Low-latency PipeASIO audio for live performance
- Linux desktop integration with native file types and dialogs
- Automatic light and dark desktop theme detection
- No-fuss support for desktop resolutions, HiDPI displays, and fractional scaling
- Fixes for VST-specific display, audio, and stability problems
- Dozens of nice-to-haves, quality-of-life fixes, and other polish
- Auditable builds with pinned inputs, checksum verification, and public documentation

## Installation

### Requirements

You need an x86-64 Linux system that meets Ableton Live's hardware requirements.

Additionally, you need:

- glibc 2.35 or newer
- PipeWire 1.4.2+ recommended (earlier versions will work but are not supported)
- GStreamer with its base and good plugin sets
- GNU coreutils, `tar`, `zstd`, and `flock`
- your installation files and activation details from Ableton

For most people, a modern and up-to-date Linux distribution, such as SteamOS,
Ubuntu, CachyOS, or Arch, will already fulfil these requirements. Debian 12,
Linux Mint, and Pop!_OS 24.04 and earlier ship an older PipeWire, so see
[getting PipeWire 1.4.2](TROUBLESHOOTING.md#the-installer-says-pipewire-is-too-old)
before you install.

### Getting started

Even if you are new to Linux, getting Ableton Live to run on Linux is usually
straightforward:

1. Download the Ableton Live installation ZIP from Ableton.com.
2. Download [the latest version of our installer](https://github.com/shibco/ableton-linux/releases/latest/download/install-ableton-latest.run).
3. From a terminal, run this command:

   ```bash
   sh ~/Downloads/install-ableton-latest.run install \
     --live-installer "$HOME/Downloads/Ableton Live 12 Installer.zip" \
     --link=session
   ```

For best results, double-check the name of the Ableton installer you have downloaded. If you run the installer by itself without explicitly pointing to an Ableton Live archive, the installer will try to find one in the same directory.

Once started, this is a mostly automated process.

Near the end, the installer may name a program still running in the Wine prefix and ask whether to close it. Pressing Enter leaves it running, which is the safe answer if you also have Max or another Wine program open. Live is already installed by that point, so either answer keeps it.

### Nix and NixOS

This repository is also a Nix flake. It builds the whole stack from source —
the patched Wine, PipeASIO, the Ableton Link peer, and the launchers — as one
package. The `.run` installer above stays the path for every other distribution.

Flakes must be enabled, and only `x86_64-linux` is supported:

```bash
# 1. Put your Ableton Live installation ZIP in ~/Proprietary.
# 2. Build the runtime and create the Wine prefix. ABLETON_LIVE_AUTOINSTALL=1
#    opts in to running that ZIP's installer silently, so Ableton's licence
#    appears on Live's first launch. Leave it unset to install Live yourself.
ABLETON_LIVE_AUTOINSTALL=1 nix run github:shibco/ableton-linux#setup-prefix
# 3. Launch Live.
nix run github:shibco/ableton-linux
```

The first build compiles Wine from source, because no binary cache serves it.
After that everything comes from your Nix store. The prefix step is per user
and safe to re-run: it heals the prefix without touching Live. The Live 12
support files (corefonts, vcrun2022, mfc42) come from the winetricks cache
vendored in the package, so that step needs no network. The Live 11 recipe
still downloads its extras; see the [Live 11 instructions](#live-11).

Unlike the `.run` install, which uses the GStreamer plugins already on your
system, the flake pins its own decoder set — base, good, bad, ugly and libav —
so a minimal NixOS needs no media packages for Live's browser to preview
mp3/mp4/wma. That also puts ffmpeg in the closure, which is the main reason
this package is larger than the tarball.

Your host needs a running PipeWire daemon and `/dev/ntsync` (kernel 6.14 or
newer with the `ntsync` module); `test -c /dev/ntsync` answers that. To also
prove the runtime uses the device, run
`nix run github:shibco/ableton-linux#check-ntsync` with Live closed — it drives
its own wineserver on your prefix. The `scripts/check-ntsync.sh` in a checkout
looks for the Wine runtime under `~/.local/opt`, which Nix never creates.

For daily use, prefer `nix profile install github:shibco/ableton-linux`, or the
NixOS configuration below, over a bare `nix run`: a profile install also
registers the menu entries and upgrades in one step. What a `nix run` no longer
loses is the build. The first Live launch (and `setup-link`) points
`~/.local/share/ableton-wine/runtime` at the running package and registers it as
an indirect GC root, so `nix-collect-garbage` keeps the compiled Wine; deleting
that symlink releases it.

That link is also the only runtime path this package writes into your
configuration. The authorisation handler entries the launcher installs and the
`ableton-linkd` user unit `setup-link` writes both go through it, never through a
store path: an upgrade re-points the link on the next launch instead of leaving
them pinned to a package hash that a garbage collection can delete.

Two optional apps mirror the `.run` installer's extra steps. Both change host
policy: `setup-realtime` needs `sudo`, and `setup-link` asks for it only when it
has something to change.

```bash
nix run github:shibco/ableton-linux#setup-realtime  # pro-audio profile
nix run github:shibco/ableton-linux#setup-link      # Ableton Link networking
```

`setup-realtime` installs the realtime scheduling limits, swappiness and CPU
governor settings; the launcher's realtime probe picks them up after a re-login.
`setup-link` opens UDP port 20808 on an active firewall and enables the
`ableton-linkd` user service that anchors the Link session. The launcher starts
that daemon itself when the service is not enabled, so Link works either way.

Live 11 works as it does with the `.run` installer:

```bash
ABLETON_LIVE_VERSION=11 nix run github:shibco/ableton-linux#setup-prefix
```

Live 11 bundles Max for Live 8, which crashes on its *second* start if it finds
a stale preferences file. After Live 11's first launch, run the fixup once:

```bash
nix run github:shibco/ableton-linux#setup-prefix -- --post-first-run
```

It moves that preferences file aside so Max regenerates it, never deletes it, and
is safe to re-run. It needs no Wine and skips every other setup step. Live 12
does not need it.

#### NixOS configuration

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
    # or pin PipeASIO audio settings declaratively — the launcher exports each
    # pin as the driver's own PIPEASIO_* override, which beats config.ini/panel
    # edits without touching that file; unpinned keys keep following config.ini,
    # and PIPEASIO_* variables you set yourself still win per launch:
    # (inputs.ableton-linux.packages.x86_64-linux.default.override {
    #   pipeasioSettings = {
    #     buffer_size = 256;             # frames; match your PipeWire quantum
    #     inputs = 2; outputs = 2;       # hardware channel counts
    #     # output_device = "Scarlett 18i20"; sample_rate = 48000; ...
    #   };
    # })
    # Display scale needs no pin: the launcher auto-detects it, and
    # ABLETON_DPI_MODE overrides it per launch (see BUILDING.md).
  ];
  services.pipewire.enable = true;
}
```

This puts `ableton-live` on every user's PATH. Each user still runs the one-time
`nix run github:shibco/ableton-linux#setup-prefix`, because the Wine prefix is
per-user state in `~/.wine-ableton`, not something a system rebuild can produce.
Desktop menu entries ship rendered in `share/applications/`, so a profile install
or `environment.systemPackages` puts Ableton Live in the menu automatically. A
bare `nix run` registers nothing.

Standalone Max 9, installed into the same prefix with `msiexec`, launches with
`max9` from the package. Its menu entries are staged but not active, because the
store cannot see whether Max is installed. Copy them from
`share/ableton-wine/desktop/` into `~/.local/share/applications` if you use Max,
and point their `Exec=` at `~/.local/share/ableton-wine/runtime/bin/max9`: unlike
the entries the launcher maintains, a plain copy keeps the package path it was
rendered with and stops working when that package goes away.

### Running Live

Start Ableton Live the way you normally start applications on your Linux OS.

You can also start Live from the applications menu or via the command line:

```bash
ableton-live
```

You can also specify a Live Set to quickly open on launch:

```bash
ableton-live "/path/to/Your Set.als"
```

For Live 11, follow the [Live 11 instructions](#live-11).

### First launch

When you first start Live, you'll need to set up your audio. Go to
**Settings > Audio**, set **Driver Type** to **ASIO**, and set
**Audio Device** to **PipeASIO**.

### Updates

Ableton Live handles its own application updates, but to protect your privacy,
we intentionally designed this project to **not** update itself automatically. 

To get the latest updates and functionality, [find and download the latest release](https://github.com/shibco/ableton-linux/releases/latest),
then from a terminal, use this command:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

The update process will install new fixes and features listed in the release notes 
to your Live Linux environment. Your Live installation, authorization, and projects will
be preserved, but anything related to the Runtime (and Live's settings) may be updated.

### Uninstalling

To remove this project's runtime and desktop integration while keeping Live and
its authorization:

```bash
sh ~/Downloads/install-ableton-latest.run uninstall --keep-prefix
```

By default, this will not delete your copy of Live and any VSTs. To get rid of everything, including Live, its authorization, and any third-party plugins:

```bash
sh ~/Downloads/install-ableton-latest.run uninstall --delete-prefix
```

### Other functionality 
Our installer supports a range of commands for advanced users or complicated
use cases. To understand what you can do with the installer, take a look at
the [full list of available commands](INSTALLER.md).

## Running different versions of Ableton Live on the same computer

This installer brings Linux compatibility to every edition of Live 11 and 12.
We worked hard on this! You can install one Live 11 edition and one Live 12
edition together.

### Live 12

The installer detects Live 12 from the named Ableton installer file. If it
cannot identify a renamed file, pass `--live-major 12` explicitly.

### Live 11

We support Live 11, but with limited resources, we are choosing to focus on
Live 12 for now. Live 11 works well in most cases, but has seen less testing
than Live 12.

To install Live 11:

1. In your terminal window, tell the installer you want to install Live 11:

   ```bash
   sh ~/Downloads/install-ableton-latest.run install \
     --live-installer "$HOME/Downloads/Ableton Live 11 Installer.zip" \
     --live-major 11
   ```

   The first setup downloads extra Live 11 support files, so it needs internet
   access.

2. After the first launch, complete the
   [one-time Max for Live repair](TROUBLESHOOTING.md#live-11-max-for-live-fails-after-the-first-launch).

3. Before importing WMA or video files, read the
   [Live 11 media limitation](TROUBLESHOOTING.md#live-11-media-files-can-crash-live).

When you run Live from the command line, the launcher will automatically detect
Live 11 if it is the only version installed. If Live 11 and Live 12 are both
installed, the launcher defaults to the newest major version.

To launch a specific version of Live, use `env ABLETON_LIVE_VERSION=11 ableton-live` to specify it. If you install
multiple editions of the same major version, follow the
[launcher troubleshooting](TROUBLESHOOTING.md#the-launcher-finds-more-than-one-live-installation).

## Instruments and Effects

We are working on ensuring compatibility with as many VSTs as possible.
This is an ongoing process, and we will soon launch a compatibility and 
stability table to track requested VSTs and plugins.

There are two ways to install Windows plugins:

### If you have a Windows installer

1. Download your VST's installer.
2. Open a terminal window and run:

   ```bash
   env WINEPREFIX="$HOME/.wine-ableton" \
     "$HOME/.local/opt/wine-d2d1-nspa-11.13/bin/wine" \
     "/path/to/PluginInstaller.exe"
   ```

   On Nix that path does not exist, because the runtime lives in the Nix
   store. Use the flake's Wine, which targets `~/.wine-ableton` itself:

   ```bash
   nix run github:shibco/ableton-linux#wine -- "/path/to/PluginInstaller.exe"
   ```

   With the package in a profile or in `environment.systemPackages`, the same
   runner is on your PATH as `ableton-wine`.

3. Your installer should install directly into your Ableton environment. By
   default, this is `~/.wine-ableton`.

Either command in step 2 also runs patches, software updaters, and
copy-protection tools.

### If you have a VST3 file

You can install Windows `.vst3` bundles by copying them directly into:

```text
~/.wine-ableton/drive_c/Program Files/Common Files/VST3/
```

### If you have a Linux VST or CLAP instrument or effect

We are working on proper Linux VST and CLAP support, but it is not implemented
in this project yet. For now, an
[experimental Carla workflow](TROUBLESHOOTING.md#my-linux-vst-or-clap-plugins-dont-appear-in-live)
can route Linux-native plugins through PipeWire.

## Hardware

This project supports Ableton Push alongside common audio interfaces and MIDI
controllers.

### Ableton Push 1 and 2 setup

1. Connect your Ableton Push.
2. Launch Ableton Live.

Live detects Push 1 automatically.

For Push 2, configure exactly one control-surface row under
**Settings/Preferences > Link, Tempo & MIDI**:

- **Control Surface:** Push2
- **Input:** Ableton Push 2 Live Port
- **Output:** Ableton Push 2 Live Port

Enable the input and output **Remote** switches. See
[Push troubleshooting](TROUBLESHOOTING.md#push-2-does-not-connect) if its
display does not start.

## Ableton Link

Link keeps Live in time with other music software and devices on your local
network. This project sets Link up as a background service that runs while Live
is open.

### Using Link

1. Enable **Show Link Toggle** under
   **Settings/Preferences > Link, Tempo & MIDI**.
2. Enable **Link** in Live's control bar.

Devices on the same local network appear automatically. See
[Link troubleshooting](TROUBLESHOOTING.md#ableton-link-does-not-find-peers) if
no peers appear.

### Choosing when Link runs

When you install Ableton Live, by default we include Link via a custom-designed
system service called `ableton-linkd`. This service starts when you launch Live or Max
and closes when those applications close. This is `session` mode.

During installation, you can change this depending on your own preference. To do so, 
append `--link` to any `install` or `update` command:

- `--link=session` runs Link while Live or Max is open. This is the default.
- `--link=always` starts Link after you log in and keeps it running.
- `--link=off` turns Link off and leaves it off your system.

The installer remembers your choice, so an update keeps it until you ask for
something else. 

If you have an active firewall, such as `ufw` or `firewalld`, Link needs a port
opened before it can reach other peers. The installer detects an active firewall
and asks for admin privileges to allow Link through.

### Changing your choice later

You can change your preference for how Link runs on your computer at any time 
without reinstalling.

For example, to run Link when your computer starts: 

```bash
sh ~/Downloads/install-ableton-latest.run link enable --mode=always
```

To turn Link off:

```bash
sh ~/Downloads/install-ableton-latest.run link disable
```

This removes only the Link files, settings, and firewall rule that this project
added. Run `link status` to see whether Link is running.

## Getting help

This project is still in active development. If you run into problems, **do not
think that your problem is too small**. 

Start with the [common troubleshooting steps](TROUBLESHOOTING.md).

If you're still stuck, file an issue [on GitHub](https://github.com/shibco/ableton-linux/issues/new/choose)
or come visit us in the [Ableton on Linux Discord](https://discord.gg/SZ2cQgV7U). 
When you post issues in our `#issues` Discord forum, we sync your posts to GitHub, 
to keep our knowledge from being locked away inside a hidden Discord server.

## Development and contributing

We welcome all kinds of contributions. If you've found a fix for a niche VST
or a workaround for a particular environment, please tell us!

Start with:

- [Build from source](BUILDING.md)
- [Implementation notes](notes/)

Contributors must follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Credits

Maintained by [Cade 'shibco' Diehm](https://shiba.computer/about) and
[Lucas 'ClickSentinel' Gillingham](https://github.com/ClickSentinel), with help from
[trendwhore](https://github.com/trendwhore), 
[jackson-57](https://github.com/jackson-57),
[jttdev](https://github.com/jttdev),
[astrazds](https://github.com/astrazds),
[Version33](https://github.com/Version33), and
[0tanh](https://github.com/0tanh). [yioannides](https://github.com/yioannides)
made the application and MIME icons.

This project is based on the `d2d1-dcomp` stack from 
[giang17/wine](https://github.com/giang17/wine), specifically, we forked
from branch `d2d1-dcomp-11.13` and `5c23dd1c` to continue building our work 
from these solid foundations. _Thank you! <3_ 

ENCORE by [wowitsjack](https://github.com/wowitsjack) informed some early patches.

Questions: [cade@parare.al](mailto:cade@parare.al)

## AI Disclosure

This project uses open-source local models Qwen 3.8 and Kimi K3 to assist with diagnosis, research, QA, documentation review, and build scripts. We will not accept fully-vibecoded contributions as the risk of regression is too high.
