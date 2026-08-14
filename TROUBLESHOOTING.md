# Troubleshooting Ableton Live on Linux

Here are some common ailments we've seen, and how to fix them.

## The installer does not finish after Live installs

If an **Ableton USB Driver** window is in your taskbar, close it. The
installer then continues by itself. If there is no such window, press
Ctrl-C, then download
[the latest installer](https://github.com/shibco/ableton-linux/releases/latest/download/install-ableton-latest.run)
and run:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

An update that stops at `== [1/5] initialise prefix ==` has the same fix.
The update keeps your Live installation, your license, and your projects.

Ableton's own installer adds a small Windows helper program that Live does
not need on Linux. The helper stays open, often without any window, and
setup used to wait for it. Releases newer than 2026.08.04.1 stop the
helper themselves and remove its autostart entry, so the wait clears after
about half a minute and the stop does not come back.

## Live has no sound

Open **Settings > Audio** and select:

- **Driver Type:** ASIO
- **Audio Device:** PipeASIO

Set **Audio Device** to **None**, then select **PipeASIO** again. If the sound
breaks up, open **PipeASIO Settings** from the application menu and select a
larger buffer size.

You can also try a 512-frame buffer for one launch:

```bash
env PIPEASIO_PREFERRED_BUFFERSIZE=512 ableton-live
```

## PipeASIO Settings does not open

Live can still use PipeASIO without the settings window. Run the latest update:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

If a desktop package is missing, the update prints the exact install command
for your Linux distribution. Run that command, then open PipeASIO Settings
again. After changing a setting, set Live's **Audio Device** to **None** and
back to **PipeASIO**.

## The installer says PipeWire is too old

Your current installation is unchanged. Install your normal Linux updates and
try again. If the message remains, upgrade to a Linux release that includes
PipeWire 1.4.2 or newer. Ubuntu 24.04 and Linux Mint 22 need that distribution
upgrade before this version can install.

## Crackle with two audio devices

Select the same audio device for input and output when possible. If the
crackle stops, the two-device setup caused it.

Run the audio report after installation:

```bash
~/.local/share/ableton-wine/audio-report.sh
```

If you still hear crackle, attach the report when you
[open an issue](https://github.com/shibco/ableton-linux/issues).

## Audio cuts out for a few seconds, or plays at the wrong speed

Wait a few seconds. If audio returns at the correct speed, there is nothing
else to do. Another audio programme changed the buffer size shared with Live,
and PipeASIO paused while Live changed to the same size.

If audio stays silent or plays too fast or too slow, update this project. Until
you can update, close Live, run this command, then start Live again:

```bash
pw-metadata -n settings 0 clock.force-quantum 0
```

If the problem returns, run the audio report from the previous entry and attach
it when you open an issue.

## A plugin window resizes repeatedly or shows stale pixels

Right-click the affected plugin in Live's device rack, disable
**Auto-Scale Plugin Window**, then reopen the plugin.

This workaround is only needed for affected plugins. See the
[Pianoteq investigation](notes/ABLETON-WINE-PIANOTEQ-DPI-GHOST-BUG.md) for the
confirmed failure mode.

## Live's "Enable GPU Renderer" setting is greyed out

If you're experiencing performance issues or high CPU usage when idle, Live
may not be using your GPU. By default, Live will always offload the UI to
your GPU for maximum performance, but will only do so when it recognises
the name of your GPU. On Linux, GPUs will 'tell' Live their name without
any external interference, and because Live is anticipating that interference,
it may not recognise the GPU's name and refuse to use the GPU.

To confirm this problem, open **Settings > Display & Input**. 
If **Enable GPU Renderer** is greyed out, and the note under it names a 
graphics card that is not the one in your computer, then you're seeing this
exact problem. 

To solve it: **update this project**.

Download [the latest installer](https://github.com/shibco/ableton-linux/releases/latest/download/install-ableton-latest.run)
and run the update. It keeps your Live installation, your license, and
your projects:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

Start Live, open **Settings > Display & Input**, and turn on **Enable GPU
Renderer**. Live now names your real graphics card, and the setting stays
on.

If the setting is still greyed out on 2026.08.01.1 or newer,
[open an issue](https://github.com/shibco/ableton-linux/issues) and
include your graphics card model.

## CPU spikes when moving your mouse

Live keeps its current diagnostics in `~/.local/state/ableton-wine/logs/live.log`,
whether you start it from the desktop menu or a terminal. If Live's CPU
use jumps while you move the mouse, run:

```bash
grep -i "sustained present-size mismatch:" ~/.local/state/ableton-wine/logs/live.log
```

The beta launcher writes `live-beta.log` in the same directory; use that
filename instead when testing Live 12 Beta.

If that prints anything,
[open an issue](https://github.com/shibco/ableton-linux/issues) and paste
the whole line. It starts with `err:winediag:` and includes your desktop
environment and window DPI.

If nothing prints and Live's CPU use is still high, the cause is
different. Open an issue and describe what you were doing when it
happened.

## Live 11: Max for Live fails after the first launch

After running Live 11 once, close Live and run:

```bash
sh ~/Downloads/install-ableton-latest.run --extract /tmp/ableton-kit
bash /tmp/ableton-kit/scripts/installer.sh prefix repair-live11
```

The repair moves Max 8's incompatible preferences to a timestamped backup.
Max creates a clean preferences file when it next starts.

## Live 11: media files can crash Live

Do not preview or import WMA or video files in Live 11. Wine's current
`wmvcore.dll` implementation can crash Live on that path. Live 12 does not use
the affected path.

See the [WMVCore investigation](notes/ABLETON-WINE-LIVE11-WMVCORE-STUB.md).

## The launcher finds more than one Live installation

When both Live 11 and Live 12 are installed, `ableton-live` starts the newest
major version. Select Live 11 with:

```bash
env ABLETON_LIVE_VERSION=11 ableton-live
```

When one prefix contains multiple editions of the same major version, the
launcher refuses to guess. Set `ABLETON_LIVE_EXE` to the exact executable you
want to start.

## Using Linux-native plugins

Linux-native VST and CLAP integration is not implemented in this project yet.
The experimental workaround runs the plugin in Carla and routes audio and MIDI
through PipeWire.

See [Linux-native plugin routing](notes/ABLETON-WINE-PLUGIN-BRIDGING.md) for
the current test procedure and limitations.

## Push 2 does not connect

Configure exactly one `Push2` control-surface row with **Ableton Push 2 Live
Port** as both its input and output. Remove duplicate `Push2` rows, close Live
normally, then reconnect Push 2 and start Live again.

See the [Push 2 display bridge note](notes/ABLETON-WINE-PUSH2-DISPLAY.md) for
USB diagnostics.

## Ableton Link does not find peers

Link peers must share a local network that carries multicast. Many guest and
public Wi-Fi networks block multicast. Multicast also stops at a VPN tunnel:
peers on the far side of a VPN cannot be discovered, while peers on your own
network remain reachable with the VPN connected.

Check these in order:

1. If you run a firewall, allow UDP port 20808.
2. If you installed with `--no-link`, run the installer again with `--link`.
3. Otherwise, close Live and retry the setup:

   ```bash
   ~/.local/share/ableton-wine/setup-link.sh
   ```

Start Live and enable **Show Link Toggle** and Link again. See
[Ableton Link diagnostics](notes/ABLETON-WINE-LINK.md) if peers still do not
appear.

## Audio latency remains high

Lower the buffer size with **PipeASIO Settings** in your application menu
(`pipeasio-settings` in a terminal), then set **Audio Device** in Live to
**None** and back to **PipeASIO**. A lower value shortens the delay but gives
Live less time to process audio. Raise it again if the sound breaks up. This
setting does not reduce the CPU used by Live or plugins.

Run the real-time audio setup once:

```bash
~/.local/share/ableton-wine/setup-realtime.sh
```

The script asks for `sudo`. Log out and back in after it finishes.

On Pop!_OS and other System76 computers, do not install the
`power-profiles-daemon` package. The package manager removes the System76
power management tools to make room for it. Use the power settings in your
desktop instead.

Earlier releases kept the CPU at full speed from every boot instead.
Remove that old boot setting with:

```bash
sudo systemctl disable ableton-cpufreq-performance.service
sudo rm /etc/systemd/system/ableton-cpufreq-performance.service
sudo systemctl daemon-reload
```

You can also run `~/.local/share/ableton-wine/setup-realtime.sh` again to
remove the old setting.

## Display scaling is wrong

Restart Live after moving it between monitors with different scale factors.
Override automatic detection for one launch with `ABLETON_DPI_MODE`; available
values are listed in [the build and configuration reference](BUILDING.md#environment-variables).

## Full Screen shows shifted content or does not fully exit

Update to a release newer than 2026.08.01.1. On 2026.08.01.1 and older,
**View > Full Screen** and F11 show Live's content shifted, clicks land away
from their targets, and leaving fullscreen keeps the fullscreen image on
screen until the window is moved.

Download [the latest installer](https://github.com/shibco/ableton-linux/releases/latest/download/install-ableton-latest.run)
and run the update. It keeps your Live installation, your license, and
your projects:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

Until you can update, drag Live's window once after leaving fullscreen to
clear the stuck image.

If fullscreen is still wrong after the update, launch once with
`WINE_WIN32_FULLSCREEN_CLASS=off ableton-live`, then
[open an issue](https://github.com/shibco/ableton-linux/issues) and include
your desktop environment and whether that launch behaved differently.

## GNOME handles a Live shortcut instead of Live

GNOME uses Ctrl+Alt+Up and Ctrl+Alt+Down for workspace switching. These keys
conflict with Live's **Adjust Note Selection Chance** shortcuts. GNOME also
uses Ctrl+Alt+Delete for logout, which conflicts with **Delete Fades** in
Live 11.

Start Live with this command:

```bash
env ABLETON_SHORTCUTS=take ableton-live
```

The launcher turns off only the exact Ctrl+Alt entries in conflict. It keeps
other keys and modifiers in the same settings. It restores the saved entries
after all Live sessions exit. It can also restore them after a crash. If you
change a shortcut while Live runs, it keeps your change.

The change applies to the complete GNOME session. The keys cannot switch a
workspace or open the logout dialog in another application while Live runs.

The default `ABLETON_SHORTCUTS=preserve` leaves every desktop shortcut
unchanged. For another desktop, change its shortcut settings when necessary.

## Report a problem

Use the [GitHub issue form](https://github.com/shibco/ableton-linux/issues/new/choose).
Include the Live edition, this project's release number, Linux distribution,
desktop environment, and the exact action that failed. Do not attach Ableton
installers, authorization files, licence keys, projects, or plugin credentials.
