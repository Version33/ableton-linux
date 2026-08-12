# Troubleshooting Ableton Live on Linux

Here are some common ailments we've seen, and how to fix them.


## The installer does not finish after Live installs

Close any **Ableton USB Driver** window. If no window appears, wait 30 seconds.
This delay comes from Ableton's own installer and clears by itself.

If the installer still has not finished after a minute, press Ctrl-C, run the
same command again, and note the last line it printed.

## Online authorization does not return to Live

Run the latest update:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

Start Live once from the application menu and try authorizing again. If the
browser still does not return to Live, check the registered handler:

```bash
xdg-mime query default x-scheme-handler/ableton
```

It should print `io.github.shibco.ableton-linux.protocol.desktop`. Compare the
launcher and desktop handoff with a harmless test address:

```bash
ableton-live 'ableton://invalid-ableton-linux-probe'
xdg-open 'ableton://invalid-ableton-linux-probe'
```

The address cannot authorize Live. If the first command works and the second
fails, log out and back in, then repeat both commands. If both work, try a
fresh browser profile or a browser package from another source.

Never share a real authorization address or `.auz` file. When reporting the
problem, include the handler result, browser package, and which test commands
opened Live.

## Live cannot save a clip or track in the Browser

Drag the same item into the User Library. If that works, Live cannot write to
the original folder. Check the folder with:

```bash
test -w "/path/to/folder" && echo writable || echo not-writable
stat -f -c 'filesystem=%T' -- "/path/to/folder"
```

Choose another folder or correct its ownership if the first command prints
`not-writable`. System folders, read-only mounts, and `/nix/store` cannot
accept new Live files.

If the folder and User Library both fail, run the profiler from a repository
checkout:

```bash
env ABLETON_LIBRARY_PATH="/path/to/folder" ./beta/scripts/ableton-linux-profiler.sh
```

The profiler does not print the folder path. Include its output, the Live
version and edition, and whether the User Library worked when reporting the
problem.

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

If a Qt 6 package is missing, the update prints the exact install command
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

If you still hear crackle, read the report and remove any private paths,
environment values, or log text that you do not want to publish. Attach the
relevant section when you
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

Open **Settings > Display & Input**. If **Enable GPU Renderer** is greyed out,
or Live names the wrong graphics card, update this project:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

Restart Live and turn on **Enable GPU Renderer**.

If the setting is still greyed out on an Intel GPU, start Live with:

```bash
env WINE_D3D_FORCE_GPU_RENDERING=1 ableton-live
```

This temporarily reports a supported Intel model to Live. The substituted
model remains visible in Live, so start Live normally before sending a report
to Ableton.

If problems continue, [open an issue](https://github.com/shibco/ableton-linux/issues)
and include your real graphics card model.

## CPU spikes when moving your mouse

Live keeps its current diagnostics in
`$XDG_STATE_HOME/ableton-wine/logs/live.log` (by default,
`~/.local/state/ableton-wine/logs/live.log`), whether you start it from the
desktop menu or a terminal. If Live's CPU use jumps while you move the mouse,
run:

```bash
grep -i "sustained present-size mismatch:" \
  "${XDG_STATE_HOME:-$HOME/.local/state}/ableton-wine/logs/live.log"
```

If that prints anything, [open an issue](https://github.com/shibco/ableton-linux/issues)
and paste the whole line. If it prints nothing, describe what you were doing
when the CPU use increased.

## Live 11: Max for Live fails after the first launch

After running Live 11 once, close Live and run:

```bash
sh ~/Downloads/install-ableton-latest.run extract /tmp/ableton-kit
bash /tmp/ableton-kit/scripts/installer.sh prefix repair-live11
```

The repair moves Max 8's incompatible preferences to a timestamped backup.
Max creates a clean preferences file when it next starts.

## A newly installed font does not show up inside Live

Close Live, then start it with the saved font list turned off:

```bash
env WINE_DISABLE_HOST_FONT_CACHE=1 ableton-live
```

Live keeps a saved list of your computer's fonts so it can start faster.
The launch above skips that list and reads your fonts directly.

If the missing font appears now, delete the saved list and start Live
normally. Live rebuilds the list with your new font:

```bash
rm ~/.wine-ableton/drive_c/windows/wine-host-font.cache
ableton-live
```

If the font is still missing with the list turned off, the list is not
the cause. [Open an issue](https://github.com/shibco/ableton-linux/issues)
and name the font and where you installed it from.

## A fader jumps after loading a Max for Live device

Install the latest release, then start a fresh Live session. Load the affected
Max for Live device and drag a track fader without clicking the device first.

The fader should follow the pointer without jumping. If it still jumps, report
the device, Linux distribution, desktop, and Live version. Say whether clicking
the device once stops the problem.

## An XWayland fader or knob moves farther than the pointer

Lower the Master fader before comparing these settings.

Compare these three one-launch settings:

```bash
env WINE_X11_WARP_EMULATION=disabled ableton-live
env WINE_X11_WARP_EMULATION=auto ableton-live
env WINE_X11_WARP_EMULATION=enabled ableton-live
```

Report which setting made the control follow the pointer most closely, whether
the pointer was visible, your pointing device, Linux distribution, desktop,
and Live version. Do not save `enabled`; it is only for comparison.

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

Link peers must share a local network that carries multicast. Guest networks,
public Wi-Fi, and the far side of a VPN may block discovery.

Check the current setting:

```bash
sh ~/Downloads/install-ableton-latest.run link status
```

If it reports `policy: off`, enable Link for the current session:

```bash
sh ~/Downloads/install-ableton-latest.run link enable --mode=session
```

The command may ask for `sudo` when a supported firewall needs to allow UDP
port 20808. Start Live and enable **Show Link Toggle** and Link again. See
[Ableton Link diagnostics](notes/ABLETON-WINE-LINK.md) if peers still do not
appear.

## Audio latency remains high

Lower the buffer size with **PipeASIO Settings** in your application menu
(`pipeasio-settings` in a terminal), then set **Audio Device** in Live to
**None** and back to **PipeASIO**. A lower value shortens the delay but gives
Live less time to process audio. Raise it again if the sound breaks up. This
setting does not reduce the CPU used by Live or plugins.

Run the optional real-time audio setup once:

```bash
~/.local/share/ableton-wine/setup-realtime.sh
```

The script changes system audio settings and asks for `sudo`. Log out and back
in after it finishes.

On Pop!_OS and other System76 computers, do not install the
`power-profiles-daemon` package. The package manager removes the System76
power management tools to make room for it. Use the power settings in your
desktop instead.

If an older release left the CPU at full speed after reboot, run the script
again. It removes the old setting.

## Display scaling is wrong

Restart Live after moving it between monitors with different scale factors.
Automatic detection is already the default. If scaling remains wrong at 125%,
compare one explicit launch.

On GNOME, run:

```bash
env ABLETON_DPI_MODE=fractional ableton-live
```

On KDE, Sway, Hyprland, COSMIC, or X11, run:

```bash
env ABLETON_DPI_MODE=dpi120 ableton-live
```

The other supported values are listed in
[the build and configuration reference](BUILDING.md#current-configuration).

## Full Screen shows shifted content or does not fully exit

If **View > Full Screen** or F11 shifts Live's content, makes clicks land away
from their targets, or leaves the fullscreen image behind when you exit,
update this project.

Download [the latest installer](https://github.com/shibco/ableton-linux/releases/latest/download/install-ableton-latest.run)
and run:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

If fullscreen is still wrong after the update, launch once with
the fullscreen adjustment disabled:

```bash
env WINE_WIN32_FULLSCREEN_CLASS=off ableton-live
```

If that changes the result, [open an issue](https://github.com/shibco/ableton-linux/issues)
and include your desktop environment and display scale.

## GNOME handles a Live shortcut instead of Live

GNOME reserves Ctrl+Alt+Up, Ctrl+Alt+Down, and Ctrl+Alt+Delete before Live can
see them. Start Live with:

```bash
env ABLETON_SHORTCUTS=take ableton-live
```

The launcher releases those shortcuts while Live runs and restores them after
the last Live session exits. They remain unavailable to other applications
during that time.

The default `ABLETON_SHORTCUTS=preserve` leaves every desktop shortcut
unchanged. For another desktop, change its shortcut settings when necessary.

## Scrolling, middle-button panning, or pinch zoom misbehaves

Mute or disconnect monitoring before reproducing a problem that can change a
fader. Start with Live's Master fader low and use a limiter.

Try the relevant command for one launch:

```bash
# Smooth scrolling
env WINE_X11_SMOOTH_SCROLLING=disabled ableton-live

# Pinch zoom
env WINE_X11_PINCH_ZOOM=disabled ableton-live

# Middle-button navigation
env WINE_X11_MIDDLE_DRAG=disabled ableton-live

# Scrolling after release
env WINE_X11_TOUCHPAD_INERTIA=disabled ableton-live

# Middle-button movement after release
env WINE_X11_MIDDLE_DRAG_THROW=disabled ableton-live

# Mouse wheel while holding another button
env WINE_X11_WHEEL_WHILE_BUTTON_HELD=disabled ableton-live
```

Scrolling inertia and middle-drag throw are on by default and work
independently. If a saved setting switched either one off, restore it for one
launch:

```bash
env WINE_X11_TOUCHPAD_INERTIA=enabled ableton-live
env WINE_X11_MIDDLE_DRAG_THROW=enabled ableton-live
```

If scrolling feels too sensitive, use whole wheel steps:

```bash
env WINE_X11_SMOOTH_SCROLLING=notched ableton-live
```

If turning a feature off changes the result, report the command you used, your
pointing device, Linux distribution, desktop, and Live version.

## Report a problem

Use the [GitHub issue form](https://github.com/shibco/ableton-linux/issues/new/choose).
Include the Live edition, this project's release number, Linux distribution,
desktop environment, and the exact action that failed.

The current launcher log is
`$XDG_STATE_HOME/ableton-wine/logs/live.log` (by default,
`~/.local/state/ableton-wine/logs/live.log`). Read any log or audio report
before sharing it. Do not attach Ableton installers, authorization files,
licence keys, Live Sets, samples, or plugin credentials.
