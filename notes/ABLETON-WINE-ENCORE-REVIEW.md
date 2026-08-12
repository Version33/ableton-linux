# ENCORE changes reviewed for Ableton Linux

The ENCORE Wine work informed several changes in this project. Each adopted
change was checked against the local patch series and Live behaviour rather
than copied as a group.

## Changes retained here

- Patch 0033 reports Unix mount points as ordinary directories when
  `WINE_DISABLE_UNIX_MOUNT_REPARSE=1`. Live's browser otherwise treats some
  host paths as unresolved junctions.
- Patch 0034 flushes `XdndStatus` replies before the drag source waits for
  them, preventing drag-and-drop stalls.
- Patch 0042 handles fractional-scale configure rounding. The local version
  records a requested rectangle and aliases only a sub-scale-equivalent grant.

The resize work is documented in
[FINDINGS-RESIZE-GROWTH-2026-07-21.md](FINDINGS-RESIZE-GROWTH-2026-07-21.md).

## Changes not adopted

Other ENCORE changes overlapped local patches, targeted different applications,
or lacked a reproduced Ableton failure. They remain references, not implicit
parts of this runtime. Recheck current upstream code and the local patch
series before importing any later ENCORE change.
