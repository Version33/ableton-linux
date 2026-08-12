# Plug-in title bars and layered shadows

Some floating plug-in windows lost their title bar, received a second desktop
decoration, or placed a JUCE shadow at the wrong scale. The affected windows
combine Win32 tool-window styles, custom non-client drawing, and layered child
surfaces.

## Changes used here

Patches 0010 to 0014 refine when captioned tool windows receive native window
manager decorations. The final path gives suitable top-level tool windows one
desktop decoration while leaving Live's custom child and popup windows alone.

Patch 0015 synchronises layered attributes to the scaled surface so JUCE
DropShadower windows keep their position and opacity after DPI changes.

Earlier attempts reconstructed frame extents for every tool window and were
reverted because they disturbed custom non-client windows. The current patches
select by actual caption, ownership, and top-level state.

Check editors with and without their own title bar, modal plug-in windows,
drop shadows, drag and resize, closing, more than one monitor, and fractional
scale. A title bar result does not cover editor input; use the separate input
checks for that path.
