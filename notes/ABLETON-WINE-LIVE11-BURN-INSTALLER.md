# Live 11 installer: the Burn bundle and the USB driver package

Status: fix committed on branch `fix/live11-installer-parity`, 2026-08-05.
The fix is verified against the Live 11.3.35 trial bundle in a scratch
prefix. A full installation test with the complete payload is open.

## Symptom

Issue #111 has two forms and one cause:

- A new installation waits after Live installs.
- An update waits at the step `[1/5] initialise prefix`.

The Ableton USB Driver package installs `tusbaudiocplapp.exe`, a Thesycon
control panel program, and an automatic start value under
`HKLM\Software\Microsoft\Windows\CurrentVersion\Run`. The program does not
stop by itself. The installer script runs `wineserver -w`, which waits for
all programs in the prefix. The wait continues until the user closes the
program window.

## Installer families

| Live | Technology                                | Unattended flags |
| ---- | ----------------------------------------- | ---------------- |
| 12   | Inno Setup                                | `/SILENT /SUPPRESSMSGBOXES /NORESTART /MERGETASKS=!audiodriver` |
| 11   | WiX Burn bundle, engine 4.0.5.0, WixStdBA | `/passive /norestart` |

Burn reads `/SILENT` as `/quiet` and shows no window at all. `/passive`
shows the progress bar and no wizard. Burn has no `/MERGETASKS` and no
`/SUPPRESSMSGBOXES`. The installer script identifies the family by file
content: the `.wixburn` PE section identifies Burn, the `Inno Setup` marker
identifies Inno.

## A flag cannot skip the driver on Live 11

These facts come from the bundle manifest. The manifest was extracted on
2026-08-05 from `ableton_live_trial_11.3.35_64.zip` on Ableton's download
CDN:

- The wizard checkbox sets the numeric variable `InstallAudioDriver`,
  default `1`.
- The variable is not overridable from the command line. The bundle's only
  overridable variable is `BypassProcessorCheck`.
- The driver package `Push3AudioDriver` (`Ableton_Push_Audio_Driver.msi`,
  version 5.68.0, `Vital="no"`) has this install condition:
  `VersionNT64 And InstallAudioDriver > 0 And
  InstalledPush3AudioDriverVersion <= v5.68.0`.
- An `MsiProductSearch` on the driver UpgradeCode
  `{AEFC5C68-0264-4E30-9685-28712A91CF4E}` sets
  `InstalledPush3AudioDriverVersion`.

A command line option therefore cannot turn the driver off. The version
guard in the install condition can.

## The fix

`setup-prefix.sh` registers a placeholder product in the prefix registry:
name "Ableton Push USB Audio Driver (ableton-linux placeholder)", version
99.0.0, ProductCode `{B0B57A61-11E0-4A2E-9A11-AB1E70201126}`, under the
driver UpgradeCode. The product search then returns 99.0.0. The install
condition becomes false. The bundle removes the package from its own plan:
`tlsetupfx.exe` does not run, the log records no failure, and the wizard
hides the driver checkbox. The checkbox shows only at version 0.0.0.0.

The registration writes both UpgradeCodes paths:

- `HKLM\Software\Microsoft\Windows\CurrentVersion\Installer\UpgradeCodes`.
  Wine's `MsiEnumRelatedProducts` reads this path.
- `HKLM\Software\Classes\Installer\UpgradeCodes`. Windows reads this path.

For a prefix that already has the driver, `setup-prefix.sh` stops
`tusbaudiocplapp.exe` after `wineboot` and deletes its automatic start
value. The scrub matches the value by its command line, not by its name.
The installer script also stops the program after Live's installer exits,
and it bounds the `wineserver -w` wait to 30 seconds. After the bound, the
script prints which window to close.

## Verification, 2026-08-05

Environment: scratch prefix, runtime `wine-d2d1-nspa-11.13`, the 23 MB
bundle stub of `ableton_live_trial_11.3.35_64.zip`. The plan phase does not
need the payload cabinets.

- Without the seed: `InstalledPush3AudioDriverVersion = 0.0.0.0`, the
  condition evaluates to true, the package plans `Present` with
  `execute: Install`.
- With the seed: `InstalledPush3AudioDriverVersion = 99.0.0`, the condition
  evaluates to false, the package plans `Absent` with `execute: None`. The
  result is equal with `/quiet` and with `/passive`.
- The automatic start scrub was tested against Wine's real `reg query`
  output, with a value name that contains spaces.

Open items:

- A full Live 11 installation with the payload cabinets present.
- The suite bundle is assumed equal to the trial bundle. The suite install
  log from the PR 130 tests names the same driver MSI and the same version.
