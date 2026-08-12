# Wine 11.13 rebase assessment from 2026-07-17

This is the pre-migration assessment for the 33-patch series that existed on
2026-07-17. The migration later completed; use
[the migration record](ABLETON-WINE-11.11-TO-11.13-BASE-BUMP.md) for the
result and `patches/BASE.txt` for current provenance.

## Upstream state reviewed then

- Wine 11.12 and 11.13 added 414 commits after 11.11.
- giang17 provided `d2d1-dcomp-11.12` at `b6a83690`; no 11.13 branch existed
  on the review date.
- Wine's file-dialogue merge request remained a draft and bug 57955 remained
  open.
- Wine had accepted the d2d1 vertex-type leak change, so a local duplicate
  would need removal.

## Areas expected to need work

The review identified changes in client-surface ownership, the OpenGL thunk
layout, fractional-DPI structures, shared session memory, raw input, frame
latency, and fullscreen swapchain checks. The DirectComposition, winealsa,
comdlg32, and mount-reporting areas had less upstream movement.

The proposed order was shared memory, OpenGL, client surfaces, dxgi, DPI, then
winex11 input and frame handling. That ordering remains useful history, but its
patch numbers and source references are stale.

## Checks proposed then

The plan required a container build, series hash refresh, fresh and upgraded
prefixes, and focused probes for geometry, DPI, DirectComposition, OpenGL,
devices, portals, audio, input, and stability. Manual coverage included Live
windows, plug-in editors, Learn View, audio and MIDI reconnects, Push 2, file
dialogues, Xwayland dragging, mount browsing, non-US keyboards, long pointer
drags, fullscreen, and several desktop scales.

Do not reuse this document as a current rebase checklist without comparing the
latest source, patch series, installer, and test suite.
