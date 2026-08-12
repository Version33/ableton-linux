# Live Browser clip and track save failures

Status: issue #165 needs a target folder and a comparison with the User
Library before the project can identify the failing layer. The Linux profiler
provides targeted, path-redacted diagnostics. This note does not claim a
runtime fix.

## Reported behaviour

Live can save a Clip as `.alc` or a track as `.als` when someone drags it from
the timeline into a folder in Live's Browser. Issue #165 reports that Live
instead shows one of these errors:

```text
<FolderHierarchy>\Untitled.alc could not be opened
<FolderHierarchy>\<TrackName>.als could not be opened
```

The report identifies NixOS 26.11 and a Wayland session. It does not identify
the target folder, its permissions, its filesystem, its mount options, or
whether the User Library fails too.

## Code path

This action stays inside Live. Live creates the `.alc` or `.als` file in the
folder already shown in its Browser. The action does not use the host desktop
handler for `.als` files, and it does not drag a file between Linux and Live.

The launcher already sets `WINE_DISABLE_UNIX_MOUNT_REPARSE=1`. Patch 0033 then
reports Unix mount boundaries as ordinary folders. Live can otherwise treat a
mount boundary as a Windows junction that Wine cannot resolve. The existing
setting makes that known failure less likely, but the issue does not show
whether the affected installation used this launcher.

## Diagnostic split

Test the same Clip or track against these targets:

| Result | Next check |
| --- | --- |
| User Library works | Check the chosen folder's permissions, filesystem, mount, and links. |
| User Library also fails | Check the launcher, prefix user folder, and runtime. |
| A folder under `/nix/store` fails | Move the library to a writable folder. The Nix store is read-only. |
| A local folder works but a removable or network drive fails | Compare the filesystems and mount options. |

Run the profiler with the failed folder:

```bash
env ABLETON_LIBRARY_PATH="/path/to/folder" ./beta/scripts/ableton-linux-profiler.sh
```

The report records whether the folder exists, accepts writes, crosses a link,
and which filesystem provides it. It prints the label
`requested_library_path` instead of the folder path.

## Remaining evidence

An affected report needs:

- Live version and edition
- project version
- User Library result
- local, removable, network, or `/nix/store` target type
- profiler output with `ABLETON_LIBRARY_PATH` set to the failed folder

If the folder accepts writes and the User Library also fails, capture the
Windows file operations around the drag. That trace can separate Live's path
validation from a runtime file-create failure.
