# Live GPU rendering

Prefix setup removes the old `-_ForceGdiBackend` option so Live can use its GPU
renderer. This change removed the measured Learn View and Splice alternation
and reduced idle CPU to one to two per cent on the test system. Those numbers
describe that system, not every Linux computer.

## Present frames without a CPU readback

Before patch 0055, Wine copied each finished top-level frame from graphics
memory to main memory and sent a full image to X11. Continuous UI activity
produced about 650 MB/s of display traffic in the recorded issue 91 trace.

[Patch 0055](../patches/0055-dxgi-prefer-GL-present-for-top-level-swapchain-devic.patch)
uses Wine's direct GL present path for eligible top-level swapchains. Compare
the earlier path with:

```bash
env WINE_DISABLE_GL_PRESENT=1 ableton-live
```

## Keep fractional-scale frames aligned

The direct path exposed a frame drawn below its window at fractional scale.
Patch 0058 takes the GDI path when the present-time client rectangle disagrees
with the swapchain rectangle. Patch 0059 queries both rectangles in the
window's DPI context, which removes the known source of that disagreement.

Patch 0071 counts sustained mismatches and writes one diagnostic line after
the threshold is reached. Current launcher output is also saved at
`${XDG_STATE_HOME:-$HOME/.local/state}/ableton-wine/logs/live.log`. Search it
with:

```bash
grep -i 'sustained present-size mismatch:' \
  "$HOME/.local/state/ableton-wine/logs/live.log"
```

Include the whole line in a report. It contains the desktop and window DPI
needed to reproduce the fallback.

## Report the real graphics device

Live disables its renderer when Wine names an old or unsupported device.

- Patch 0035 adds Intel Battlemage G21.
- Patch 0057 adds Intel devices from Ice Lake through current Arc generations.
- Patch 0061 uses the driver's reported name, PCI identifiers, and video
  memory when Wine has no table entry.

These changes let Live decide against the actual adapter instead of a generic
HD 4000 or Radeon HD 5600 fallback.

## Check a renderer change

To confirm which path a build uses, start Live with
`WINEDEBUG=fixme+all,err+all` and count the message `Using GDI present`
in the log. One occurrence means the copy path. Zero means the direct
path. The launcher sets `WINEDEBUG=-all,+winediag` by default, so pass
`WINEDEBUG` explicitly. Turn tracing off when measuring bandwidth,
because the log's own writes count toward `/proc/<pid>/io`.

These measurements come from one machine (AMD Navi 31, COSMIC/Wayland
via XWayland). Confirmation on Intel or NVIDIA hardware and on a
non-Wayland session is still open.

### The direct path can land the frame low; patch 0058 gates it (2026-07-30)

Two reports show the direct path drawing Live's frame too low, a black
band on top and the bottom rows clipped, while input hit-testing stays
on the real layout: niri/XWayland at 125% (reported on PR 98, about
476 px low) and KDE Plasma with NVIDIA when Live's Enable HiDPI Mode
setting is on (issue 100). KDE floats its windows, so a tiling-only
explanation does not cover both.

The candidate mechanism both share sits in the present path. The
destination rect is captured on Live's thread in the window's DPI
context (patch 0023). The blit's y-flip re-queries the client rect
later, on wined3d's CS thread, in that thread's DPI context
(`wined3d_texture_translate_drawable_coords`). Nothing forces the two
queries to agree: the threads can hold different DPI awareness, and
the window can be resized between capture and execution. On a
disagreement, GL's bottom-left origin lands the frame low by the
difference.

Patch 0058 gates the direct path on agreement, per frame: it re-queries
the client rect on the CS thread and compares it with the captured
destination rect. Matching frames keep the direct path. Disagreeing
frames take the GDI path, which anchors top-left and renders correctly
under the same mismatch. On an affected setup every frame disagrees,
so the swapchain behaves as if `WINE_DISABLE_GL_PRESENT=1` without
anyone setting it, and healthy setups keep the direct path. The
fire-once FIXME `Present-time client rect disagrees` plus a
rate-limited TRACE record both rects and the backbuffer size, so an
affected machine can show which side lies, toward a root fix in
`translate_drawable_coords` itself.

Runtime verification is below: the gate is correct, and the
disagreement it detects has a root cause worth fixing.

### The disagreement is a DPI-context gap; patch 0059 closes it (2026-07-30)

The trigger is fractional display scaling, not a compositor, a driver
or a window manager. It reproduces on AMD Navi 31 under COSMIC/Wayland
(a setup with no symptom at 100%) by putting the prefix at 125%
(`ABLETON_DPI_MODE=dpi120`, LogPixels 120). That covers both reports:
niri at 125%, and issue 100's KDE/NVIDIA machine, where the trigger is
Live's Enable HiDPI Mode.

Patch 0023 brackets the present-time client-rect queries with the
window's own DPI awareness context, in `wined3d_swapchain_present`,
`wined3d_swapchain_resize_buffers`, `wined3d_swapchain_state_init` and
`d3d12_swapchain_resize_buffers`. It does not cover
`wined3d_texture_translate_drawable_coords`, the one that runs on the
CS thread. The flip subtracts a height resolved in that thread's
inherited context from a destination rect resolved in the window's,
and under scaling those are two different numbers for the same window.

Patch 0059 brackets that query the same way, and 0058's gate with it.
The second half is not optional: the gate runs before the blit and
sends mismatched frames to `swapchain_blit_gdi()`, which never reaches
the flip, so an unbracketed gate diverts every scaled frame and the
corrected flip never runs. The first build of 0059 showed no bar and a
healthy frame rate while its own FIXME had fired zero times.

Measured at 125% on one machine, mouse moving over the window, Live's
CPU sampled with `top -b`, 15 readings at 2s (one core = 100%):

| Series | Black bar | Live CPU | Present path |
|---|---|---|---|
| 0055, no 0058 | yes | 29.8% | direct |
| + 0058 | no | 98.9% | copy |
| + 0058 + 0059 | no | 25.2% | direct |

0058 on its own trades the bar for the copy path's cost on every
scaled setup, and that cost is not noticeable by feel, only by
measurement. With 0059 there is nothing to trade: the bar is gone and
the direct path survives. 0058 stays in as the safety net, silent, and
as the assertion that the two contexts now agree.

### The fallback now reports itself; patch 0071 counts it (2026-08-05)

The section above calls the 0058 gate silent. Patch 0071 supersedes
that. The gate now counts its own decisions and reports a sustained
fallback.

The reason is the row in the table above. A machine on the copy path
loses about one processor core. The screen stays correct. The user
feels a slow computer and sees no cause. Before patch 0071, the only
signs were one FIXME line and some TRACE lines. The launcher hides
both. A swapchain could stay on the copy path for a full session, and
no record existed.

Patch 0071 adds counters to each swapchain. A swapchain is the set of
frame buffers that Wine keeps for one window. The counters record: the
number of gate decisions, the number of fallback frames, the longest
unbroken run of fallback frames, and the longest run that repeats one
identical pair of rectangles.

The repeated pair is the test that separates a window resize from a
real fault. During a resize, the window size changes on every frame,
so the two compared rectangles also change on every frame. A
persistent fault compares the same two rectangles on every frame. When
the same pair repeats for 120 frames, about two seconds, the gate
reports a fault. A second rule covers faults that alternate between
rectangle pairs: when more than half of the frames in a five-second
window fall back, and this happens in two qualifying windows, the gate
also reports a fault. A pause of at least one second discards an
unfinished window. One completed strike survives pauses shorter than
30 seconds, so a fault that presents in bursts longer than five seconds
still warns; a pause of 30 seconds or longer clears it before unrelated
activity can accumulate. The five seconds are the mechanism, not a
margin: a burst shorter than the ratio window never completes one, so it
never scores a strike at all. Carrying the strike across the pause is
what lowers the requirement, from about twelve seconds of unbroken
mismatch to about five and a half.

The 30-second reset is a chosen trade rather than a derived bound. It
admits one narrow false positive: two 6-second bursts of more than half
fallback warn across any gap shorter than 30 seconds. Measured healthy
sessions sit well below that shape.

The report prints once for each swapchain and has two parts. Two
`ableton-wine:` lines always print, on every WINEDEBUG setting. They
name the symptom and ask the user to open an issue. One
`err:winediag:` line carries the evidence: both rectangles, the
backbuffer size, both DPI awareness contexts, the window DPI, the
window styles, the swapchain flags, the GPU name, and the session type
and desktop from the host environment. Wine prefixes host XDG_*
variables with WINE_HOST_ in the Win32 environment block, so the patch
reads WINE_HOST_XDG_SESSION_TYPE and WINE_HOST_XDG_CURRENT_DESKTOP.
The line stays on one line so a user can copy it whole into an issue.
The launchers, the Max 9 launcher, and the beta tester kit now set
`WINEDEBUG=-all,+winediag`, which keeps all debug output off and lets
only these rare notices through. When Wine destroys a swapchain that
warned, it prints one summary line with the totals, so a long session
leaves a record even when nobody watched it.

A desktop launch inherits stderr from the desktop environment, which may
be /dev/null, so the notice needs somewhere to land. `scripts/ableton-live`
tees stderr to `~/.log/ableton-wine/live.log` and `bin/ableton-live-beta`
to `live-beta.log` beside it; the tester kit's `run-session` already
captures both streams into its session file. Each launcher starts a fresh
log only when it is the one bringing Live up: every Live desktop entry
(`.als`, `.auz`, `ableton://`) runs the same launcher again to hand its
argument to the running instance, and truncating on that path would wipe
the warning the running session had already recorded.

Status on 2026-08-07: the patch compiles clean and the built
`wined3d.dll` contains both audit fingerprints. At 125%, the persistent
fault rig fired at exactly identical-pair 120, with dst
(0,0)-(1706,896) against client (0,0)-(1365,717). A separate 26-second
healthy edge drag at 100% (96 DPI) measured 613 of 3028 presents
falling back, longest run 7, and no warning. The ratio rule's idle-gap
and maximum-counter paths are model-checked. The normal 125% resize and
full-session checks below remain runtime acceptance checks:

1. Build with the 0059 `swapchain.c` bracket reverted. The gate then
   compares a CS-thread-context height against a window-context
   dst_rect and disagrees on every scaled frame. Set the prefix to
   125%. Start Live and move the mouse over the window. The warning
   must appear within about ten seconds. Reverting the 0059
   `texture.c` hunk instead does not work: the bar returns, but the
   bracketed gate still sees two rectangles that agree.
2. On a normal build at 125%, drag a window edge for ten seconds. The
   warning must not appear.
3. On a normal build, run a full session. No `Sustained present-size
   mismatch` line and no destroy summary must appear.

Status on 2026-08-08: the burst figures above come from review, from a
sweep of the counter logic rather than a Live session. Sweeping burst
length at 100% mismatch with 6-second pauses, bursts of 5.5 seconds and
longer warned, and bursts of 5 seconds and shorter stayed silent through
3000 mismatched frames. The same sweep put the false-positive boundary at
a 30-second gap. A Live session has not been run against these thresholds;
acceptance checks 1 to 3 above still stand.

## Device identification (added 2026-07-30, updated 2026-08-01, issue 84)

Live checks the graphics card before it enables the GPU renderer. It
reads the device name and PCI ID that wined3d reports, and wined3d
takes both from a device table. A card missing from that table is
reported as "Intel(R) HD Graphics 4000", a 2012 device that Live
rejects. On such a machine Preferences > Display & Input greys out
"Enable GPU Renderer" with the reason text "Intel(R) HD Graphics
4000: Unexplained slow UI at zoom-level 100% and/or crashes", and
nothing else in this note applies.

The table ended at 2018's Coffee Lake, plus one Battlemage entry from
patch 0035. Wine patch 0057 adds the families from Ice Lake through
Lunar Lake and the Arc A-series cards, so Live sees a current device
name and its own check passes. Confirmed on issue 84's Meteor Lake
laptop 2026-07-30: stickyfran built this branch and the GPU renderer
enabled (issue 84 comments).

Patch 0061 covers devices missing from the table by synthesising the
description from the driver's own renderer string. That is not enough
for Meteor Lake: the synthesised name, "Intel(R) Arc(tm) Graphics", is
the device's real Windows name, and a build with 0061 alone stayed
greyed out on the same laptop (PR 105 comments, 2026-07-31). A table
entry takes precedence over 0061, and the "(MTL)" suffix in 0057's
entry is what passes Live's check. A traced launch from that machine
confirming the exact rejected name is still open.

The two paragraphs above explain the refusal by the reported name.
That explanation is wrong, and the subsection below replaces it.

To check a machine: open Preferences > Display & Input. "Enable GPU
Renderer" must be a switch, not greyed out with the HD 4000 reason
text.

### Live matches ID numbers, not names (2026-08-02, patch 0066)

Every graphics chip reports a vendor number and a device number. Live
reads only those numbers: it refuses a device number found on an
internal list of 101 Intel parts sold between roughly 2004 and 2014,
and the name appears only in the refusal message. Established by
reading `Ableton Live 12 Suite.exe`. A suffix cannot matter to a check
that never reads names, which rules out the "(MTL)" account above.

When Wine cannot identify a card it reports Intel device `0x0162`,
which is on Live's list, so every unidentified Intel card arrives
wearing a refused identity. Patches 0066 through 0068 close the gaps:
0066 adds the missing 2015 to 2019 table entries, 0067 keeps an
unlisted card's real identity when the driver reports no video memory,
and 0068 adds the opt-in `WINE_D3D_FORCE_GPU_RENDERING=1` substitution
for the parts Live genuinely lists, disclosed in the device name. Each
patch header carries its mechanism and evidence.

#### Reading a machine's log

```bash
grep -a "TD3dSurface: Adapter\|GPU Renderer:\|Can't use GPU" \
  ~/.wine-ableton/drive_c/users/*/AppData/Roaming/Ableton/Live*/Preferences/Log.txt | tail
```

An `Adapter:` line carries the pair Live received: `(8086:0162)` is the
invented identity, `(8086:3e92)` a real one. The line appears only
while Live draws through Direct3D, so it is absent with
`-_ForceGdiBackend` set and after Live has refused the renderer. A
`Can't use GPU renderer:` line records a refusal, but Live writes it
only when the preference is already on, so its absence proves nothing
at the default of off.

The fastest datum from a reporter is a screenshot of Settings > Display
& Input. "Unexplained slow UI at zoom-level 100% and/or crashes" means
the ID pair was refused. "Gpu rendering is incompatible with
_ForceGdiBackend" means the legacy flag is still set. "Cannot fetch
IDXGIAdapter1" means Live found no adapter.

Use `find ~/.wine-ableton -name Options.txt` to check for that flag
file; in fish a glob that matches nothing aborts the whole command.

## Related

- [Diagnosis narrative](ABLETON-WINE-GPU-RENDERER-WEBVIEW2-DIAGNOSIS.md)
- [Learn View flicker mechanism](ABLETON-WINE-LEARNVIEW-FLICKER.md)
- [Patch 0053](../patches/0053-winex11-export-the-app-minimum-tracking-size-as-PMin.patch)
- [Patch 0055](../patches/0055-dxgi-prefer-GL-present-for-top-level-swapchain-devic.patch)
- [Patch 0057](../patches/0057-wined3d-add-Intel-graphics-devices-from-Ice-Lake-to-.patch)
- [Patch 0066](../patches/0066-wined3d-add-the-missing-Intel-devices-from-Skylake-t.patch)
- [Patch 0071](../patches/0071-wined3d-count-and-report-sustained-present-size-fall.patch)
- Resize trace from the diagnosis session:
  `~/Projects/Code/ableton/live-resize-trace-gpu-20260727.log`
  (machine-local)
