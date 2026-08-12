# Max for Live waits forever after a font miss, 2026-07-29

Some Max for Live devices left Live black and unresponsive while audio kept
playing. Carbon Regulator and Stabbed Bass shared no Max device, but both
reached the same MaxPlug condition-variable wait after requesting a font the
prefix could not resolve.

## Missing final fallback

Devices authored on macOS requested faces such as Geneva, Menlo, Lucida
Grande, Helvetica Neue, and Consolas. MaxPlug then tried its own final chain:

```text
Bitstream Vera Serif
Bitstream Vera Sans Mono
Bitstream Vera Sans
```

Modern distributions generally ship DejaVu instead. When both the requested
face and Bitstream Vera were absent, MaxPlug parked Live's UI thread and never
signalled it. Installing and registering Bitstream Vera let the lookup finish
even though the original face remained unavailable.

Paired stack captures placed the UI thread in
`RtlSleepConditionVariableCS` at the same MaxPlug offset. Two samples ten
seconds apart showed no CPU progress on that thread while audio workers
continued. The two racks diverged above the common font-resolution frames,
which ruled out their individual devices as the shared cause.

## Prefix setup

`setup-prefix.sh` installs the unmodified Bitstream Vera files from
`vendor/fonts/bitstream-vera/`, ships their licence, and registers each face in
the Wine font registry. Copying files alone did not work because the existing
prefix font list had already been saved.

`scripts/check-m4l-fonts.sh` verifies the files, licence, family names,
packaging, registration, MaxPlug fallback strings, and resolution.
`tools/fontprobe.c` checks enumeration through the same GDI family API. The
M4L font audit combines that result with Max's private bundled fonts.

Registry `FontSubstitutes` did not help because Max enumerates families rather
than relying on `CreateFontIndirect` substitution. Pointing a fake family
registry value at another font also failed because Wine reads the family name
from the font file.

## Remaining limitation

Affected devices use Bitstream Vera instead of their intended macOS face. The
original fonts cannot be redistributed here. The underlying Max behaviour,
waiting forever after its own fallback chain fails, remains in Max. The project
removes the known trigger and checks that the final families stay available.

Regenerate private stack and CPU captures with
`tools/m4l-hang-capture.sh`. Do not run prefix setup while Live is open because
the setup wait requires all Wine processes to exit.
