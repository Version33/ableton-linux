# Learn View open-pane flicker investigation, 2026-07-27

This investigation began with a grey Learn View frame alternating with the
rendered page at about 5 Hz. The production prefix used WebView2 149 and Live's
GDI renderer.

## Measured result

Removing `-_ForceGdiBackend` from `Options.txt` enabled Live's GPU renderer and
removed the visible alternation on both the production Wine 11.11 runtime and
the Wine 11.13 build tested that day. Thirty captures from each pane had the
same hash at 200 per cent scale. The maintainer also reported idle CPU at one
to two per cent during that run.

The reblit timer still ran, so this result did not replace the underlying
DirectComposition work. It established that the two visible writers produced
the same content when Live used its GPU renderer.

Live supplied its own WebView2 flags:

```text
--disable-gpu
--disable-gpu-compositing
--disable-direct-composition
```

Process command lines confirmed that launcher-supplied browser flags did not
control the page renderer in this case.

## Earlier mechanism

Patch 0041 made the DirectComposition frame visible in an unattributed child
window. Chromium's stale software frame could still paint into the same area.
With the GDI renderer, the two frames alternated at the reblit cadence.
`learnheal.exe` tried to make them converge by changing the settled pane width
by one pixel, but WebView2 149 at 2x scale did not converge reliably.

A giang17 compositor backport was built on a separate branch but was never run
against Live. It is not evidence for current behaviour. Fork issue 8 also
reported a delegated-compositing regression in WebView2 149 and 150, so the
unrun backport was not promoted.

## Current references

- [Live GPU renderer](ABLETON-WINE-GPU-RENDERER.md)
- [Learn View rendering](ABLETON-WINE-LEARNVIEW-FLICKER.md)
- [M4L selection flicker](ABLETON-WINE-M4L-SELECTION-FLICKER.md)

For a new report, record the WebView2 version, display scale, selected Live
renderer, launcher and runtime paths, and repeated frame captures. Separate an
open-pane alternation from stale pixels left after closing the pane.
