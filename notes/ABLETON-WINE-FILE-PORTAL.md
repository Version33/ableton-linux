# Native Linux file dialogues

[Patch 0031](../patches/0031-comdlg32-add-XDG-file-dialog-portal.patch) lets
Wine's common file dialogue use the XDG desktop portal. Live then receives the
selected Windows path through its existing Win32 dialogue call.

## Selection rules

Set `WINE_FORCE_PORTAL=1` to request the portal. The launcher enables it for
Live. Wine falls back to its built-in dialogue when the portal is unavailable,
returns an error, or cannot represent the request.

The implementation covers open, multi-open, save, and folder selection. It
translates filters, the initial folder, the proposed filename, and returned
URIs. It keeps Wine's validation and buffer-size handling after the portal
returns.

The portal does not grant permanent access by itself. The selected path must
remain visible inside the Wine prefix or through Wine's Unix path mapping.

## Check the path

Run `tools/portalprobe.exe` under the project Wine build, then exercise Live's
Open, Save As, export, and folder selection actions. Test cancellation, spaces,
non-ASCII filenames, multiple selection, and an unavailable portal service.

The host needs a working `xdg-desktop-portal` service and a backend for the
desktop. A missing backend should produce the Wine dialogue fallback, not a
hung request.
