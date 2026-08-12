# Wine 11.13 base migration, 2026-07-21

This record explains the move from the giang17 `d2d1-dcomp-11.11` base to
`d2d1-dcomp-11.13` at `5c23dd1c`. `patches/BASE.txt` contains the current
per-patch provenance.

## Why the base moved

Wine 11.13 contained two point releases of upstream work and changes near this
project's popup and window-management patches. It also aligned the base with
the Wine version then used by ENCORE.

## How the series was moved

The 42-patch series at `7ea0c8b7dd` was first applied as commits to the old
source tree. Git then replayed those commits onto `5c23dd1c` with three-way
merge information.

Five textual conflicts required review:

- `dlls/dxgi/swapchain.c`: Wine's new cached fullscreen description replaced
  the older local hunk.
- `dlls/win32u/window.c`: the new `struct ratio` DPI API was combined with the
  project's decoration and frame-extents changes.
- `dlls/win32u/ntuser_private.h`: both added fields were retained.
- `dlls/winex11.drv/opengl.c`: patch 0020 was adapted to the renamed surface
  window field.

The remaining DirectComposition, Push 2, file-dialogue, and resize patches
replayed without textual conflicts.

## Build failures found after the rebase

A clean replay did not prove that the series still built. The container build
found three API changes in files that had not conflicted:

1. Wine moved frame-latency signalling into wined3d and returned a duplicated
   semaphore handle. Patch 0046 now obtains, releases, and closes that handle.
2. `get_dpi_for_window()` began returning `struct ratio`. Patch 0047 applies
   `round_dpi()` before calculating the menu band.
3. libusb detection moved from `AC_CHECK_LIB` to `AC_CHECK_FUNC`. Patch 0048
   updates both `configure.ac` and the generated `configure` script so the Push
   2 bridge is built when libusb is available.

The build audit now names missing Push 2 and file-dialogue artefacts instead of
failing without a useful message.

## Build log caution

`./build.sh | tee build.log` reports `tee`'s status unless the invoking shell
uses `pipefail`. Run the build directly or use:

```bash
set -o pipefail
./build.sh | tee build.log
```

Patch number 0027 remains intentionally unused. The three compatibility
patches above were initially numbered 0043 to 0045 and became 0046 to 0048
after later merges.
