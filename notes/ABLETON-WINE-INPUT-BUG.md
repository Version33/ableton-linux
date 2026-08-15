# Plug-in input and window activation changes

Patches 0016 to 0020 address four separate failures found during the same Live
sessions. They affect JUCE input, X11 activation, shared Wine session data, and
OpenGL pixel formats.

## Preserve the DirectComposition window procedure

JUCE 8 can recreate a composition target on the same editor window. Wine could
record its own subclass as the original procedure, then leave that subclass in
place after releasing the target. Painting continued while mouse and hit-test
messages went to `DefWindowProcW`.

Patch 0016 stores the real original procedure separately, never chains the
subclass to itself, and removes only state owned by the released target.

## Send a real activation timestamp

Mutter rejected `_NET_ACTIVE_WINDOW` requests with timestamp zero. Wine then
deduplicated the retry, leaving focus, menus, and mouse activation pending.
Patch 0017 sends the last processed input timestamp.

## Keep shared session mappings current

A read-only wineserver session mapping used `MAP_PRIVATE`, so a client could
stop seeing later object records. Class registration then reached window
creation with a null procedure and Live spent about 2.4 seconds handling each
exception.

Patch 0019 requests a writable shared view and retains a read-only fallback.
Patch 0018 pre-dirties new server blocks and corrects the block-end comparison.
A 30,000-iteration class create/destroy run crossed mapping growth without the
previous mismatch.

## Advertise sRGB formats

Wine's EGL path did not advertise an sRGB-capable format, so baseview and
nih-plug editors requesting `srgb: true` could abort. Patch 0020 advertises
8-bit RGB sRGB formats when `EGL_KHR_gl_colorspace` is available and retries
surface creation with the default colour space if needed.

Use `tools/swamprobe.c`, `glchild.c`, `menutest.c`, and `stresstest.c` for
focused checks. Affected editors must still be opened, used, resized, closed,
and reopened in Live.
