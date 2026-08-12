# Idle CPU use and the `-DontCombineAPCs` test

Release 2026.07.18.1 added `-DontCombineAPCs` after an idle Live thread was
reported at 30 to 40 per cent of one core. The option caused choppy, slowed
playback. Removing it resolved issue 29 on the reporting system, and restoring
it reproduced the failure. Release 2026.07.19.1 removed the option and prefix
setup removes it from existing `Options.txt` files.

The original note interpreted APC as Windows asynchronous procedure calls and
proposed a Wine queueing change. Ableton's option documentation instead uses
APC for Akai APC controllers: the setting controls whether Live combines APC20
and APC40 devices. The Wine APC proposal therefore had no established link to
the measured thread or playback failure and should not be implemented from
this evidence.

## What remains known

- Live's default setting produced working playback in the reported comparison.
- `-DontCombineAPCs` reproduced the playback fault.
- The idle CPU observation did not identify the busy thread's call path.

Any further CPU investigation must profile the process and compare the same
Set, audio device, buffer, scheduling mode, and CPU allocation. Record PipeWire
xruns as well as process and thread CPU use. Do not infer a Wine APC defect from
the option name.
