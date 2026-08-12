# Advanced test tools

These tools are for investigating a specific failure. The normal tester command
does not run them unless you request the input trace. Some tools send input,
close Live, resize its window, or change audio connections.

Save the project before using them. Record the exact command in the issue.

## Build the Linux tools

From the root of this repository:

```bash
./beta/tester-kit/probes/build-native-tools
```

The script writes the programs and `build-results.txt` under
`beta/tester-kit/probes/advanced/native/`. It stops if no C compiler is
installed. A missing development library marks the affected program `SKIP`.
The script does not install packages or use `sudo`.

## Live input trace

This is the only advanced workflow that `run-session` can start:

```bash
./beta/tester-kit/run-session --live-only \
  --advanced-input-trace \
  --wine "$HOME/.local/opt/wine-d2d1-nspa-11.13/bin/wine"
```

The command asks you to type `TRACE`. It then watches Wine mouse input and JUCE
plug-in windows for 15 seconds. Use the affected window during those 15
seconds.

The hook DLL can remain loaded until Live exits. Save first, run the trace, and
then quit Live.

## Windows tools

| Tool | What it does |
| --- | --- |
| `liveinject.exe` | Sends keyboard or pointer input to Live. It can also ask Live to close. |
| `heldwheel.exe` (local build) | Shows whether wheel movement reaches a window while a mouse button is held. |
| `showrestore.exe` | Restores a minimised Live window, then asks Live to close. |
| `wmresize.exe` | Opens a test window and measures whether resizing stops. |
| `spyhost.exe` and `mousespy.dll` | Install a Wine-wide mouse hook and inspect JUCE plug-in windows. |

Run these files with the same Wine executable and Wine prefix used by Live.

## Linux tools

| Tool | What it does |
| --- | --- |
| `fakectl` | Creates a temporary ALSA MIDI controller. |
| `jacklinkd` | Restores selected JACK or PipeWire audio connections. |
| `uclick` | Sends keyboard or pointer input through Linux `uinput`. |
| `xact` | Changes X11 window activation and focus. |
| `xmon` | Records focus, properties and size for one X11 window. |
| `xrec` | Records focus and input events across X11 programs. |
| `xtool` | Sends pointer or keyboard input through XTEST. |
| `xsettle` | Finds, resizes and measures the Live XWayland window. |
| `xdmg` | Records redraw events for one X11 window. |
| `xgrid` and `xsamp` | Measure pixel changes in Learn View and plug-in windows. |

## Wheel use while holding a button

Use `heldwheel.c` with `uclick` to check that a mouse wheel still works while a
button is held. Build the receiver with Wine's compiler:

```bash
winegcc -O2 -Wall -Wextra -Werror \
  -o /tmp/heldwheel.exe \
  beta/tester-kit/probes/advanced/src/heldwheel.c
```

Keep `/tmp/heldwheel.exe` and `/tmp/heldwheel.exe.so` together. Start the
receiver with the Wine build and prefix under test:

```bash
env WINEPREFIX=/path/to/prefix \
  WINELOADER=/path/to/wine/bin/wine \
  /tmp/heldwheel.exe
```

Keep the pointer in the receiver's white client area. In another terminal,
start `beta/tester-kit/probes/advanced/native/uclick`, then enter commands such
as:

```text
move 0.5 0.5
btn down left
wheel 1
hwheel -1
btn up left
btn down right
wheel -1
btn up right
quit
```

`wheel 1` is one upward step and should report `delta=120`. `hwheel 1` is one
step to the right. With the left button held, the result should include `L=1`
and values for `target` and `capture`. No wheel line means the input was
blocked before it reached the receiver.

Use the left or right button for this check. Middle-button navigation can use
the middle button itself.

`liveinject.exe`, `showrestore.exe`, `jacklinkd`, `uclick`, `xact`, `xsettle`,
and `xtool` change Live, audio routing, focus, window geometry, or input.
`fakectl` creates a temporary MIDI device. Use these tools only for the test
named in an issue.
