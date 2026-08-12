# Open Live browser items in the Linux file manager

Release 2026.08.01.1 shipped the complete folder handling for issue 41.
Patches 0043, 0063, and 0064 route Live's Explorer commands to the desktop file
manager and keep Wine Explorer as a fallback.

## File and folder requests

Live uses `explorer.exe /select,"<path>"` for a reveal. Patch 0043 recognises
an existing target and calls the XDG OpenURI portal. This worked for files,
but `OpenDirectory` is defined around a file descriptor and some backends did
not handle a directory target consistently.

Patch 0063 sends folder selection to
`org.freedesktop.FileManager1.ShowItems`, opening the parent and selecting the
folder. It percent-encodes the file URI so non-ASCII names do not depend on the
process locale.

Live's library panel uses folder-open forms such as `/e,"<folder>"`, not
`/select`. Patch 0064 recognises `/e`, `/root`, and a bare existing directory
and calls `ShowFolders` so the directory itself opens.

The fallback order is FileManager1, the portal where applicable, then Wine
Explorer. Missing paths, unsupported switches, 32-bit callers, disabled portal
policy, and service failures retain the Wine path.

## Check the desktop call

Use `dbus-monitor` while revealing a file, selecting a folder, and opening a
library folder. Expect `ShowItems` for selection and `ShowFolders` for an open.
Check spaces, non-ASCII names, a stopped portal backend, and
`FileDialogPortal=never`. A file manager may open the parent without visibly
selecting the item; that final behaviour belongs to its backend.
