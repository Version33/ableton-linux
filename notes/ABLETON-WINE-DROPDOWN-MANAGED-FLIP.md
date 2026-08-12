# Preferences dropdowns stay unmanaged

Live creates Preferences dropdowns as popup windows. Wine briefly changed a
mapped dropdown from unmanaged to managed after its style changed, causing the
window manager to decorate or reposition it.

## Cause and change

`winex11` recalculated the managed state after mapping. A transient style
change made the popup look like a normal top-level window even though changing
its X11 management mode after mapping is unsafe.

[Patch 0039](../patches/0039-winex11-never-flip-a-mapped-window-to-managed.patch)
keeps an already mapped unmanaged window unmanaged. It does not prevent Wine
from dropping management when a mapped window becomes unsuitable for desktop
management.

## Check the result

Open Live Preferences and exercise every dropdown. Confirm that each list
opens at its control, has no desktop decoration, accepts a selection, and
closes without moving the Preferences window. Repeat on X11 and Xwayland when
both are available.
