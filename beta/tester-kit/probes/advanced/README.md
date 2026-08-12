# Advanced diagnostic tools

These probes collect evidence for a specific failure. They are not part of the
default test run because some need manual interaction or observe input across
the Wine desktop.

## Build native tools

```bash
./beta/tester-kit/probes/build-native-tools
```

The build script writes Linux executables under `probes/advanced/linux/` and
updates their hashes. Use the repository maintainer environment for Windows
probe builds.

## Capture a Live input trace

Run the trace only after reading its prompt:

```bash
./beta/tester-kit/run-session --live-only --advanced-input-trace \
  --prefix "$HOME/.wine-ableton-beta"
```

The trace observes mouse and keyboard input delivered to Wine while it runs.
Close unrelated applications, enter no passwords, and stop the trace as soon
as the requested action is complete. The final report removes captured window
titles, but the retained temporary directory can contain more detailed
evidence. Keep that directory private.

## Windows probes

Windows probes run under the selected Wine runtime. They inspect input,
window-management, DirectComposition, and related Win32 paths used by Live.
Their source lives beside the distributed executables where available.

Run only the tool named by an investigation and attach its output to that
issue. A result from an advanced probe is evidence for that path only; it does
not replace a full Live run.

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
