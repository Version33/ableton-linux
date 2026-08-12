# Pianoteq editor resize loop

With Live's Auto-Scale Plugin Window enabled, some Pianoteq editors repeatedly
resize or leave stale pixels. The host and plug-in apply different DPI
assumptions to the same child window, so each resize response requests another
size.

Disable Auto-Scale Plugin Window for the affected plug-in, close the editor,
and reopen it. This leaves other plug-ins unchanged.

The recorded trace showed a host-driven resize loop rather than a general Live
main-window growth problem. Patches 0040, 0042, 0058, and 0059 address menu,
window-manager, and present-path rounding elsewhere; they do not replace the
per-plug-in auto-scale choice.

For a new report, record desktop scale, Live's plug-in auto-scale setting,
Pianoteq version, editor size sequence, and whether the stale area follows the
old or new rectangle.
