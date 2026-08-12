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

## Linux probes

Linux tools inspect the host display, audio, scheduling, and process state.
Run only the tool named by an investigation and attach its output to that
issue. A result from an advanced probe is evidence for that path only; it does
not replace a full Live run.
