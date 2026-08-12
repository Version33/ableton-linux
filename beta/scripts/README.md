# Environment profilers

These scripts print redacted system information for bug reports:

- `ableton-linux-profiler.sh`
- `ableton-macos-profiler.sh`
- `ableton-windows-profiler.ps1`

The scripts copy the report when a supported clipboard tool is available.
Read the output before sharing it.

The Linux report covers the distribution, kernel, processor, memory, graphics,
desktop session, PipeWire, WirePlumber, audio and MIDI devices, installed
project files, desktop handlers, prefix state, and optional library access.
The macOS and Windows reports collect the equivalent operating-system,
hardware, device, and Live version details.

## Data removed from reports

The profilers replace the configured home path and native account name. They
also remove or replace common serial numbers, UUIDs, GUIDs, MAC addresses,
email addresses, mount points, tokens, passwords, API keys, Ableton licence
values, and other credential-like fields.

The Linux collector also replaces `/run/user/<uid>` and LUKS UUIDs. The macOS
collector removes BSD device names. The tester kit removes captured window
titles.

Redaction cannot recognise every private value. If a report contains one,
keep it local and report the collector failure.

## Check profiler privacy

Run this after changing a profiler or collector:

```bash
./beta/scripts/check-profiler-privacy.sh
```

The check rejects forbidden collection patterns, missing redaction rules, and
private values in its fixture output.
