# Troubleshooting Ableton Live on Linux

Use the action under the symptom you see. Update this project before reporting a problem:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

An update keeps Live, its authorisation, projects, and PipeASIO settings. It may update compatibility-related Wine and Live settings.

## The installer does not finish

If an **Ableton USB Driver** window is open, close it and wait for setup to continue. If the current installer still stops, press Ctrl-C, run it again, and note the last line it printed.

## Online authorisation does not return to Live

Run the current project update, start Live once from the application menu, and try authorising again. If the browser still does not return to Live, check the registered handler:

```bash
xdg-mime query default x-scheme-handler/ableton
```

It should print `io.github.shibco.ableton-linux.protocol.desktop`. Compare the launcher and desktop handoff with a harmless test address:

```bash
ableton-live 'ableton://invalid-ableton-linux-probe'
xdg-open 'ableton://invalid-ableton-linux-probe'
```

The address cannot authorise Live. If the first command works and the second fails, log out and back in, then repeat both commands. If both work, compare a fresh browser profile or a browser package from another source.

Never share a real authorisation address or `.auz` file. When reporting the problem, include the handler result, browser package, and which test commands opened Live.

## Live cannot save a clip or track in the Browser

Drag the same item into the User Library. If that works, Live cannot write to the original folder. Check the folder with:

```bash
test -w "/path/to/folder" && echo writable || echo not-writable
stat -f -c 'filesystem=%T' -- "/path/to/folder"
```

Choose another folder or correct its ownership if the first command prints `not-writable`. System folders, read-only mounts, and `/nix/store` cannot accept new Live files.

If the folder and User Library both fail, run the profiler from a repository checkout:

```bash
env ABLETON_LIBRARY_PATH="/path/to/folder" ./beta/scripts/ableton-linux-profiler.sh
```

The profiler does not print the folder path. Include its output, the Live version and edition, and whether the User Library worked when reporting the problem.

## Live has no sound

Open **Settings > Audio** and select:

- **Driver Type:** ASIO
- **Audio Device:** PipeASIO

Set **Audio Device** to **None**, then select **PipeASIO** again. If sound breaks up, open **PipeASIO Settings** from the application menu and choose a larger buffer.

Try 512 frames for one launch with:

```bash
env PIPEASIO_PREFERRED_BUFFERSIZE=512 ableton-live
```

## PipeASIO Settings does not open

Live can still use PipeASIO without the settings window. Run the project update. If a Qt package is missing, the update prints the install command for the detected distribution. Install that package and open PipeASIO Settings again.

After saving a change, set Live's **Audio Device** to **None** and back to **PipeASIO**.

## The installer says PipeWire is too old

The installer has left the current installation unchanged. Install the normal Linux updates and try again. If the message remains, use a Linux release that provides PipeWire 1.4.2 or newer.

## Audio pauses or plays at the wrong speed

Wait a few seconds. PipeASIO normally asks Live to use the current PipeWire buffer size and resumes at the correct speed.

If the problem remains, close Live, clear a forced PipeWire buffer size, and start Live again:

```bash
pw-metadata -n settings 0 clock.force-quantum 0
```

If it returns, run the installed audio report:

```bash
~/.local/share/ableton-wine/audio-report.sh
```

Read the output before sharing it. Remove private paths, environment values, or log text that you do not want to publish, then attach the relevant section to an issue.

## A plugin window resizes repeatedly or shows stale pixels

Right-click the plugin in Live's device rack, turn off **Auto-Scale Plugin Window**, and reopen it. Apply this only to the affected plugin.

## Live does not let you enable the GPU renderer

Run the current project update, restart Live, and open **Settings > Display & Input**. Turn on **Enable GPU Renderer**.

If you're experiencing performance issues or high CPU usage when idle, Live
may not be using your GPU. Live only uses graphics chips it recognises, and
when this project cannot identify your chip, Live sees an old model it
refuses to use.

## CPU use rises when the pointer moves

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

If the setting is still greyed out, start Live with:

```bash
env WINE_D3D_FORCE_GPU_RENDERING=1 ableton-live
```

Please note: while you use this flag, any report you send to Ableton names
a different graphics card model than yours. Start Live without the flag to
go back.

If problems continue, [open an issue](https://github.com/shibco/ableton-linux/issues)
and include your graphics card model.

## CPU spikes when moving your mouse

Live keeps its current diagnostics in
`$XDG_STATE_HOME/ableton-wine/logs/live.log` (by default,
`~/.local/state/ableton-wine/logs/live.log`),
whether you start it from the desktop menu or a terminal. If Live's CPU
use jumps while you move the mouse, run:

```bash
grep -i "sustained present-size mismatch:" ~/.local/state/ableton-wine/logs/live.log
```

If it prints a line, include that whole line when reporting the problem. It contains the desktop environment and window DPI but should still be read before sharing. If it prints nothing, describe the action that triggers the CPU increase instead.

## Live 11: Max for Live fails after the first launch

Close Live after its first run, extract the current project installer, and run the repair:

```bash
sh ~/Downloads/install-ableton-latest.run extract /tmp/ableton-kit
bash /tmp/ableton-kit/scripts/installer.sh prefix repair-live11
```

The repair moves the incompatible Max preferences to a timestamped backup. Max creates a clean file the next time it starts.

## A newly installed font does not show up inside Live

Close Live, then start it with the saved font list turned off:

```bash
env WINE_DISABLE_HOST_FONT_CACHE=1 ableton-live
```

Live keeps a saved list of your computer's fonts so it can start faster.
The list refreshes itself when your fonts change, so a new font normally
appears at the next launch on its own. The launch above skips the list
and reads your fonts directly.

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

Do not preview or import WMA or video files in Live 11. The current Wine media implementation can crash Live on that path. Live 12 does not use the affected path.

## The launcher finds more than one Live installation

When Live 11 and Live 12 are both installed, `ableton-live` starts the newest major version. Start Live 11 with:

```bash
env ABLETON_LIVE_VERSION=11 ableton-live
```

If one prefix contains several editions of the same major version, set `ABLETON_LIVE_EXE` to the exact executable you want to start.

## Using Linux-native plugins

Direct Linux VST or CLAP loading is not implemented. Running a plugin in Carla and routing audio and MIDI through PipeWire remains experimental and is not configured by the installer.

## Push 2 does not connect

Configure one **Push2** control-surface row with **Ableton Push 2 Live Port** as both input and output. Remove duplicate **Push2** rows, close Live normally, reconnect Push 2, and start Live again.

If the display still does not start, include the result of `lsusb` and the selected control-surface row when you report the problem.

## Ableton Link does not find peers

Link peers must share a local network that carries multicast traffic. Guest networks, public Wi-Fi, and the far side of a VPN may block discovery.

Check the current setting:

```bash
sh ~/Downloads/install-ableton-latest.run link status
```

If it reports `policy: off`, enable Link for the current session:

```bash
sh ~/Downloads/install-ableton-latest.run link enable --mode=session
```

The command may ask for `sudo` when a supported firewall needs to allow UDP port 20808. Start Live, enable **Show Link Toggle**, and turn on Link in the control bar.

## Audio latency remains high

Open **PipeASIO Settings**, lower the buffer size, save, then set Live's **Audio Device** to **None** and back to **PipeASIO**. Raise the buffer again if sound breaks up. Buffer size changes latency, not the CPU used by Live or plugins.

Run the optional real-time setup once:

```bash
~/.local/share/ableton-wine/setup-realtime.sh
```

The script changes system audio settings and asks for `sudo`. Log out and back in after it finishes. Running it again also removes the boot-time CPU setting used by early project releases.

On Pop!_OS and other System76 computers, do not install `power-profiles-daemon` solely for this project. Its installation can remove the System76 power-management tools. Use the desktop power settings instead.

## Display scaling is wrong

Restart Live after moving it between monitors with different scale factors. Automatic detection is already the default. If scaling remains wrong at 125%, compare one explicit launch.

On GNOME, run:

```bash
env ABLETON_DPI_MODE=fractional ableton-live
```

On KDE, Sway, Hyprland, COSMIC, or X11, run:

```bash
env ABLETON_DPI_MODE=dpi120 ableton-live
```

The other supported values are listed in [Building](https://github.com/shibco/ableton-linux/blob/main/BUILDING.md#current-configuration).

## Full screen is shifted or does not close correctly

Update the project first. If the problem remains, compare one launch with the fullscreen adjustment disabled:

```bash
env WINE_WIN32_FULLSCREEN_CLASS=off ableton-live
```

Open an issue and include the desktop environment, display scale, and whether that launch behaved differently.

## GNOME handles a Live shortcut instead of Live

GNOME may use Ctrl+Alt+Up, Ctrl+Alt+Down, or Ctrl+Alt+Delete before Live sees it. Start Live with:

```bash
env ABLETON_SHORTCUTS=take ableton-live
```

The launcher temporarily removes only the conflicting GNOME entries and restores them after all Live sessions exit. Those shortcuts remain unavailable to other applications while Live runs.

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

Use the [GitHub issue form](https://github.com/shibco/ableton-linux/issues/new/choose). Include the Live edition, project release, Linux distribution, desktop environment, and exact action that failed.

The current launcher log is `~/.local/state/ableton-wine/logs/live.log`. Read any log or audio report before sharing it. Do not attach Ableton installers, authorisation files, licence keys, Live Sets, samples, or plugin credentials.
