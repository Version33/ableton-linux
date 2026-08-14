# Pointer behaviour and checks

Wine uses 120 units for one wheel step.

## Defaults

By default, Live provides:

- whole-notch vertical and horizontal scrolling;
- pinch zoom;
- middle-button drag navigation that moves content with the pointer;
- scrolling inertia after a quick release;
- continued movement after releasing a moving middle-button drag; and
- normal mouse-wheel clicks while another button is held, except during
  middle-button navigation.

`TouchpadInertia` affects scrolling after release. `MiddleDragThrow` affects
middle-button movement after release. Turning either one off leaves direct
scrolling and direct middle-button navigation unchanged.

`SmoothScrolling` defaults to `disabled`. Any other value selects XI2 motion
and button events on our own windows. That selection stops core event delivery
for the device on those windows, and a button press then creates an implicit
XI2 device grab. `X11DRV_SetCursorPos` and `grab_clipping_window` both take a
core `XGrabPointer`, which fails against that grab, so while a button is held
every warp is refused and cursor clipping is never established. Live drags a
fader by re-anchoring the pointer with `SetCursorPos`, so each refused
re-anchor leaves it accumulating raw physical motion and the control crosses
its whole range from a small movement.

The XI2 selection is dropped for the duration of a core drag, so a button press
leaves the X server holding its stock grab and the core `XGrabPointer`
succeeds. `precise` and `notched` no longer reintroduce the refused-warp
behaviour. The default stays `disabled` until check 11 below has run against
`precise` on each desktop.

The XWayland correction for faders and knobs defaults to `auto`: it engages
only after Wine observes failed pointer warps, never preemptively, so desktops
whose warps work see no behaviour change. A button release is reported in the
corrected coordinate space only when the drag's own motion was delivered
there; a drag whose motion went out uncorrected ends with an uncorrected
release. COSMIC/XWayland, KDE/XWayland, GNOME/XWayland and Xorg checks remain
open.

## Settings

| Setting | Launch variable | Default | Choices |
| --- | --- | --- | --- |
| `SmoothScrolling` | `WINE_X11_SMOOTH_SCROLLING` | `disabled` | `disabled`, `precise`, `notched` |
| `TouchpadInertia` | `WINE_X11_TOUCHPAD_INERTIA` | `enabled` | `disabled`, `auto`, `enabled` |
| `PinchZoom` | `WINE_X11_PINCH_ZOOM` | `legacy-wheel` | `disabled`, `legacy-wheel` |
| `MiddleDrag` | `WINE_X11_MIDDLE_DRAG` | `navigate` | `disabled`, `navigate`, `navigate-notched` |
| `MiddleDragThrow` | `WINE_X11_MIDDLE_DRAG_THROW` | `enabled` | `disabled`, `enabled` |
| `WheelWhileButtonHeld` | `WINE_X11_WHEEL_WHILE_BUTTON_HELD` | `enabled` | `disabled`, `enabled` |
| `InertiaCurve` | `WINE_X11_INERTIA_CURVE` | `exponential` | `exponential`, `linear` |
| `InertiaRate` | `WINE_X11_INERTIA_RATE` | `4.0` | 0.5 to 16.0 |
| `WarpEmulation` | `WINE_X11_WARP_EMULATION` | `auto` | `disabled`, `auto`, `enabled` |
| (all of the above) | `WINE_X11_POINTER_FEATURES` | unset | `disabled`, `off` or `0` turns every pointer feature off |

The launcher sets none of these variables. A launch variable overrides a saved
choice for that launch. Named values ignore letter case. `off` and `0` mean
`disabled` where supported. Wine reports an invalid value in the normal launch
log, then tries the saved choice or default.

`TouchpadInertia=auto` currently behaves like `disabled` on X11.
Lower `InertiaRate` values keep continued movement going for longer. Higher
values stop it sooner.

`WINE_X11_POINTER_FEATURES` is the master switch. Set it to `disabled`, `off`
or `0` and every pointer feature above turns off regardless of any other
source, restoring stock pointer behaviour for baseline comparisons. Wine
reports the switch in the normal launch log.

## Primary solution to issues associated with inertia work

Pressing any ordinary mouse button suspends every optimisation in this series
for the whole drag, on every desktop, from the moment Live loads. While a
button is held there is no XInput2 involvement at all: the X server owns its
stock grab and delivers ordinary core motion, smooth scrolling and pinch are
suspended, inertia and throw cannot start, and the XWayland correction stays
off unless its warps verifiably fail. We forcefully prevent smoothing, acceleration,
a sensitivity change or a coordinate rewrite to a held-button drag. The same
applies at release: the release is delivered in the same coordinate space the
drag's motion used.

## Mitigations

- A mouse-button press stops older scrolling inertia or middle-drag throw.
- Adding a second touch and scrolling cannot speed up a left- or right-button
  control drag. Normal one-finger dragging and middle-button navigation remain
  available. Touchpad scrolling and pinch cannot change the held control.
  Wine does not send ignored movement after release.
- A physical mouse wheel still works while another button is held, except
  during middle-button navigation. Set `WheelWhileButtonHeld=disabled` to
  block it.
- Middle-button navigation works only while its own middle button remains held.
  Another button press stops it.
- Continued movement stays at the window and point where it began. It cannot
  follow the pointer to another control.
- New pointer or key input stops continued movement. Focus or window changes
  and removed devices also stop it.
- Wine keeps at most one continued update waiting. Movement does not build up or
  replay after a pause.

## Limits

| Behaviour | Limit |
| --- | --- |
| Direct smooth scroll | 120 units per axis for one update |
| Direct middle-button drag | 120 units per axis for one update |
| Pinch update | 120 units |
| Largest accepted scroll jump | 240 units |
| Normal inertia start speed | 240 units per second |
| Start speed after 100 ms without more scrolling | 480 units per second |
| Maximum starting speed | 19,200 units per second |
| Largest continued update | 300 units per axis |
| Maximum continued travel | 4,800 units per axis, 7,200 units in total |
| Maximum continued updates sent to Live | 384 |
| Maximum continued time | 4 seconds |
| Movement used to judge a middle-drag throw | Latest 100 ms |
| Longest gap between movements or before release | 80 ms |
| Minimum timed movement span | 10 ms |
| Time assigned when movement updates share one time | 24 ms |
| Minimum movement when updates share one time | 4 pixels |

If Wine receives no clear end report, `TouchpadInertia=enabled` may begin
inertia after 100 ms without more scrolling. This requires the higher start
speed shown above.

Middle-drag throw uses all movement in the final 100 ms when it spans at least
10 ms. A gap longer than 80 ms starts a new final movement, and a pause longer
than 80 ms before release prevents the throw. When the desktop sends one
movement update, or several updates with the same time, Wine assigns a 24 ms
span and requires four pixels of movement. A cancelled drag or extra button
press stops the throw.

## Source checks

Run these commands from the repository root:

```bash
make check
make verify
```

`make check` reads the pointer patches and tests their maths. `make verify`
also checks the saved source files. Neither command starts Wine or Live. The
hands-on checks below remain required.

## Hands-on checks

Mute or disconnect monitoring before a check that can change volume. Start
with Live's Master fader low.

1. Drag faders and knobs. Their values must follow the pointer without jumps.
2. Load an affected Max for Live device without clicking its panel. A Live
   fader must still follow the pointer. Repeat after clicking the device once.
3. Hold a fader with the left or right button. Drag with one finger, then add a
   second touch and scroll. The drag must not speed up. Touchpad scrolling and
   pinch must not change the fader during the drag or after release.
4. Hold the left or right mouse button and turn a physical mouse wheel. The
   wheel must work with the default setting. Repeat with
   `WheelWhileButtonHeld=disabled`; the wheel must stop.
5. Make a fast smooth scroll. The view must keep moving, slow gradually and stay
   within the limits above. New input must stop it. Repeat with
   `TouchpadInertia=disabled`; direct scrolling must feel the same but stop with
   the touchpad or wheel.
6. Release a moving middle-button drag. Repeat with a short drag and a gentle
   curve. Direct navigation and the throw must move content with the pointer
   on both axes. The view must keep moving only after release. A click, a drag
   held still for more than 80 ms, a cancelled drag or an extra button press
   must not start a throw. Repeat with `MiddleDragThrow=disabled`; direct
   navigation must remain unchanged and stop at release.
7. Pinch in and out, including while holding Ctrl. Live must zoom and leave the
   physical Ctrl state unchanged. A cancelled pinch must stop zooming.
8. If Live pauses while loading a plug-in or browser folder during a fast
   scroll, it must not replay missed movement when it responds.
9. Repeat the held-control, inertia and throw checks in Live's main window and
   in a separate plug-in window.
10. Run the fader and knob checks on COSMIC/XWayland, KDE/XWayland,
    GNOME/XWayland and Xorg. On XWayland, compare `WarpEmulation=disabled`,
    `auto` and `enabled` with the pointer shown and hidden. No setting may
    double the control's movement.
11. COSMIC/XWayland, from a fresh Live launch, with no window resize first, and
    with `SmoothScrolling=precise`, which is what selects the XI scroll motion
    this check suspends: drag one fader. Sensitivity must match the pointer and
    the fader must keep its value on release. With `WINEDEBUG=+cursor,+event`,
    the log must show
    `X server delivered core MotionNotify while XI scroll motion is suspended`
    during the drag, proving the server owned the drag. At the default
    `SmoothScrolling=disabled` that line is absent because no XI scroll motion
    was selected; the check does not apply. Repeat with
    `WINE_X11_POINTER_FEATURES=disabled`; behaviour must be identical and
    equally free of acceleration or snap-back. Then repeat checks 1-5 for
    two-finger scroll, pinch, middle-drag pan and inertia outside drags.

Record the pointing device, Linux distribution, desktop, Xorg or XWayland,
Live version, setting and result for each check.

## Limitations and additional notes

- Wine cannot tell whether smooth scrolling came from a touchpad, a precision
  mouse wheel or a free-spinning wheel. All three may keep moving after input
  stops. Set `TouchpadInertia=disabled` to turn this off.
- On KDE/XWayland, inertia may start 100 ms after scrolling stops because the
  desktop may omit the end report.
- This work applies when Live runs through Xorg or XWayland. It does not apply
  when Live runs directly through Wayland.
- Testing the Max for Live pointer repair on the affected Fedora computer
  remains open.
