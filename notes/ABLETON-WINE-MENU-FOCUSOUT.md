# Menus survive transient X11 focus changes

Live menus could close as soon as they opened because winex11 cancelled menu
tracking on a temporary `FocusOut` event. The focus move belonged to the popup
and did not mean that the user had left Live.

[Patch 0038](../patches/0038-winex11-don-t-cancel-menu-tracking-while-the-focus-s.patch)
keeps tracking while focus remains within the same Wine menu interaction. A
real activation change still closes the menu.

Check mouse and keyboard opening, submenus, click-away dismissal, Alt
navigation, switching to another application, and X11 and Xwayland sessions.
Pair this with patch 0017's activation timestamp check when a failure also
affects window focus.
