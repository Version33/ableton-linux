# Live 11 installer waits and the USB driver package

Issue 111 covered installs that waited after Live completed and updates that
waited at prefix initialisation. Ableton's Windows USB driver installs a
resident control-panel process. `wineserver -w` then waits for a process that
may have no window.

## Live installer families

Live 12 uses Inno Setup. The project passes silent flags and excludes its audio
driver task. Live 11 uses WiX Burn and needs `/passive /norestart`.

Live 11 bundles have two observed generations:

- WiX 3 in Suite 11.3.25 always plans the non-vital Push audio driver MSI. The
  MSI can fail under Wine while Live installation continues.
- WiX 4 in Trial 11.3.35 and Suite 11.3.42 uses
  `InstalledPush3AudioDriverVersion` to decide whether to run driver version
  5.68.0.

The installer detects Burn from the `.wixburn` PE section and distinguishes
WiX 4 through its `wixtoolset.dutil` build string. Edition alone does not
identify the generation.

## Skip the WiX 4 driver

For WiX 4, setup temporarily registers a placeholder product at version
99.0.0 under the driver's upgrade code. Burn then decides that the driver
package does not need to run. Setup removes the invented product registration
afterwards.

The same seed is not used for WiX 3. That generation always executes the
package and can remove a related placeholder registration while leaving an
orphaned product key.

A Windows USB kernel driver cannot run under Wine, and Live uses PipeASIO for
audio, so skipping the package does not remove a Linux audio function.

## Stop stale resident processes

Prefix setup removes automatic start entries that point into Ableton USB or
Push driver directories. It matches the path in HKLM and HKCU Run keys and in
both Startup folder spellings because the image name differs by driver
generation and may appear as an 8.3 path.

The waits after `wineboot` and after Live's installer have a 30-second limit.
On timeout, setup stops the prefix wineserver and waits again with a limit.
This also handles a WebView2 updater that can start without a window.

## Evidence and remaining checks

Registry and plan tests confirmed the WiX 4 seed with Trial 11.3.35. Real Suite
11.3.25 runs confirmed the WiX 3 path. A 2026.08.04.1 field capture confirmed
that an 8.3-named Ableton USB agent and then `MicrosoftEdgeUpdate.exe` could
hold the old wait. Scratch-prefix tests confirmed path-based Run and Startup
cleanup and the bounded kill fallback.

Still needed: a licensed Suite 11.3.42 install through the WiX 4 path, another
Suite 11.3.25 run after current cleanup, and identification of the Live 12 Lite
driver task that escaped one recorded Inno install.
