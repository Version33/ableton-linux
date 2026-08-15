# Live 11 media crash in `wmvcore`

Previewing or importing WMA or video can crash Live 11 because Wine raises
`EXCEPTION_WINE_STUB` from `wmvcore.dll`. Live 12 does not use this path. No
Wine patch exists yet, so avoid those formats in Live 11.

## Evidence needed for a patch

Sampled dumps use exception code `0x80000100` and identify `wmvcore.dll`, but
they do not name the missing export. Capture it with:

```bash
env ABLETON_LIVE_VERSION=11 WINEDEBUG=-all,fixme+wmvcore \
  ableton-live 2>&1 | tee "$HOME/live11-wmvcore.log"
grep -E 'fixme:wmvcore:[A-Za-z0-9_]+ stub' \
  "$HOME/live11-wmvcore.log" | sort -u
```

The implementation must use the confirmed SDK signature and documented error
behaviour. Guessing the arguments can corrupt a 32-bit caller in the WoW64
runtime.

## Install and repair Live 11

Use the current installer command and name Live 11 explicitly when the file
name is ambiguous:

```bash
sh install-ableton-latest.run install \
  --live-installer "$HOME/Downloads/Ableton Live 11 Installer.zip" \
  --live-major 11 --link=session
```

After the first Live 11 launch, close Live and run:

```bash
sh install-ableton-latest.run prefix repair-live11
```

The repair moves incompatible Max 8 preferences to a timestamped backup. When
Live 11 and Live 12 share a prefix, select Live 11 with:

```bash
env ABLETON_LIVE_VERSION=11 ableton-live
```

Authorisation belongs to the prefix's `MachineGuid`, so preserve the prefix.
Never share a real authorisation URL or `.auz` file.
