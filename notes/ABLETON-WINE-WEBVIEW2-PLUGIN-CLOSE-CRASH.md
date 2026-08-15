# WebView2 editor crash during close

Issue 52 affected WebView2-based VST3 editors such as Splice INSTRUMENT.
Closing the editor could show Live's "serious program error" dialogue.

## Cross-process drop target

The WebView2 helper registers an OLE drop target on its child window. Live's
host-side teardown can enumerate that foreign child and call
`RevokeDragDrop`. Wine then read a raw `IDropTarget` pointer created in the
helper process and called its vtable from Live, causing an access violation.

Patch 0045 makes `RevokeDragDrop` reject a window owned by another process,
matching `RegisterDragDrop`. The helper can still revoke its own target.

## Focused check

`tools/webviewclose.c` hosts a WebView2 controller and reproduces several
teardown orders. Variant `e` revokes descendants before closing; it faulted on
the unpatched runtime and completed on the patched build. Build it with
`tools/build_webviewclose.sh` and a matching Wine source tree.

The patch changes Wine OLE behaviour and does not depend on this project's
DirectComposition patches. Check repeated editor open and close, more than one
editor, drag-and-drop, and normal Live shutdown after any OLE update.
