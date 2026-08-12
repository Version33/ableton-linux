# PipeASIO 1.5 v2: build, packaging, and installer record

Date: 2026-08-12

Branch: `moonshot-pipeasio-15-v2`

Working-tree base: `052650024d2b37aa176df25d5df0e018ac8e5a32`

This note records completed build and packaging evidence for the PipeASIO 1.5
redo. It deliberately separates repeatable container and installer checks from
the Live, hardware, distribution, and scheduler tests that still require
release validation.

The installer work uses PR #182 at
`c8c02cc4c2f79d3941bbc707bc006f7c61618305` as its structural baseline:
`scripts/installer.sh` is the public dispatcher, while component scripts remain
internal transaction participants. The older PipeASIO branch installer changes
were not merged mechanically.

## Frozen runtime artifact

The final Jammy container build produced version `2026.08.12.1`.

| artifact or record | SHA-256 |
| --- | --- |
| `dist/wine-d2d1-nspa-11.13-2026.08.12.1.tar.zst` | `03c1f4f0b29b349cb41d69e9ce0cad5aa986486f17dc77d9cd84f764501204c0` |
| `dist/BUILD-INFO-2026.08.12.1.txt` | `ea6653909741622e03fd109cb6b2266b6bbcf09987944385126a97a4a771ec1a` |
| `dist/pipewire-version-probe` | `4ea7a631decb71c0c9dfa562c916efeb82df8b5d7187b06e942f74dbbb63c31f` |
| `dist/ableton-linkd` | `d4afb5b0d91b3389935df74f8d2544c504278c0b502368531ef83280450f1a69` |
| `pipeasio-settings` recorded in BUILD-INFO | `f9ca6e4b846976caab3ca23e6be6563394cd09564383cc4f2117a70935c97455` |
| `dist/ableton-wine-setup-2026.08.12.1.run` | `d8b3e2c112c46eda89614efa703c300daae9fbc55d067449f5137d3c8a0f5e74` |

BUILD-INFO records 90 patches: 81 Wine patches and nine PipeASIO patches. The
frozen patch-stack digest is
`b8ef3ae674307a397edebfd6d4a32506b177a3ee2bdcfdc7fd5d8b97df4ccf43`.
The PipeASIO series and all other entries in `patches/SERIES.sha256` verify.

## Build-path changes

### Upstream CMake and CTest

`scripts/container-build.sh` builds PipeASIO 1.5.0 through upstream CMake. It
no longer recreates the driver and Qt targets with hand-written compiler, moc,
and `pkg-config Qt6Widgets` commands. CMake owns Qt discovery, target flags,
Wine DLL generation, installation, and CTest registration.

The build uses the vendored PipeWire 1.6.2 SDK as a compile-time sysroot. The
installed driver remains a normal host client with `DT_NEEDED` on
`libpipewire-0.3.so.0`; it has no SDK RPATH and does not ship the SDK library.
The final native version probe has only libc and `libpipewire-0.3.so.0` as
needed libraries and also has no RPATH.

CMake installation supplies the canonical driver files and their relative
aliases. The packaging audit requires both aliases to resolve to byte-identical
canonical binaries. The panel, desktop file, and icon are installed as one
optional unit.

### Optional panel contract

BUILD-INFO has one machine-readable panel state:

- `pipeasio-panel: built` requires a 64-hex `pipeasio-settings` digest and all
  three panel files;
- `pipeasio-panel: skipped` permits only `skipped (disabled)` or
  `skipped (Qt6 Widgets unavailable)` and requires all three files to be absent.

Partial payloads, arbitrary skipped reasons, a stale panel accompanying a
skipped record, and digest mismatches are rejected. Production CI requires the
built state. Separate synthetic audits passed for both supported skipped
reasons, and an arbitrary reason was rejected as intended.

### Native PipeWire compatibility probe

`tools/pipewire-version-probe.c` calls `pw_get_library_version()` in its own
loaded process and reads `pw_core_info.version` from the connected daemon. It
has a bounded internal timeout and does not depend on `pw-cli`, `pw-dump`, or
`pw-top`.

The public installer uses this probe before replacing a PipeASIO-bearing
runtime or registering the driver. Both the loaded client and daemon must be
at least 1.4.2. An unavailable, malformed, or older result is a hard refusal
before those mutations. Missing `pw-dump` and `pw-top` affects only optional
diagnostics and does not block installation.

This branch ships neither an isolated matched PipeWire client closure nor a
legacy asynchronous driver variant. Therefore stock Ubuntu 24.04 and Linux
Mint systems still on PipeWire 1.0.5 are refused safely; they are not silently
treated as supported.

### PR #182 installer integration

The public dispatcher provides install, update, runtime, prefix, Link,
uninstall, plan, and the narrow Live 11 post-first-run repair operations. Its
shared configuration resolves CLI values, environment variables, persistent
XDG configuration, and compatibility defaults in that order.

Installer state now includes:

- exact, byte-validated ownership markers for runtime, prefix, and state roots;
- a path-constrained ownership manifest and hashed pre-install file backups;
- complete preflight of journals and transaction backup slots before mutation;
- signal-bounded, same-filesystem runtime and prefix promotion;
- explicit committed-cleanup and incomplete-restoration records;
- one-CLSID PipeASIO registration and verified unregister for retained prefixes;
- versioned runtime rollback with recorded installer and PipeASIO configuration;
- durable `setup-realtime.sh`, `audio-report.sh`, and `rollback.sh` copies under
  the resolved XDG data root;
- ownership-safe installation/removal of the panel command, desktop file, and
  icon, preserving an independently installed command;
- narrow migration of the canonical, provable pre-marker 2026.08.08.1 runtime
  and prefix. Custom or malformed trees are refused.

Rollback and uninstall retain recovery state on partial failure. Tests cover
corrupt, duplicate, NUL-containing, symlinked, misplaced, missing, and
out-of-scope journal data; interrupted promotion; failed restoration;
registration failure; MIME failure; and retry after a partial uninstall.

The final self-extracting installer was built only after the bounded PR #182
audit passed. Its embedded payload hash self-check passed, and an independent
extraction of the exact 118,224,300-byte `.run` reproduced the sealed runtime,
BUILD-INFO, native PipeWire probe, dispatcher, transaction libraries, rollback,
audio-report, and realtime-setup files byte for byte. The extracted runtime
checksum also verified independently.

## Completed automated gates

The frozen Jammy build completed successfully:

- production and no-Qt CMake build/install plus non-integration CTest;
- ASan+UBSan: 11/11;
- TSan native units: 6/6;
- relocation and PipeASIO registration checks;
- production runtime artifact audit: 142/142;
- independent second audit of the exact tarball: 142/142;
- both supported driver-only/skipped-panel synthetic audits: 134/134;
- native probe stub, sanitizer, ELF dependency, RPATH, and live-host checks.

On the patched source tree, the full CMake/CTest pass was 19/19, with nine
live-graph probes skipped by their environment gate. A separate sanitizer run
passed 17/17 ASan+UBSan-labelled tests and 6/6 TSan native units. The optional
WoW64 Unix half passed a target-equivalent syntax compile; a complete 32-bit
link was not run because the i686 MinGW compiler is unavailable, and production
remains explicitly 64-bit-only.

The PR #182-based repository lifecycle gate passed 158/158:

- 45 shortcut-hold checks;
- 29 dispatcher and installer-lifecycle checks;
- 84 focused PipeASIO, transaction, rollback, migration, and uninstall checks.

The focused set includes deterministic replacements on both sides of the
historical PR #182 custom-Link capture. A user replacement is preserved and
de-owned before capture; a replacement after capture is preserved with a
durable conflict that blocks both commit and rollback until inspected. The
bounded final audit found no remaining blocker in that lifecycle boundary.

All changed scripts pass Bash syntax checking. Scoped ShellCheck passes with
the repository's documented dynamic-source and intentional-expression
exclusions. `git diff --check` is clean.

### Isolated Live 12 smoke test

An interactive Live 12 Suite 12.4.3 smoke test used the exact final runtime
from the sealed tarball without replacing the installed PipeASIO 1.2.2
runtime. The existing Live prefix and a copied two-input/two-output,
256-frame configuration were used with `ABLETON_RT=on` and
`PIPEASIO_REALTIME=off`; Link, power-profile, shortcut, theme, DPI, top-bar,
and font mutations were disabled for the isolated launch.

The native probe reported client 1.6.8 and daemon 1.6.8. PipeWire showed the
Live node running at `256/48000`, with `node.force-quantum=256` and `ERR=0`.
PipeASIO reported two missed cycles during activation and no later xrun,
quantum-mismatch, reset, sample-rate, or failure diagnostics. Live exited
normally; its PipeWire node and all users of the temporary runtime disappeared.
This is one launch/playback interaction, not the complete Live 12 matrix, and
does not close the Hardware Setup, repeated reselect, device, rate, suspend,
hotplug, or scheduler-combination gates below.

## Still-open release validation

The completed checks do not establish a release support claim. The following
remain open:

- Live 11 and Live 12 with the exact final artifact, including Hardware Setup
  during playback, repeated open/close, driver reselect, missing Qt/QPA, X11,
  and Wayland;
- the complete 14-size by six-rate bit-exact matrix on real hardware;
- dynamic global and JACK quantum `0 -> Q -> 0`, invalid values, and hosts that
  accept or ignore reset requests;
- same-device duplex, two independent hardware clocks, physical alignment,
  hotplug, suspend/resume, reconnect, and daemon failure;
- all four `ABLETON_RT` by `PIPEASIO_REALTIME` combinations on a low-core and a
  larger machine, with per-thread scheduling and CPU/xrun measurements;
- Debian 13 at the 1.4.2 floor, safe 1.0.5 refusal on Ubuntu/Mint, Fedora and
  Arch current, missing Qt, rollback, and uninstall;
- Live MIDI hardware and a real 49.7-day `timeGetTime()` rollover observation.

PipeASIO 1.5 is not yet confirmed with Ableton Live upstream. This branch does
not claim that 1.5 lowers CPU use, survives arbitrary CPU starvation or device
removal without interruption, or has completed the real-hardware matrix.
