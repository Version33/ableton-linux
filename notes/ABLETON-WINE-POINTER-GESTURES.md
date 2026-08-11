# Pointer input: wheel coordinates and gestures

Patches 0072 through 0074, 0090 and 0091 add middle-button drag
navigation (issue 50), touchpad pinch zoom (issue 64), precision
scrolling from XInput2 scroll valuators, and scroll inertia. The default
enables inertia, and a setting can disable it. Patch 0073 also keeps
horizontal-wheel coordinates in screen space for Live's own hit testing.

## Output routes

The driver sends each direct XInput2 scroll report with its mapped screen
point. Wineserver updates its cursor before it routes the wheel. The
driver forwards any pointer motion in the same report first, so the
cursor and wheel describe the same input report.

The driver sends middle-drag, pinch and delayed inertia output without a
position. Without `MOUSEEVENTF_ABSOLUTE` and with a zero point,
`send_mouse_input()` adds no `MOUSEEVENTF_MOVE`, and wineserver stamps the
message at its current cursor. This preserves the middle drag's
press-origin target and prevents an old inertia point from moving the
cursor. The driver also omits the position from direct scrolling while a
middle drag is active.

Wine does not try to identify Live's internally drawn scrollable regions.
It delivers wheel messages at the cursor; Live performs its own hit
testing.

## Patch 0072: configuration and middle-button drag

All pointer features read one configuration block. `setup_options()`
parses it once when the process attaches. A `WINE_X11_*` environment
variable has first priority as a one-launch override. The AppDefaults
registry key comes next, followed by `HKCU\Software\Wine\X11 Driver`.
The parser accepts only the named values. Any other value logs a warning
and keeps the default, so a near miss cannot enable a setting meant to
disable a feature. `InertiaRate` also rejects non-finite numbers, values
outside its range and trailing characters. The driver logs a `winediag`
warning when it finds an environment variable that it no longer reads,
and names the current variable. The launcher exports none of these
variables.

`MiddleDrag=navigate` holds a middle press back and reports movement as
wheel (vertical) and horizontal wheel (horizontal), 24 raw pixels per
notch, fractionally. The driver takes the drag slop from
`SM_CXDRAG` and `SM_CYDRAG` and measures movement against the press
origin. An unmoved press replays as a plain middle click. A completed drag
syncs the cursor to the X11 release coordinates. Drag state lives per GUI
thread: the X implicit pointer grab pins a drag's events to the owning
thread, so nothing races across threads and the state needs no lock.

## Patch 0073: horizontal-wheel screen coordinates

Both `WM_MOUSEWHEEL` and `WM_MOUSEHWHEEL` define the x and y values packed
into `lParam` as screen coordinates. Wine kept only the vertical message
out of client conversion. It first routed horizontal input to the correct
Win32 window, then rewrote `lParam` in that window's client coordinates.
The observed bands and the result after preserving screen coordinates
support this diagnosis: Live treated the rewritten value as a screen point
for its own hit test. The client-origin offset shifted the effective point
up and left. In the device drawer, scrolling at the top reached the main
view, scrolling in the middle reached no scrollable region, and scrolling
at the bottom reached the drawer.

Patch 0073 keeps both wheel messages in screen space in
`process_mouse_message()`. Wineserver no longer predicts a non-client form
for either wheel message. [tools/wheelcoords.c](../tools/wheelcoords.c)
injects both wheel messages over a popup at a nonzero origin and checks
their `lParam` against `GetCursorPos()`. The final case makes hit testing
return `HTCAPTION` and checks that a `PeekMessage()` filter receives no
non-client horizontal-wheel message.

## Patch 0074: pinch zoom

The driver turns XInput2 2.4 pinch gestures into wheel events that
applications read as Ctrl+wheel. A Windows precision touchpad produces
the same input for an unhandled pinch. The driver synthesises no Ctrl key
event: it creates no key message, triggers no keyboard hook or accelerator,
and does not release a physically held Ctrl. The modifier reaches both of
an application's reads:

- A new `SEND_HWMSG_FORCE_MK_CONTROL` flag on the
  `send_hardware_message` request makes the server set `MK_CONTROL` in the
  message's `wParam`. The server builds this value at queue time.
  `update_key_state()` ignores the `MK_*` bits of mouse messages, so this
  route changes no key state. The flag uses the request's existing flags
  field, so the wire format and protocol version do not change. Patch
  0078 carries the next protocol version change.
- For the gesture's duration the driver holds Ctrl in the owning
  thread's queue and async key state through the server's existing
  `set_key_state` request. Live reads `GetKeyState()` rather than the
  message state (measured 2026-08-10: with the `wParam` override alone,
  the wheel arrived and nothing zoomed), so this half serves that read
  while creating no input. The driver releases the key on gesture end,
  cancellation, focus loss, device change, slot eviction and thread
  detach. `KeymapNotify` resynchronises a stale state byte.

The Ctrl write replaces the full key-state array. A concurrent physical
modifier transition can overwrite that array. Overlapping pinches also
share one synthetic Ctrl hold without ownership. A server operation that
changes only the Ctrl bits would remove both risks.

The driver tracks gestures per physical device (`sourceid`, not
`deviceid`). Begin seeds the protocol-defined scale of 1.0. An update
without a begin adopts the event's scale. The driver ignores an unmatched
end. On `XIGesturePinchEventCancelled`, it returns the net wheel movement
in one compensating event, capped at 16 notches. A larger cancelled
gesture can retain some zoom. Focus loss, device changes, slot eviction
and thread detach free the slots. The path keeps no cursor anchor and
never calls `XQueryPointer`, so its wheel-only output cannot move the
cursor.

The server does not merge wheel messages across a modifier change. This
keeps ordinary scrolling separate from Ctrl-tagged zoom. It also
coalesces `WM_MOUSEHWHEEL` in the same way as `WM_MOUSEWHEEL`, so a
stalled application drains one accumulated message per axis.

`tools/pinchgen.c` creates a virtual uinput touchpad that drives this path
without hardware.

## Patch 0090: precision scrolling

XInput2 2.1 reports touchpad and high-resolution wheel scrolling as
cumulative valuator positions. The decoder converts each change into
fractional wheel units with a carried remainder (verified in Live:
fractional delivery makes Live scroll and zoom smoothly). It drops the
emulated legacy button duplicates and keeps core wheel buttons untouched,
so scrolling works during core grabs such as menus, move and resize, and
`ClipCursor`. It also reconstructs the core events that an XInput2
selection suppresses, with matched press and release events.

Each direct native wheel or scroll-valuator report carries its current
XInput2 point after `map_event_coords()`. Wineserver updates its cursor
before it routes the wheel. The driver forwards pointer motion from the
same report first. It keeps active middle drags and later inertia ticks on
the positionless route.

The decoder invalidates and reseeds baselines on window entry, focus
changes, cursor-clip grabs, device changes and removal, and implausibly
large jumps. XInput2 can reuse a removed device ID. A report past the
16-notch cap advances the baseline all the way and discards the excess,
so the excess cannot appear in a later report.

`WM_MOUSEWHEEL` defines `MK_LBUTTON` and the other button flags as normal
message state. While a button is down, the decoder delivers each complete
notch and carries the remaining fraction. A clickpad thumb-hold with a
moving finger still classifies as two-finger scroll, and wheel input with
`MK_LBUTTON` set reaches the control under the drag (reproduced in Live
faders, 2026-08-10). On release, the decoder discards any remaining
fraction so it cannot appear over a different target. A held button also
cancels inertia tracking. The quantised stream would inflate the fling
velocity, so the tracker measures deltas against the last raw report.

The pointer axes come from the device's valuator class labels, with 0 and
1 as the unlabelled fallback. The driver queries slave scroll classes once
at thread initialisation instead of making a round trip on the first
event. The XInput2 selection follows Wine's `WS_EX_TRANSPARENT` policy
instead of calling `XGetWindowAttributes()` for each window. The cache
evicts the scroll source that reported least recently.

Native XInput2 wheel-button input and scroll-valuator output update the
window user time at most once per 100 ms. This keeps focus-stealing
prevention current without waking the X server and window manager for
every report.

## Patch 0091: scroll inertia and thrown drags

When a fast touchpad sequence or middle-button drag ends, its velocity
can decay into further wheel input. Inertia ships on by default;
`TouchpadInertia=disabled` turns it off. XInput2 cannot classify scroll
sources: `ScrollClass` has no finger or wheel field, and XWayland discards
the Wayland `axis_source`. The default therefore also makes free-spin and
high-resolution wheels coast. `TouchpadInertia=auto` resolves to disabled
on this backend and remains available for a future backend that can
classify input sources. The scroll path also requires precise mode. A
middle drag has raw pixel deltas and can throw in any mode.

The GUI thread owns the tracker state and emits every wheel event. A
separate nudger thread only schedules internal tick messages:

- While a sequence runs, the tracker retains raw fractional deltas and
  event timestamps for 100 ms. Each sample rearms a one-shot 100 ms
  release deadline. On the tested XWayland system, a zero-delta
  scroll-axis report coincided with finger lift. The driver treats this
  report as the stop marker and evaluates the fling immediately. It
  compares the axes against the last observed values because the delivery
  baseline lags by the sub-notch remainder. A middle-button release is the
  stop marker for a drag. An abort or a press that stayed a click cancels
  instead.
- The tracker computes velocity as the summed raw deltas over the
  interval covered by their event timestamps. A late evaluation does not
  reduce that value, and rounding does not remove samples. A fling starts
  at a vector magnitude of 240 wheel units/s, stops below 60 and clamps at
  19200. Measured touchpad flicks ranged from about 4000 to 19000.
- A stop marker more than 70 ms after the last movement does not start a
  fling. A late stop marker also cancels a coast that the quiet deadline
  started while the fingers rested on the pad. A middle drag that stops
  moving parks its tracker, so only a release during movement throws. After
  three seconds of coasting, the driver raises the decay rate to 14/s. A
  slow custom `InertiaRate` then finishes in about 300 ms instead of
  stopping in one tick.
- The nudger waits on `CLOCK_MONOTONIC`, so wall-clock changes do not move
  its deadlines. A sample rearms its slot under a mutex and wakes the
  nudger only when the deadline moves earlier. Eight slots hold one
  schedule per window. If all slots are full, the nudger replaces the
  schedule with the latest deadline; that tracker resumes on its thread's
  next input.
- Coasting integrates the decay analytically per tick: `v1 = v0 e^(-k dt)`
  and `dx = v0 (1 - e^(-k dt)) / k`. The tracker carries the remainder,
  so tick timing does not change the total travel. `InertiaRate` is `k` in
  1/s, with a default of 4.0 and a range of 0.5 to 16.0.
  `InertiaCurve=linear` uses constant deceleration with the same initial
  slope. `k` is an exponential rate coefficient, not a fraction of
  velocity lost per second.
- The nudger posts `WM_X11DRV_POINTER_TICK`, a driver-internal message.
  win32u hands each tick to the driver on the window's thread, and the
  application never sees it. The nudger holds no scroll state and emits no
  input. A tick posted after cancellation finds an idle tracker.
- Coasting cancels on pointer motion, any button or key press, focus
  loss, cursor clip grabs, device changes, and a new scroll sequence.
  The driver sends wheel-only output to the null window. The server routes
  it by capture and cursor position, so an old window target cannot receive
  it.

## Policy

The registry values live in:

```text
HKCU\Software\Wine\X11 Driver
```

with per-application overrides in
`HKCU\Software\Wine\AppDefaults\<exe>\X11 Driver`.

| Value | Accepted | Default |
| --- | --- | --- |
| `SmoothScrolling` | `disabled`, `precise`, `notched` | `precise` |
| `TouchpadInertia` | `disabled`, `auto`, `enabled` | `enabled` |
| `PinchZoom` | `disabled`, `legacy-wheel` | `legacy-wheel` |
| `MiddleDrag` | `disabled`, `navigate`, `navigate-notched` | `navigate` |
| `InertiaCurve` | `exponential`, `linear` | `exponential` |
| `InertiaRate` | finite number accepted by `strtod()`, 0.5 to 16.0, no trailing characters | `4.0` |

`precise` behaves as `disabled` when the X server has no XInput2 2.1.
Pinch needs XInput2 2.4. The driver logs a warning when gesture support is
unavailable. Set a value with this project's Wine:

```bash
env WINEPREFIX="$HOME/.wine-ableton" \
  "$HOME/.local/opt/wine-d2d1-nspa-11.13/bin/wine" reg add \
  'HKCU\Software\Wine\X11 Driver' \
  /v SmoothScrolling /t REG_SZ /d notched /f
```

For one launch, pass `WINE_X11_SMOOTH_SCROLLING`,
`WINE_X11_TOUCHPAD_INERTIA`, `WINE_X11_PINCH_ZOOM`,
`WINE_X11_MIDDLE_DRAG`, `WINE_X11_INERTIA_CURVE` or
`WINE_X11_INERTIA_RATE` with the same values as the registry. The launcher
sets none of them. Set the variable before the launcher starts. The driver
reads the settings when each process attaches and traces each value with
its source as `(default)`, `(environment)` or `(registry)`.

Earlier preview builds used `WINE_X11_SMOOTH_SCROLL` and
`WINE_X11_SCROLL_INERTIA*`. The driver does not map those names to the
current settings. It logs a warning and names the replacement. No release
used the old names.

## Issue 163 stays separate

Reports of a file dialog after an Alt velocity edit concern win32u menu
arming. Patch 0070 may still miss the order `LButtonDown`, `AltDown`,
drag, `LButtonUp`, `AltUp`, where the mouse press predates the arming.
This pointer series does not change menu arming. Patch 0074 does hold Ctrl
in the queue and async key state during a pinch, so the source alone does
not rule out an interaction.

Wait for a trace before changing behaviour or attributing the report. The
trace needs `WM_SYSKEYDOWN`, `WM_SYSKEYUP`, `SC_KEYMENU`, menu-loop
messages, and the call that opens the dialog or portal. Treat menu
activation and file-chooser invocation as separate failures until that
trace exists.

## Verification status

The full main series compiled, and all patches applied in filename order.
On 2026-08-10, the series ran in Live 12 on one GNOME Wayland (XWayland)
setup, with swapped `winex11.so` and `wineserver` binaries from the
2026.08.04.1 preview runtime:

- The session showed precision scrolling, pinch zoom with the key-state
  change, middle-drag panning, scroll coasting on the stop marker, thrown
  middle drags and cancellation on new input.
- Timestamped traces showed that the driver delivered input on the first
  attempt. Live consumed it late during startup.
- Tests found four boundary faults. Pinch input could inherit a running
  fling. A paused middle drag could start a coast that later input could
  not cancel. Resting fingers could trigger a deadline fling. The
  three-second cap could stop a slow coast in one tick. The implementation
  cancels, gates or decays those cases.
- Retest fling responsiveness. The 70 ms stop gate may reject genuine
  flings.

That run predates the direct XInput2 position change in patch 0090.

On 2026-08-11, all 86 Wine patches applied in filename order. The full
WoW64 build and all 114 artifact checks passed. `tools/wheelcoords.c`
passed both wheel-coordinate cases and the non-client filter case on that
build. Live 12.4.3 ran with the same Wine and wineserver. An interactive
check on the same GNOME Wayland setup confirmed horizontal scrolling at
the top, middle and bottom of the device drawer. The previous main-view
band, dead zone and drawer-only band did not recur.

These results cover one GNOME XWayland environment. Empty gate cells
remain unrun.

Release gate: every row must pass before `precise` ships as the default
in a release:

| Check | Xorg | XWayland GNOME | XWayland KDE | Wayland other |
| --- | --- | --- | --- | --- |
| Horizontal scroll targets the device drawer at top, middle and bottom | | Pass (Live 12.4.3, 2026-08-11) | | |
| Touchpad two-finger scroll in Live (all scroll regions) | | | | |
| Fader/knob drag with clickpad thumb-hold (regression) | | | | |
| High-resolution wheel, free-spin wheel | | | | |
| Coarse wheel notches | | | | |
| Wheel during drag (MK state, no loss) | | | | |
| Scroll in another app, return, tiny scroll (no burst) | | | | |
| Cross-thread plugin window scroll handoff | | | | |
| Menus, dialogs, move/size, ClipCursor scrolling | | | | |
| Device unplug and reconnect mid-session | | | | |
| Middle drag: click, drag, abort, release sync | | | | |
| Pinch begin/update/end, cancellation, Ctrl+wheel zoom responds | | | | |
| Live `wParam` vs `GetKeyState()` check (`pinchgen`) | | | | |
| Inertia: glide starts/coasts/cancels; UI stall past 100 ms | | | | |
| Alt-drag velocity edit (issue 163 observation only) | | | | |
| Basic clicking unchanged: five buttons press/release paired | | | | |

`tools/pinchgen.c` creates a virtual uinput touchpad that drives the pinch
and scroll paths without hardware. It needs write access to `/dev/uinput`.
