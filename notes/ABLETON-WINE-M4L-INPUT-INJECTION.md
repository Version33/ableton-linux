# Max for Live can make faders jump

This note covers [issue 122](https://github.com/shibco/ableton-linux/issues/122)
and patch 0093.

## Status

Patch 0093 is included and passes the build checks. The problem does not occur
on the development computer, so testing on the affected Fedora computer is
still required.

## Problem

After loading a Max for Live device, a Live fader can jump across its range
while the pointer moves smoothly. Clicking the device once may stop the problem
for the rest of the session.

Max for Live can open its device window separately from Live. While the device
loads, that window may briefly take control of the pointer. On affected
desktops, it can keep an old pointer state after control returns to Live. The
device then reports extra pointer positions and the fader jumps between them.

## Fix

Patch 0093 clears the old pointer state when control moves to another window.
It also clears that state before a window tries to confine the pointer again.
This stops the device from sending extra positions after Live regains control.

## Check

Use a computer that shows the problem:

1. Install a build that contains patch 0093.
2. Start a fresh Live session with:

   ```bash
   env WINEDEBUG=-all,+event ableton-live
   ```

3. Load the affected Max for Live device. Do not click its panel.
4. Drag the track volume fader in Session View.

The fader should follow the pointer without jumping. The log may contain:

```text
lost X focus to another client while clipping
```

Report the device, Linux distribution, desktop, Live version, result, and
whether clicking the device once changes the result.

This repair applies when Live runs through Xorg or XWayland. It does not apply
when Live runs directly through Wayland.
