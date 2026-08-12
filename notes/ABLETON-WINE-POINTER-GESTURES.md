# Pointer input review and safety tests

This document describes the pointer behaviour produced by the complete Wine
patch series. It is for reviewers and testers. Patch 0092 contains the final
gesture safety rules, patch 0093 repairs stale cross-process clipping state,
and patch 0094 adds guarded XWayland warp handling. Review the applied Wine
source rather than treating the older pointer patches as separate
implementations.

A Windows wheel notch is 120 wheel units. Fine scrolling and continued
movement may send part of a notch. XInput2 is the X11 interface that provides
high-resolution pointer and touchpad reports.

## What the code provides

- fine vertical and horizontal scrolling from XInput2 scroll reports;
- touchpad pinch reported as Ctrl+wheel;
- middle-button drag navigation;
- bounded movement after a fast scroll or middle-button release;
- screen coordinates for both vertical and horizontal wheel messages;
- cleanup of stale clipping state after an embedded M4L process loses focus;
  and
- guarded relative fader and knob dragging when XWayland does not apply a
  visible-cursor pointer warp.

The gesture defaults are unchanged. Fine scrolling, pinch, middle drag, and
continued movement remain enabled. XWayland warp handling is opt-in and
defaults to `disabled` until the desktop and cursor-visibility matrix below is
complete.

## Code map

| File | What to review |
| --- | --- |
| `dlls/winex11.drv/mouse.c` | Scroll decoding, middle drag, pinch, warp observation, cancellation, and continued movement. |
| `dlls/winex11.drv/event.c` | Focus-bound clipping cleanup and gesture or warp cancellation. |
| `dlls/winex11.drv/window.c` | Capture-bound warp cancellation. |
| `dlls/winex11.drv/x11drv_main.c` | Pointer settings, defaults, and setting priority. |
| `dlls/winex11.drv/x11drv.h` | Per-device and per-thread pointer state. |
| `server/queue.c` | Stored wheel positions, held-button checks, queue limits, and final target selection. |
| `dlls/win32u/input.c` | Preserves the routing flags that belong to each queued pointer movement. |
| `dlls/win32u/message.c` | Rechecks delayed wheel messages before the application can receive them. |

Patch provenance is in [`patches/BASE.txt`](../patches/BASE.txt).

## Ordinary fader and knob dragging

Patch 0093 and patch 0094 repair two separate faults below the gesture layer.

Patch 0093 handles embedded M4L processes. A Max/JUCE host can acquire Live's
cursor-clipping state during embedding, lose focus without receiving the
normal release, and then inject fabricated positions from global raw-motion
deltas. Wine now clears local clipping state when another X client holds the
focus. The complete diagnosis and affected-machine test are in the
[M4L input-injection note](ABLETON-WINE-M4L-INPUT-INJECTION.md).

Patch 0094 handles Live's relative XWayland drags. Live repeatedly calls
`SetCursorPos` to re-anchor a fader or knob. XWayland can accept the X request
without moving the compositor pointer. The next motion then continues from
the old point and Live measures too much movement.

Automatic mode compares the accelerated XInput2 raw delta with the next
ordinary X motion report. A report based on the pre-warp point is evidence
that the warp failed. A report based on the requested target is evidence that
XWayland handled it. Wine requires two clear failed correlations before it
maps motion from the requested target. Missing, out-of-order, small, or
ambiguous evidence keeps native XWayland behaviour. This avoids applying the
repair on top of XWayland's own hidden-cursor warp emulation.

The warp state is shared by the Wine process. Button release, focus change,
capture change, clipping release, input-device replacement, and X11 thread
detach cancel it. Middle-drag navigation receives the original coordinates
and clears the warp state before its release handler returns.

## The safety rule

Ordinary wheel output must not reach a control while any mouse button is
held. This covers:

- fine scroll reports;
- core and XInput2 wheel buttons;
- pinch-generated Ctrl+wheel; and
- movement left over from an earlier scroll.

Pointer movement is still forwarded during a drag. Fine-scroll values are
advanced without sending wheel input, so ignored movement cannot catch up
after the button is released.

Middle-button drag navigation is the only exception. Its own middle press is
withheld from the application. A drag packet is accepted only while exactly
that one physical middle button remains down. Another button press, a second
middle press, or the release changes the button state and invalidates any
delayed drag packet.

## Stored wheel positions

Fine scrolling, pinch, middle drag, and continued movement use a stored Wine
window and screen point. Wine sends the wheel message at that point without
moving the desktop cursor.

For this stored-position input, Wine:

- does not redirect the message to a later mouse capture;
- does not create a raw-input copy;
- does not merge it with another wheel message;
- drops it if the stored window is gone, hidden, or transparent; and
- drops it if the required button state changed while hooks or the application
  delayed delivery.

Wine checks the button state when the message is created, after a low-level
hook, while scanning the queue, and again around application message hooks.
The final hit test uses the stored window and screen point.

## Direct input limits

| Input | Limit for one report |
| --- | --- |
| Fine vertical or horizontal scroll | 120 units per axis |
| Middle-button drag | 120 units per axis |
| Pinch update | 120 units |
| Pinch cancellation correction | 120 units |
| Ordinary queued wheel merge | 120 units |

A cumulative fine-scroll jump greater than 240 units is treated as a device
reset. The complete report is ignored, its saved values are updated, and any
recorded continued movement is cancelled. A report capped at one notch also
updates the saved value fully, so the discarded amount cannot appear later.

Middle drag uses 24 raw screen pixels per notch. A press that stays within
Wine's normal drag distance is replayed as a normal middle click.

## Continued movement limits

Only wheel movement that was actually accepted for delivery is used to measure
ending speed. Fine scrolling starts continued movement only after a matching
unchanged-value report from the same device and window. Middle drag uses its
button release. Silence alone never starts it.

| Limit | Value |
| --- | --- |
| Recent movement used for speed | 100 ms |
| Latest accepted end signal | 70 ms after movement |
| Minimum starting speed | 240 units per second |
| Maximum starting speed | 1,200 units per second |
| Stop speed | 60 units per second |
| Maximum delayed frame used for output | 16 ms |
| Maximum one message | 15 units per axis |
| Maximum attempted messages | 16 total across both axes |
| Maximum travel guard | 120 units per axis |
| Maximum total output | 240 units across both axes |
| Slow-curve correction begins | 3 seconds |
| Final time limit | 4 seconds |

If Wine's interface thread is delayed, speed is reduced over the full delay,
but output is calculated from only the newest 16 ms. Missed frames are
discarded instead of arriving as a burst.

At the default decay rate, the strongest single-axis continuation is about
120 units over 128 ms. Ordinary, slower releases keep their existing response;
the lower speed and output limits tame only forceful releases.

New pointer or key input and changes such as focus, capture, or device removal
cancel recorded movement across the process. A queued packet that was already
submitted is still subject to the stored-position and button checks above.

## Settings

| Registry value | Built-in default | Accepted values |
| --- | --- | --- |
| `SmoothScrolling` | `precise` | `disabled`, `precise`, `notched` |
| `TouchpadInertia` | `enabled` | `disabled`, `auto`, `enabled` |
| `PinchZoom` | `legacy-wheel` | `disabled`, `legacy-wheel` |
| `MiddleDrag` | `navigate` | `disabled`, `navigate`, `navigate-notched` |
| `InertiaCurve` | `exponential` | `exponential`, `linear` |
| `InertiaRate` | `4.0` | decimal value from 0.5 to 16.0 |
| `WarpEmulation` | `disabled` | `disabled`, `auto`, `enabled` |

`SmoothScrolling=disabled` turns off only the XInput2 fine-scroll path.
Ordinary wheel input remains available. `TouchpadInertia` controls continued
movement for both fine scrolling and middle drag.

Wine tries each setting source in this order:

1. the environment variable for this launch;
2. `HKCU\Software\Wine\AppDefaults\<program>.exe\X11 Driver`;
3. `HKCU\Software\Wine\X11 Driver`;
4. the built-in default.

An invalid value produces a warning and Wine continues to the next source. A
mistyped high-priority value therefore cannot hide a valid lower-priority
disable.

| Registry value | Environment variable |
| --- | --- |
| `SmoothScrolling` | `WINE_X11_SMOOTH_SCROLLING` |
| `TouchpadInertia` | `WINE_X11_TOUCHPAD_INERTIA` |
| `PinchZoom` | `WINE_X11_PINCH_ZOOM` |
| `MiddleDrag` | `WINE_X11_MIDDLE_DRAG` |
| `InertiaCurve` | `WINE_X11_INERTIA_CURVE` |
| `InertiaRate` | `WINE_X11_INERTIA_RATE` |
| `WarpEmulation` | `WINE_X11_WARP_EMULATION` |

The launcher sets none of these variables. `TouchpadInertia=auto` is disabled
on XInput2 because that interface does not identify whether a scroll report
came from a touchpad, a high-resolution wheel, or a free-spinning wheel.

`WarpEmulation=disabled` leaves every warp native. The opt-in `auto` mode
observes only XWayland and activates after two correlated failed warps during
a one-button drag. `enabled` forces target-relative mapping during an eligible
XWayland drag and is intended for diagnosis when automatic correlation is
unavailable. The first automatic activation writes `XWayland warp emulation
activated after observed failed warps` to a `+winediag` log.

## Automated checks

Run from the repository root:

```bash
make check
make verify
```

`make check` compiles and runs `tools/pointer-safety-invariants.c`. It checks
the production patch text and exercises the numerical limits with hostile
inputs. `make verify` also checks the pinned source archives.

These are source and maths checks. They do not run Wine or Ableton Live and do
not replace the manual safety tests.

## Manual safety acceptance tests

Mute or disconnect monitoring before touching a control that can change
volume. Start with Live's Master fader low. Restore normal monitoring only
after the tests pass.

Complete the relative-drag coverage below with the default
`WarpEmulation=disabled`, then compare `auto` and `enabled` in every XWayland
cell.

| Display path | Cursor visible | Cursor hidden by Live |
| --- | --- | --- |
| KDE/XWayland | Required | Required |
| GNOME/XWayland | Required | Required |
| Xorg | Required; native behaviour must remain unchanged | Required; native behaviour must remain unchanged |

- Drag a fader or knob normally. Its value must follow the pointer without a
  jump.
- On each XWayland desktop, repeat the fader and knob drag with a visible
  cursor and with every Live control mode that hides it. Compare `auto`,
  `disabled`, and `enabled`. A server-handled hidden-cursor warp must not move
  twice, and an emulated visible-cursor warp must not lose its first delta.
- Load an affected M4L device without focusing its panel, then drag a Live
  fader. The value must follow the pointer. Record whether the log contains
  `lost X focus to another client while clipping`.
- Hold a clickpad press on a fader and move another finger. Pointer movement
  may continue, but the control must receive no scroll change during the drag
  or after release.
- While any ordinary mouse button is held on a control, turn every available
  wheel and try a pinch. The control must not change from wheel input.
- Start a fast scroll, move to a fader, and press it. No older wheel message
  may reach the fader.
- Scroll quickly in every Live scroll area, vertically and horizontally.
  Continued movement must be short, arrive in small steps, and stop on new
  input.
- If Live pauses while loading a plug-in or opening a large browser folder,
  start a fast scroll just before the pause. No catch-up burst may appear when
  the interface responds. Treat this as an opportunistic check when a pause
  occurs, not as a required way to force one.
- Test a normal middle click, slow and fast middle drags, release, and a second
  button pressed during the drag. Navigation must remain bounded, and no drag
  packet may arrive after the button state changes.
- Test pinch begin, updates, end, cancellation, and a physically held Ctrl
  key.
- Repeat the held-drag cases in Live's main window and in a separate plug-in
  window.

Record the pointing device, desktop, Xorg or XWayland session, Live version,
and pass or failure for each case.

## Known limits

- XInput2 cannot distinguish touchpads from high-resolution or free-spinning
  wheels. With `TouchpadInertia=enabled`, all three can continue after a fast
  end signal.
- KDE/XWayland may omit the repeated cumulative scroll value that marks the
  end of a smooth scroll. Direct fine scrolling still works, but continued
  movement does not start. The clipping and warp repairs do not change this
  condition.
- Automatic warp handling requires a raw and cooked XInput2 frame from the
  same Wine X connection, device source, warp generation, and timestamp.
  Conflicting, delayed, small, or otherwise ambiguous evidence keeps native
  coordinates. Use `WarpEmulation=enabled` only as a one-launch diagnostic.
- These changes apply to Wine's X11 driver. Wine's native Wayland driver does
  not use this code.
- Raw movement smaller than one screen pixel can round to zero before Wine
  sees cursor motion. Such movement may not cancel an active continuation.
  Button transitions still invalidate delayed wheel messages.
- A cancelled pinch can correct at most one notch, so a larger cancelled
  gesture may not return completely to its starting zoom.
- Pinch temporarily updates Wine's Ctrl state without creating Ctrl key input.
  A physical modifier change at the same instant can race that state update.
- Passing the automated checks proves the stated source limits, not behaviour
  inside Live. The manual acceptance tests remain required.
