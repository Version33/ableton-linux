# Pointer gestures: middle drag, pinch zoom, precision scrolling, inertia

Patches 0072, 0073 and 0074, plus the separate default-off patch 0090, add
middle-button drag navigation (issue 50), touchpad pinch zoom (issue 64),
precision scrolling from XInput2 scroll valuators, and optional scroll
inertia. They rebuild PR 157 after its review: the same verified input
decoding, with the state, output and lifecycle redesigned. PR 157 numbered
its patches 0070 to 0072 and never merged; those numbers now belong to the
merged Alt/F10 and telemetry patches.

## Output route

Every wheel event the series produces goes through one helper that sends
mouse input with no position. Without MOUSEEVENTF_ABSOLUTE and with a zero
point, send_mouse_input() adds no MOUSEEVENTF_MOVE, and wineserver stamps
the message at the current cursor position (server/queue.c fills x/y from
the desktop cursor when the message carries no move). Wheel delivery
therefore never moves the cursor or the hover state. This removes the PR
157 cursor snap-back, where inertia ticks carried a stored absolute point
and send_mouse_input() turned it into pointer movement.

Wine does not try to identify Live's internally drawn scrollable regions.
It delivers wheel messages at the cursor; Live performs its own hit
testing.

## Patch 0072: configuration and middle-button drag

All pointer features read one configuration block. setup_options() parses
it once at process attach: the registry first (HKCU\Software\Wine\X11
Driver, with the AppDefaults overlay winex11 already gives every option),
then a WINE_X11_* environment variable as an explicit one-launch override.
The parser checks each value against an allow-list. Anything else warns
once and keeps the default, so a value meant to disable a feature can
never enable it through a near miss. InertiaRate additionally rejects
non-finite values, out-of-range values and trailing characters. The
launcher exports none of these variables.

MiddleDrag=navigate holds a middle press back and reports movement as
wheel (vertical) and horizontal wheel (horizontal), 24 raw pixels per
notch, fractionally. The driver takes the drag slop from
SM_CXDRAG/SM_CYDRAG and measures movement against the press origin. An
unmoved press replays as a plain middle click. A completed drag syncs the
cursor to the X11 release coordinates. Drag state lives per GUI thread:
the X implicit pointer grab pins a drag's events to the owning thread, so
nothing races across threads and the state needs no lock.

## Patch 0073: pinch zoom

The driver turns XI 2.4 pinch gestures into wheel events applications
read as Ctrl+wheel, the input a Windows precision touchpad produces for
an unhandled pinch. It synthesizes no Ctrl key event anywhere: no key
message exists, no hook sees a phantom key, no accelerator can fire, and
Wine never releases a physically held Ctrl (X keymap check). The modifier
reaches both of an application's reads:

- A new SEND_HWMSG_FORCE_MK_CONTROL flag on the send_hardware_message
  request makes the server set MK_CONTROL in that message's wparam,
  which the server builds at queue time. update_key_state() ignores MK_*
  bits of mouse messages, so this half changes no key state. The client
  already passes its flags word through unchanged, so the change touches
  only protocol.def and server/queue.c, with no wire-format change and
  no protocol version bump (patch 0078 carries the next bump; the
  runtime ships server and client from one tree).
- For the gesture's duration the driver holds Ctrl in the owning
  thread's queue and async key state through the server's existing
  set_key_state request. Live reads GetKeyState() rather than the
  message state (measured 2026-08-10: with the wparam override alone,
  the wheel arrived and nothing zoomed), so this half serves that read
  while creating no input. The driver releases the key on gesture end,
  cancellation, focus loss, device change and slot eviction, and a stale
  byte self-heals through the KeymapNotify modifier resync.

The driver tracks gestures per physical device (sourceid, not master
deviceid). Begin seeds the protocol-defined scale 1.0. Update-without-
begin adopts the event's scale. The driver ignores an unmatched end, and
undoes a cancelled gesture (XIGesturePinchEventCancelled) with one
compensating wheel event, as the XI2 protocol asks. Focus loss and device
changes free the slots; no other cleanup exists. The path keeps no cursor
anchor and never calls XQueryPointer: wheel-only output cannot move the
cursor.

A runtime check settled the wparam-or-GetKeyState question on 2026-08-10:
Live reads the key state, so the set_key_state half makes Live zoom, and
the wparam override stays correct for applications that read the message.
tools/pinchgen.c creates a virtual uinput touchpad that drives this path
without hardware.

## Patch 0074: precision scrolling

XInput2 2.1 reports touchpad and high-resolution wheel scrolling as
cumulative valuator positions. The decoder converts each change into
fractional wheel units with a carried remainder (verified in Live under
PR 157: fractional delivery makes Live scroll and zoom smoothly). It
dedups the emulated legacy button events and keeps core wheel buttons
untouched, so scrolling works during core grabs (menus, move/size,
ClipCursor). It also reconstructs the core events an XI selection
suppresses, press/release symmetric.

What changed against PR 157:

- The decoder invalidates and reseeds baselines on every discontinuity:
  window enter, focus in and out, cursor clip grabs, device change,
  device removal (XInput2 reuses device IDs), and an implausible-jump
  backstop. A report past the 16-notch cap advances the baseline all the
  way and discards the excess, so no debt survives to burst later. This
  removes the phantom 16-notch bursts after scrolling in another
  application or another Wine thread's window.
- The decoder drops no input while a button is down. WM_MOUSEWHEEL
  defines MK_LBUTTON and friends as ordinary message states, and the old
  gate lost high-resolution wheel input during drags. The clickpad fader
  report reproduced on 2026-08-10, so the agreed fallback is in: while a
  button is down the decoder delivers whole notches and carries the
  remainder. It never drops.
- The driver pre-queries slave scroll classes once at thread init
  instead of a first-event round trip, and the XI selection follows
  Wine's own WS_EX_TRANSPARENT policy instead of calling
  XGetWindowAttributes per window.
- Scroll sources evict by age, not by overwriting a fixed slot.

## Patch 0090: scroll inertia and thrown drags

When a fast touchpad sequence or middle-button drag ends, its velocity
can decay into further wheel input. Inertia ships on by default
(Theo's call, 2026-08-10, after the runtime session);
TouchpadInertia=disabled turns it off. XInput2 cannot classify scroll
sources: ScrollClass has no finger/wheel field and XWayland discards
the Wayland axis_source, so the default also makes free-spin and
high-resolution wheels coast. TouchpadInertia=auto resolves to
disabled on this backend and exists for a future native-Wayland path.
The scroll path additionally requires precise mode. The middle drag
has raw pixel deltas and throws in any mode.

Mechanics, all on the owning GUI thread:

- While a sequence runs, the tracker retains raw fractional deltas and
  event timestamps for 100 ms. Nothing polls: each sample re-arms a
  one-shot 100 ms release deadline, and a positive end evaluates the
  fling immediately. For scrolling, the positive end is a report whose
  present axes did not move since the previous report, which is XWayland
  forwarding the compositor's finger lift; the tracker compares against
  the last observed value, because the reporting baseline lags by the
  sub-notch remainder and never compares equal. For the middle drag, the
  positive end is the button release itself. An abort, or a press that
  stayed a click, cancels instead.
- The tracker computes velocity as the summed raw deltas over the
  interval they actually cover, from event timestamps. A late evaluation
  cannot underestimate it and rounding cannot thin it out. A fling
  starts at 240 wheel units/s vector magnitude, stops below 60, and
  clamps at 19200 (measured touchpad flicks span roughly 4000 to 19000).
- Stopping precisely stops precisely. A positive end more than 70 ms
  after the last movement means the fingers rested before lifting, and a
  rest never flings. A late lift marker also kills a coast the quiet
  deadline launched while fingers were resting on the pad. A middle drag
  going still under the held button parks its tracker; only releasing
  while moving throws. Past 3 s of coasting the tracker forces the decay
  steep, so the fling exhales within ~300 ms instead of stopping dead
  (reachable only with slow custom InertiaRate values).
- The nudger waits on CLOCK_MONOTONIC (immune to wall-clock steps) and
  arms once per sequence, not per input sample. The wheel paths throttle
  the _NET_WM_USER_TIME property to once per 100 ms. The server now
  coalesces WM_MOUSEHWHEEL like WM_MOUSEWHEEL, never across a modifier
  change, so a stalled UI drains one accumulated message per axis.
- Coasting integrates the decay analytically per tick: v1 = v0 e^(-k dt),
  dx = v0 (1 - e^(-k dt)) / k, and the tracker carries the remainder, so
  total travel does not depend on tick timing. InertiaRate is k in 1/s
  (default 4.0, bounded [0.5, 16.0]); InertiaCurve=linear substitutes a
  constant deceleration with the same initial slope. k is an exponential
  rate coefficient, not a fraction of velocity lost per second.
- Ticks arrive as WM_X11DRV_POINTER_TICK, a driver-internal message
  win32u hands to the driver on the window's own thread; the application
  never sees it. The only foreign thread is the nudger that posts these
  messages. It holds no scroll state and emits no input, and a stray
  post after a cancel finds the tracker idle.
- Coasting cancels on pointer motion, any button or key press, focus
  loss, cursor clip grabs, device changes, and a new scroll sequence.
  Output goes wheel-only to the null window; the server routes it by
  capture and cursor position, so no stale window target can catch a
  delivery.

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
| `MiddleDrag` | `disabled`, `navigate`, `navigate-notched` | `disabled` |
| `InertiaCurve` | `exponential`, `linear` | `exponential` |
| `InertiaRate` | decimal in [0.5, 16.0] | `4.0` |

`precise` behaves as `disabled` when the X server has no XInput2 2.1.
Pinch needs XInput2 2.4 and warns once without it. Set a value with this
project's Wine:

```bash
env WINEPREFIX="$HOME/.wine-ableton" \
  "$HOME/.local/opt/wine-d2d1-nspa-11.13/bin/wine" reg add \
  'HKCU\Software\Wine\X11 Driver' \
  /v SmoothScrolling /t REG_SZ /d notched /f
```

For one launch, set the environment overrides WINE_X11_SMOOTH_SCROLLING,
WINE_X11_TOUCHPAD_INERTIA, WINE_X11_PINCH_ZOOM, WINE_X11_MIDDLE_DRAG,
WINE_X11_INERTIA_CURVE and WINE_X11_INERTIA_RATE, with the same values as
the registry. The launcher sets none of them. The PR 157 launcher
defaults are gone, and nothing maps the old WINE_X11_SMOOTH_SCROLL and
WINE_X11_SCROLL_INERTIA* names; they never shipped in a release.

## Issue 163 stays separate

The file dialog opening after Alt velocity edits is an Alt menu-arming
question in win32u, not a pointer-gestures one. The merged Alt/F10 patch
(0070) may still miss the ordering LButtonDown, AltDown, drag, LButtonUp,
AltUp, where the press predates the arming. Per the PR 157 review, any
behavior change waits for a message trace (WM_SYSKEYDOWN/UP, SC_KEYMENU,
menu-loop messages, and the actual dialog or portal call). Treat "File
menu activated" and "file chooser invoked" as different failures until
the trace exists. Nothing in this series changes win32u menu arming, and
nothing in it can hold a synthetic Ctrl, so the pinch path can no longer
contribute a stuck-modifier file-open route.

## Verification status

The patch series records compile verification against the full main
series and a lexical-order apply check. On 2026-08-10 the series ran in
Live 12 on one GNOME Wayland (XWayland) setup, as swapped winex11.so and
wineserver binaries on the 2026.08.04.1 preview runtime:

- The session showed precision scrolling, pinch zoom (with the key-state
  half), middle-drag panning, scroll coasting on the finger lift marker,
  thrown middle drags, and cancellation on new input all working.
- Timestamped traces showed the driver delivering from the first
  attempt; the first-load delay was Live's own startup consuming input
  late. Resolved as app behavior, not a driver defect.
- A four-lens review with adversarial verification then found four seam
  bugs the interactive session could not see, all fixed the same day: a
  pinch over a running fling zoomed with leftover momentum; a paused
  middle drag could self-fling with an unkillable coast; fingers resting
  on the pad could launch phantom deadline flings (fixed with a 70 ms
  positive-end gate; the gate suppresses some launches the earlier
  session produced, so it needs a feel re-pass); and the 3 s cap stopped
  slow coasts dead (now an exhale).

That is one environment; every other row of the gate below is unrun.

Release gate: every row must pass before `precise` ships as the default
in a release. Empty cells are unrun:

| Check | Xorg | XWayland GNOME | XWayland KDE | Wayland other |
| --- | --- | --- | --- | --- |
| Touchpad two-finger scroll in Live (all scroll regions) | | | | |
| Fader/knob drag with clickpad thumb-hold (regression, K2) | | | | |
| High-resolution wheel, free-spin wheel | | | | |
| Coarse wheel notches | | | | |
| Wheel during drag (MK state, no loss) | | | | |
| Scroll in another app, return, tiny scroll (no burst) | | | | |
| Cross-thread plugin window scroll handoff | | | | |
| Menus, dialogs, move/size, ClipCursor scrolling | | | | |
| Device unplug and reconnect mid-session | | | | |
| Middle drag: click, drag, abort, release sync | | | | |
| Pinch begin/update/end, cancellation, Ctrl+wheel zoom responds | | | | |
| Live wparam vs GetKeyState check (pinchgen) | | | | |
| Inertia: glide starts/coasts/cancels; UI stall past 100 ms | | | | |
| Alt-drag velocity edit (issue 163 observation only) | | | | |
| Basic clicking unchanged: five buttons press/release paired | | | | |

tools/pinchgen.c (a uinput virtual touchpad) drives the pinch and scroll
paths without hardware. It needs write access to /dev/uinput.
