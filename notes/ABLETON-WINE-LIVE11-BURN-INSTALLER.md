# Live 11 installer: the Burn bundle and the USB driver package

Status: fix on branch `fix/live11-installer-parity`. First version
2026-08-05, revised 2026-08-07 after review testing against a real Live 11
Suite 11.3.25 install showed the bundle exists in two generations and the
fix only reaches one of them.

## Symptom

Issue #111 has two forms and one cause:

- A new installation waits after Live installs.
- An update waits at the step `[1/5] initialise prefix`.

The Ableton USB Driver package installs `tusbaudiocplapp.exe`, a Thesycon
control panel program, and an automatic start entry. The program does not
stop by itself. The installer script runs `wineserver -w`, which waits for
all programs in the prefix. The wait continues until the user closes the
program window.

## Installer families

| Live | Technology                                | Unattended flags |
| ---- | ----------------------------------------- | ---------------- |
| 12   | Inno Setup                                | `/SILENT /SUPPRESSMSGBOXES /NORESTART /MERGETASKS=!audiodriver` |
| 11   | WiX Burn bundle, WixStdBA                 | `/passive /norestart` |

Burn reads `/SILENT` as `/quiet` and shows no window at all. `/passive`
shows the progress bar. Burn has no `/MERGETASKS` and no
`/SUPPRESSMSGBOXES`. The installer script identifies the family by file
content: the `.wixburn` PE section identifies Burn, the `Inno Setup` marker
identifies Inno.

## Live 11 ships two bundle generations

The Live 11 bundle is not one thing. Manifests were extracted from the
installer executables on Ableton's download CDN (the zips are public; the
method is range reads for the zip central directory and the exe entry, a
scan for the attached MSCF cabinets, cabextract on the UX cabinet; the
Burn manifest is its first file):

- WiX 3 generation, observed in suite 11.3.25. One MsiProductSearch, for
  the VC redist only. No `InstallAudioDriver` variable. The driver package
  is `Ableton_Push_Audio_Driver.msi` version 5.57.0 with
  `InstallCondition="VersionNT64"` and `Vital="no"`. `Setup.msi` has
  `DisplayInternalUI="yes"`.
- WiX 4 generation, engine 4.0.5.0, observed in trial 11.3.35 and suite
  11.3.42. The wizard checkbox sets the numeric variable
  `InstallAudioDriver`, default 1, not overridable from the command line
  (no variable in the manifest carries an `Overridable` attribute). An
  MsiProductSearch on the driver UpgradeCode
  `{AEFC5C68-0264-4E30-9685-28712A91CF4E}` sets
  `InstalledPush3AudioDriverVersion`. The driver package
  (`Ableton_Push_Audio_Driver.msi` version 5.68.0, `Vital="no"`) has the
  install condition `InstallAudioDriver > 0 And
  InstalledPush3AudioDriverVersion <= v5.68.0` (suite 11.3.42 adds a
  NativeMachine clause). No package sets `DisplayInternalUI`.

The split is the bundle generation, not the edition. The installer script
tells the generations apart by content: WiX 4 engine stubs carry the
`wixtoolset.dutil` build path within the first megabyte of the executable,
the WiX 3 stub has no such string.

Consequences per generation:

- WiX 4: the version guard can be fed, so the placeholder seed works.
  `/passive` is click-free.
- WiX 3: no flag and no seed can skip the driver. The package runs and
  fails with 0x80070643 under Wine; the failure is non-vital and the
  install continues. `/passive` still shows the Live setup wizard, because
  `DisplayInternalUI="yes"` puts the MSI's own UI on top of the bundle UI.
  It behaves the same on Windows.

## The RelatedPackage sweep

Both generations mark the driver package's own UpgradeCode as a
`<RelatedPackage ... OnlyDetect="no"/>`. In the Burn engine
(src/burn/engine/msiengine.cpp in wixtoolset/wix), a related product found
under that code gets `BOOTSTRAPPER_RELATED_OPERATION_MAJOR_UPGRADE`, and
the bundle plans its removal when the owning package installs. The removal
is only planned for a package that executes.

So on the WiX 4 generation the seed survives: the seed at version 99.0.0
makes the install condition false, the package plans Absent with execute
None, and no removal is planned. On the WiX 3 generation the package
always executes, the bundle finds the placeholder under the UpgradeCode
and removes it, and because the placeholder has no real cached package the
removal leaves an orphaned InstallProperties key behind. Observed in
review testing on suite 11.3.25: the seeded UpgradeCodes entries were gone
after the install, the InstallProperties key remained.

This is why the seed is gated on the bundle generation, and why
`setup-prefix.sh` removes any leftover placeholder registration: the
placeholder ProductCode `{B0B57A61-11E0-4A2E-9A11-AB1E70201126}` is
invented by the seed, so removing it is always safe.

## The fix

For a WiX 4 bundle, `setup-run-header.sh` registers the placeholder
product in the prefix registry right before it runs the installer: name
"Ableton Push USB Audio Driver (ableton-linux placeholder)", version
99.0.0, ProductCode `{B0B57A61-11E0-4A2E-9A11-AB1E70201126}`, under the
driver UpgradeCode. The product search then returns 99.0.0, the install
condition becomes false, and the bundle removes the package from its own
plan: `tlsetupfx.exe` does not run, the log records no failure, and the
wizard hides its driver checkbox. The registration writes both
UpgradeCodes paths:

- `HKLM\Software\Microsoft\Windows\CurrentVersion\Installer\UpgradeCodes`.
  Wine's `MsiEnumRelatedProducts` reads this path.
- `HKLM\Software\Classes\Installer\UpgradeCodes`. Windows reads this path.

A Windows USB kernel driver cannot load under Wine and audio is PipeASIO,
so nothing real is lost. Live 12's Inno installer never consults MSI
product state; these keys are inert there.

For a prefix that already has the driver, `setup-prefix.sh` stops
`tusbaudiocplapp.exe` after `wineboot` and deletes its automatic start
entries. Stopping the process is what unblocks the wait; deleting the
entries prevents recurrence. The scrub covers exactly what wineboot's
startup pass runs: the HKLM Run key in both views, the HKCU Run key, and
the Startup folders. The Run-value match is on the value's command line,
not its name. The installer script also stops the program after Live's
installer exits, and it bounds the `wineserver -w` wait to 30 seconds.
After the bound, the script prints which window to close.

## Verification, 2026-08-05

Environment: scratch prefix, runtime `wine-d2d1-nspa-11.13`, the 23 MB
bundle stub of `ableton_live_trial_11.3.35_64.zip`. The plan phase does not
need the payload cabinets.

- Without the seed: `InstalledPush3AudioDriverVersion = 0.0.0.0`, the
  condition evaluates to true, the package plans `Present` with
  `execute: Install`.
- With the seed: `InstalledPush3AudioDriverVersion = 99.0.0`, the
  condition evaluates to false, the package plans `Absent` with
  `execute: None`. The result is equal with `/quiet` and with `/passive`.
- The automatic start scrub was tested against Wine's real `reg query`
  output, with a value name that contains spaces.

## Verification, 2026-08-07

Review testing ran the fix against a real Live 11 Suite 11.3.25 install on
the release runtime, twice, on two runtimes, with identical results. The
suite bundle is the WiX 3 generation: the seed did nothing, the driver
package ran and failed 0x80070643 (non-vital, install continued), the
RelatedPackage sweep removed the seeded UpgradeCodes entries and left an
orphaned InstallProperties key, `/passive` showed the Live setup wizard,
and the tray app's automatic start value survived under HKCU Run because
the scrub only covered HKLM. Working as designed: the `.wixburn` detection
at byte 632, the seed mechanism itself on the WiX 4 bundle, and the
taskkill unblocking `wineserver -w`.

The manifests quoted in this note were extracted from Ableton's CDN on
2026-08-07 for suite 11.3.25, trial 11.3.35, and suite 11.3.42. The
assumption from 2026-08-05 that suite and trial bundles are equal was
wrong for the WiX 3 generation.

Open items:

- Re-test suite 11.3.25 with the gated fix: expect no seed, no sweep, the
  non-vital driver failure as before, clicks required, the tray app
  scrubbed from HKCU Run, and no leftover placeholder keys after an
  update.
- One install of a WiX 4 suite bundle (11.3.42) to confirm the seed path
  on the edition licensees download. Suite 11.3.42 has the guard; the seed
  is verified against trial 11.3.35 only.
