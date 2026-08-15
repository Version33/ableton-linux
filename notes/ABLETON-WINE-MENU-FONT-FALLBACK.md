# Non-Latin text in Live's native menus

Live's Ableton Sans faces cover Latin text but not Cyrillic, Arabic, Hebrew,
Indic scripts, Thai, CJK, or Hangul. Replacing Wine's menu font with Ableton
Sans therefore made some translated labels and project names render as boxes
or disappear.

## Registered fallback chain

The launcher links Live's UI fonts into the prefix and registers this Wine
`SystemLink` chain:

1. Tahoma
2. Live's Noto Sans CJK JP, SC, and KR faces
3. Live's Unifont-JP and Unifont Upper faces

The family value must use the font's name-table ID 1. Live's Japanese file, for
example, resolves as `Noto Sans CJK JP Regular`, not the shorter typographic
name printed first by some fontconfig commands.

## Select a fallback while drawing

Wine normally consulted `SystemLink` while selecting a font by charset, not
while drawing missing glyphs. Patch 0054 checks the complete menu string with
`NtGdiGetGlyphIndicesW`, selects the first registered family that covers it,
and measures the item with the same face. The candidate limit is 16 so the
six-entry chain cannot be truncated.

The current implementation switches the whole string to one fallback face.
A mixed Latin and CJK comparison found no useful visual reason to add
per-glyph shaping to this Win32 menu path.

## Test without host-font contamination

Wine imports host fonts into the prefix registry. Changing `FONTCONFIG_FILE`
after a prefix has started does not remove those saved paths. For an isolated
test, create a fresh prefix with an empty fontconfig directory list and confirm
that `system.reg` contains no host font paths.

Use `WINEDEBUG=+font` and inspect `load_system_links`: `Adding file` identifies
a resolved entry and `Unable to find file` identifies a name mismatch. Check
Cyrillic, Arabic, CJK, and mixed-script menu text, including measurement and
selection highlighting.
