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

Confirm the adapter name and Enable GPU Renderer setting in Live. Exercise
Learn View, Splice, Max for Live selection, plug-in editors, resizing, full
screen, and fractional scaling. Record idle and active CPU separately and
check the log for patch 0071 diagnostics. The PipeASIO 1.5 update does not
reduce Live's CPU use.
