# Learn View rendering paths

Two different artefacts affected Live's WebView2 panes: alternating content
while a pane was open, and a stale frame left in the pane rectangle after it
closed. Keep them separate when reporting a regression.

## Make DirectComposition content visible

[Patch 0041](../patches/0041-dxgi-make-dcomp-presents-visible-on-webview2-s-unat.patch)
gives an unattributed `WS_EX_NOREDIRECTIONBITMAP` target an opaque layered
surface, rejects stale-size copies, and retries a small number of reblits after
a resize. Attributed layered windows such as JUCE shadows are unchanged.

With Live's former GDI renderer, Chromium's software frame and Wine's current
composition frame could alternate. Enabling Live's GPU renderer made the
captured frames agree on the measured WebView2 149 setup. See
[the recorded comparison](ABLETON-WINE-GPU-RENDERER-WEBVIEW2-DIAGNOSIS.md).

## Stop painting after a pane closes

Live parks the WebView2 target instead of destroying it. Wine could continue
copying the last composition buffer into the now-hidden pane area. Patch 0056
stops parked reblits while the target or an ancestor is hidden and resumes
when the chain becomes visible again.

## Check both states

Open, resize, scroll, close, and reopen both Learn View and the documentation
sidebar. Repeat at 100 and 125 per cent scale and check JUCE shadow windows and
SWAM editors for shared DirectComposition regressions.

Useful tools include `dcompspy.c`, `hwndspy.c`, `xdmg.c`, `xsamp.c`, `xgrid.c`,
and `xsettle.c` under `tools/`.
