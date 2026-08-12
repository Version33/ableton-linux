# Troubleshooting Ableton Live on Linux

Use the action under the symptom you see. Update this project before reporting a problem:

```bash
sh ~/Downloads/install-ableton-latest.run update
```

An update keeps Live, its authorisation, projects, and PipeASIO settings. It may update compatibility-related Wine and Live settings.

## The installer does not finish

If an **Ableton USB Driver** window is open, close it and wait for setup to continue. If the current installer still stops, press Ctrl-C, run it again, and note the last line it printed.

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

If the setting remains unavailable, open an issue and include the graphics card model shown by Linux and the name shown by Live.

## Live 11: Max for Live fails after the first launch

Close Live after its first run, extract the current project installer, and run the repair:

```bash
sh ~/Downloads/install-ableton-latest.run extract /tmp/ableton-kit
bash /tmp/ableton-kit/scripts/installer.sh prefix repair-live11
```

The repair moves the incompatible Max preferences to a timestamped backup. Max creates a clean file the next time it starts.

## Live 11: media files can crash Live

Do not preview or import WMA or video files in Live 11. The current Wine media implementation can crash Live on that path. Live 12 does not use the affected path.

## The launcher finds more than one Live installation

When Live 11 and Live 12 are both installed, `ableton-live` starts the newest major version. Start Live 11 with:

```bash
env ABLETON_LIVE_VERSION=11 ableton-live
```

If one prefix contains several editions of the same major version, set `ABLETON_LIVE_EXE` to the exact executable you want to start.

## Push 2 does not connect

Configure one **Push2** control-surface row with **Ableton Push 2 Live Port** as both input and output. Remove duplicate **Push2** rows, close Live normally, reconnect Push 2, and start Live again.

If the display still does not start, include the result of `lsusb` and the selected control-surface row when you report the problem.

## Ableton Link does not find peers

Link peers must share a local network that carries multicast traffic. Guest networks, public Wi-Fi, and the far side of a VPN may block discovery.

Enable the session Link setup again:

```bash
~/.local/share/ableton-wine/setup-link.sh enable --mode=session
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

## Report a problem

Use the [GitHub issue form](https://github.com/shibco/ableton-linux/issues/new/choose). Include the Live edition, project release, Linux distribution, desktop environment, and exact action that failed.

The current launcher log is `~/.local/state/ableton-wine/logs/live.log`. Read any log or audio report before sharing it. Do not attach Ableton installers, authorisation files, licence keys, Live Sets, samples, or plugin credentials.
