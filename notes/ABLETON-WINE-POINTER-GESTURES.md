# Pointer behaviour and checks

Wine uses 120 units for one wheel step.

## Defaults

By default, Live provides:

- smooth vertical and horizontal scrolling;
- pinch zoom;
- middle-button drag navigation;
- scrolling inertia after a quick release;
- continued movement after a quick middle-button drag; and
- normal mouse-wheel clicks while another button is held, except during
  middle-button navigation.

`TouchpadInertia` affects scrolling after release. `MiddleDragThrow` affects
middle-button movement after release. Turning either one off leaves direct
scrolling and direct middle-button navigation unchanged.

The XWayland correction for faders and knobs defaults to `disabled`.
KDE/XWayland, GNOME/XWayland and Xorg checks remain open.

## Settings

| Setting | Launch variable | Default | Choices |
| --- | --- | --- | --- |
| `SmoothScrolling` | `WINE_X11_SMOOTH_SCROLLING` | `precise` | `disabled`, `precise`, `notched` |
| `TouchpadInertia` | `WINE_X11_TOUCHPAD_INERTIA` | `enabled` | `disabled`, `auto`, `enabled` |
| `PinchZoom` | `WINE_X11_PINCH_ZOOM` | `legacy-wheel` | `disabled`, `legacy-wheel` |
| `MiddleDrag` | `WINE_X11_MIDDLE_DRAG` | `navigate` | `disabled`, `navigate`, `navigate-notched` |
| `MiddleDragThrow` | `WINE_X11_MIDDLE_DRAG_THROW` | `enabled` | `disabled`, `enabled` |
| `WheelWhileButtonHeld` | `WINE_X11_WHEEL_WHILE_BUTTON_HELD` | `enabled` | `disabled`, `enabled` |
| `InertiaCurve` | `WINE_X11_INERTIA_CURVE` | `exponential` | `exponential`, `linear` |
| `InertiaRate` | `WINE_X11_INERTIA_RATE` | `4.0` | 0.5 to 16.0 |
| `WarpEmulation` | `WINE_X11_WARP_EMULATION` | `disabled` | `disabled`, `auto`, `enabled` |

The launcher sets none of these variables. A launch variable overrides a saved
choice for that launch. Named values ignore letter case. `off` and `0` mean
`disabled` where supported. Wine reports an invalid value in the normal launch
log, then tries the saved choice or default.

`TouchpadInertia=auto` currently behaves like `disabled` on X11.

## Safety rules

- A mouse-button press stops older scrolling inertia or middle-drag throw.
- Touchpad scrolling and pinch cannot change a control while a mouse button is
  held. Ignored movement cannot catch up after release.
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
| Maximum starting speed | 1,200 units per second |
| Largest continued update | 15 units per axis |
| Maximum continued travel | 480 units per axis, 960 units in total |
| Maximum continued updates sent to Live | 192 |
| Maximum continued time | 4 seconds |
| Movement used to judge a middle-drag throw | Latest 80 ms |
| Longest pause before middle-button release | 40 ms |
| Shortest middle drag that can throw | 4 ms |
| Required movement in the throw direction | 65% |

If Wine receives no clear end report, `TouchpadInertia=enabled` may begin
inertia after 100 ms without more scrolling. This requires the higher start
speed shown above.

Middle-drag throw starts only when the user releases the middle button. A
pause, reversal, cancelled drag or extra button press stops it.

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
3. Hold a fader and scroll or pinch on a touchpad. The fader must not change
   during the drag or after release.
4. Hold the left or right mouse button and turn a physical mouse wheel. The
   wheel must work with the default setting. Repeat with
   `WheelWhileButtonHeld=disabled`; the wheel must stop.
5. Make a fast smooth scroll. The view must keep moving after release and stay
   within the limits above. New input must stop it. Repeat with
   `TouchpadInertia=disabled`; direct scrolling must feel the same but stop with
   the touchpad or wheel.
6. Release a fast, straight middle-button drag. The view must keep moving only
   after release. A click, slow drag, pause, reversal or extra button press
   must not start a throw. Repeat with `MiddleDragThrow=disabled`; direct
   navigation must remain unchanged and stop at release.
7. Pinch in and out, including while holding Ctrl. Live must zoom and leave the
   physical Ctrl state unchanged. A cancelled pinch must stop zooming.
8. If Live pauses while loading a plug-in or browser folder during a fast
   scroll, it must not replay missed movement when it responds.
9. Repeat the held-control, inertia and throw checks in Live's main window and
   in a separate plug-in window.
10. Run the fader and knob checks on KDE/XWayland, GNOME/XWayland and Xorg. On
    XWayland, compare `WarpEmulation=disabled`, `auto` and `enabled` with the
    pointer shown and hidden. No setting may double the control's movement.

Record the pointing device, Linux distribution, desktop, Xorg or XWayland,
Live version, setting and result for each check.

## Known limits

- Wine cannot tell whether smooth scrolling came from a touchpad, a precision
  mouse wheel or a free-spinning wheel. All three may keep moving after input
  stops. Set `TouchpadInertia=disabled` to turn this off.
- On KDE/XWayland, inertia may start 100 ms after scrolling stops because the
  desktop may omit the end report.
- This work applies when Live runs through Xorg or XWayland. It does not apply
  when Live runs directly through Wayland.
- Testing the Max for Live pointer repair on the affected Fedora computer
  remains open.
