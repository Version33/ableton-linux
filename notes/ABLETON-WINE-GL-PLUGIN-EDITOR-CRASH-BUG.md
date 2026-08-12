# OpenGL plug-in editors and depth mismatches

Some OpenGL plug-in editors crashed or failed to draw when Wine created their
child surface with a visual that did not match the drawable used by the device
context.

## Cause and change

The EGL path could select a default visual while the X11 drawable belonged to
a different depth. X then rejected operations on the mismatched drawable.

[Patch 0026](../patches/0026-winex11-report-the-drawable-s-visual-in-set_dc_drawa.patch)
reports the drawable's actual visual to the OpenGL setup path. Patch 0020 also
advertises and honours sRGB-capable pixel formats needed by plug-in editors.

## Check the editor

Open, resize, close, and reopen affected editors. Test docked and floating
windows, more than one instance, and both X11 and Xwayland. An editor rendering
correctly does not prove that its audio path or saved state is correct; test
those separately.
