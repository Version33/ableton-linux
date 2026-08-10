# PipeASIO 1.5 redo: research findings, 2026-08-10

Branch `moonshot-pipeasio-15-v2`, cut from origin/main at 3e7bbf1. This note records the
research pass behind the redo of PR #160 (branch `moonshot-pipeasio-15`, head b975e81),
after the request-changes review of 2026-08-10. Nothing here is committed or published.

Sources: the review itself; the pipeasio-15, moonshot-multi-audio-device-hardening,
moonshot-cpu-idle, performance-moonshot-combined and moonshot-bench-projects worktrees;
full threads of issues 49, 48, 60, 63, 9, 19, 29, 109, 126, 149, 150, 154, 164 and
PRs 160/118; CI run 31287663024; the six crash report zips and the Discord crash-reports
DM in ~/Downloads; upstream PipeASIO 1.5.0 source; PipeWire source and documentation;
Wine 11.15 source.

## 1. Where the work stands

Nothing from the moonshot audio or CPU series is on main. `origin/main` carries pipeasio
patches 0001 and 0002 only; `patches/performance/` does not exist there. Everything else
sits under the open umbrella PR #118 (`performance-moonshot`), with PR #160 based on that
branch, not on main. The redo therefore starts clean and chooses what to carry.

PR #160 contents: vendor bump 1.2.2 to 1.5.0 (tag tarball), six-patch series re-ported
(0003 retired into 0005, 0004 extended for a new CreateBuffers pow2 gate), pipeasio-settings
panel bundled (issue 60), floor raised to 1.4.2 in some files. Its own driver-level numbers
(notes/ABLETON-WINE-PIPEASIO.md on that branch): round trip halved to exactly 1.00 buffer
period at 128/192/256/512/883 (1.2.2 measures 2.00), zero discontinuities in loopback,
CPU within noise of 1.2.2 (loopback process 0.4% vs 0.3%, pipewire 1.8% both). The latency
gain is real and upstream (1.4.3 clears node.async after connect). The CPU gain does not
exist. Any release claim must say latency, not CPU.

## 2. What users actually hit

Four distinct mechanisms, one packaging failure.

**A. Quantum mismatch, wrong-speed playback (issue 49, root-caused).** Global
clock.force-quantum wins absolutely; otherwise last-changed node.force-quantum wins by
monotonic stamp. On losing, 1.2.2 kept calling bufferSwitch host-sized at the foreign
cadence: at graph 192 vs host 256 the transport runs 1.333x fast; at 1024, 5.33x (the
35 s clip in 8 s video). Fixed in class by 0004+0005, but 0005 as written has the
correctness faults in section 3.

**B. Residual crackle on capable hardware (issue 49, yioannides).** Fedora, 8C/16T
desktop, MOTU M2, rtprio 99, no RT throttling. Crackle survives buffer changes, the
PulseAudio backend and a runtime rollback. Diagnostic line is a follower resync:
`spa.alsa: hw:M2p: follower avail:125 delay:125 target:384 thr:256, resync`. This is the
C8 follower-headroom class from the crackle note. Patch 0007 targets it but its mechanism
does not work mid-stream (section 4, headroom). Bitwig at 192 is clean on the same box,
so Windows-parity is achievable there.

**C. Per-core CPU starvation on small machines (issues 164, 49/Rob-goblin).** ULV laptops
(i7-8650U 4C/8T, ULV Ryzen): Live's CPU meter pegs and audio crackles while the system
monitor stays under 100%; "wine only using like two cores". ABLETON_RT=off and larger
buffers reduce it (headroom masks, both reporters), CachyOS reinstall cured one entirely.
Mechanisms per the crackle note: C3 (Live's DSP workers get only niceness from Wine, the
realtime band is clamped in server/thread.c), C4 (the whole process inherits the launcher's
SCHED_RR 10, so 126 threads share one RT priority), C6 (no ntsync). PipeASIO 1.5 adds
measurement here, not capacity. The CPU work lives in P2/P4/P5/P13, not in this driver bump.

**D. PipeWire 1.0.5 hosts, Ubuntu 24.04 and Mint 22.x (issues 150, 149).** Two separable
faults on slizzul's Latitude 5400:
- A driver lifecycle crash: two of the six crash zips end in EXCEPTION_ACCESS_VIOLATION
  inside PipeASIO Open and Close while switching driver type. 81.0x19 reproduced the
  crash class by removing pipeasio patches 0001+0002, and found PipeASIO >= 1.4 "seems to
  fix the driver type change crash". The 1.5 lifecycle rework is plausibly the fix; needs
  a 1.0.5 regression run to confirm.
- A server-side crackle that persists after the crash is gone ("vm still crackles").
  trendwhore traced it to Mint's PipeWire predating upstream commit 338e32e5. No client
  change can fix a daemon-side xrun recovery fault.
The other three zips from that machine are a freeze/crash loop loading old projects off
NTFS, Vital VST3 the only captured suspect. Those belong to 149/154, not to the driver.

**E. Packaging (issue 60, CI).** The settings panel never shipped, and the PR #160 attempt
fails CI: the container base is an Ubuntu jammy snapshot whose Qt 6.2.4 packaging ships no
pkg-config .pc files at all (Qt6 gained them in 6.3), so `pkg-config Qt6Widgets` returns
nothing, the failed substitution does not abort under set -e, and g++ runs with no Qt
include flags. First error: `gui/Config.hpp:27: fatal error: QString`. Installing more
jammy Qt packages cannot help; discovery must go through CMake (jammy Qt 6.2.4 does ship
CMake config) or qmake6, or the base image moves.

Also cross-cutting: the installer never runs setup-realtime.sh. slizzul's Mint box and the
Fedora 43 linkd-report machine both show `ulimit -r 0`. Much of the fleet likely runs with
no RT grant at all, which feeds mechanism C and invalidates any scheduling conclusion drawn
from the build machine (rtprio 99, ntsync, CachyOS).

Crash-report triage lesson, recorded once: the .dmp files inside Ableton report zips are
startup artifacts, one per launch, written one second after session start even for clean
exits. Crash evidence is the "Detected a prior crash" marker plus log truncation. The
2026-08-01 zip is a different machine and is the (expired-link) issue 115 evidence: a
reproducible M4L Convolution Reverb insert crash on a pre-2026.08.01.1 runtime that is
also stuck in the issue-84 HD 4000 GDI fallback.

## 3. Review verdict: all ten blockers confirmed, four refined

Verified against the pipeasio-15 worktree with all six patches applied cleanly to the
vendored 1.5.0 tree. Line references are into the patched tree unless noted.

| # | Verdict | Detail |
|---|---------|--------|
| B1 CI/Qt | Confirmed | No cmake/ctest anywhere in the build scripts. Reproduced the empty pkg-config locally against jammy qt6-base-dev 6.2.4. |
| B2 align | Confirmed, attribution corrected | `SPA_PARAM_BUFFERS_align = bsize_bytes` is upstream 1.5.0 code (src/audio.c:790). The series' fault is removing the pow2 validation that kept it unreachable. Even pow2 sizes request up to 32 KiB alignment. PipeWire's allocator does pure bitmask math and validates nothing; stock clients omit align entirely. |
| B3 GUI | Confirmed, worse | Non-pow2 config is not rewritten to 1024, it is discarded to the default; the size combo then displays it as 16 (fallback index 0, a value below the driver's own floor). No patch touches gui/. container-build.sh's claim that the panel shares the driver's config code is false for reading: the panel parses with its own C++ parseIni carrying the old pow2 gate. |
| B4 adoption | Confirmed, plus one | quantum_adopted never cleared; last_reset_quantum committed before the host accepts the reset, blocking retry; invalid global values (0..INT_MAX accepted at parse) advertised before CreateBuffers rejects them. Additional fault: in pure host-controlled mode the adopted quantum is read by nothing, so a host that honours kAsioResetRequest rebuilds at the old preferred size, mismatches again, and the retry gate then blocks re-adoption permanently. |
| B5 case fold | Confirmed | PE side lstrcmpiA vs backend strcmp, under a comment saying both halves must agree. Same bug class found and fixed in PR #118 review (r3705281957); the fix needs `#include <strings.h>` or the unix side fails on -Werror=implicit-function-declaration. |
| B6 mute workload | Confirmed | Backend invokes the host callback with c->buffer_size once per graph cycle: Live at 512 on a 128 graph runs 375 host-sized bufferSwitch/s, about 4x DSP. No buffer overflow behind it; the offsets math is host-sized throughout. |
| B7 scheduler | Confirmed | Launcher runs `chrt -r 10 wine`; glibc pthread_create defaults to PTHREAD_INHERIT_SCHED and Wine sets no inherit attribute, so every CreateThread'd thread, the PipeWire data loop included, arrives at SCHED_RR 10. audio_rt_acquire with realtime=false logs "left SCHED_OTHER" and returns without touching policy; audio_rt_drop also skips when rt_priority is unset. Upstream's shipped default therefore cannot take effect under the production launcher, and its log line is false there. |
| B8 headroom | Confirmed, two claims narrowed | It raises to 512 (not adds), only when current < target. The cross-thread channel is a deliberate seqlock, but the guarded buffer is plain memory and the reader lacks an acquire fence: still a formal C11 data race, narrower fix than "no atomics". Blind restore, ignored set_param result, unconditional success logging, crash residue: all confirmed. |
| B9 capture anchor | Confirmed | Input endpoints resolve first, against default_sink_name or lowest-id playback node; the configured output_device is consulted only in the later output call. Explicit USB output plus unset input anchors capture to the onboard card and the warning then names the wrong card. |
| B10 gating | Confirmed, plus | Preflight greps the soname only, warns, proceeds to regsvr32. The floor is self-contradictory inside the one branch: container-build.sh says 1.4.2, setup-prefix.sh:583 and setup-run-header.sh:277 still say 0.3.56. uninstall.sh and the install rollback orphan the panel symlink, desktop entry and icon. |

The patched-tree test break is exact: upstream tests/unit/test_config.c:134-141 expects
buffer_size=1000 to fall back to 1024; patch 0004 makes 1000 valid. The repo never runs
CTest so CI never sees it. The redo rewrites that test to the new contract and runs the
suite.

## 4. Upstream facts that shape the redo

**Buffers align.** SPA_ROUND_UP_N and SPA_PTR_ALIGN are bitmask arithmetic, silently wrong
for non-pow2 align. pw_filter's own default buffers pod does not set align; the context
default is the SIMD max-align (>= 16, MemFd raised to page size). Correct form for us:
omit align, or pass a small fixed pow2 (16). Never derive it from the buffer size.

**ASIO granularity.** Per the SDK: granularity -1 means pow2 steps between min and max;
0 means min=max; positive means arithmetic steps of that many frames. A driver accepting
any in-range size should advertise granularity 1 (min 32, max 8192), not -1. The fixed
and follower branches keep granularity 0.

**Quantum arbitration (verified in module-scheduler-v1.c).** Global clock.force-quantum
metadata overrides everything and skips clamping to min/max. Otherwise the newest-stamped
node.force-quantum wins, skips pow2 rounding, and disables lock; the stamp advances only
on a value change, so re-writing the same value does nothing. node.latency is a suggestion:
smallest wins, clamped, then rounded down to pow2 by default. There is no rate matching for
a quantum mismatch on a filter: the process callback simply runs at the graph cadence. The
driver must read the graph's effective quantum (clock.duration), not the raw metadata
string, before advertising anything to the host; PipeWire clamps forced values to
clock.quantum-limit, so metadata and reality can disagree.

**api.alsa.headroom (verified in alsa-pcm.c).** Meaning: extra ringbuffer space for
devices whose pointers are inaccurate. A live Props set_param lands in default_headroom
only; the active headroom is recomputed only in spa_alsa_set_format and setup_matching
(format negotiation, driver reassignment). So 0007's mid-playback write does nothing until
the next renegotiation, while logging success. If follower headroom stays in the series at
all, the write must happen before stream start or force a renegotiation, and the honest
long-term shape is a documented WirePlumber rule plus latency reporting, not a live
mutation of a node the driver does not own.

**Version floors.** PipeASIO's 1.4.2 floor is a build-time pkg-config check; the API
anchor named in its changelog, spa_json_str_object_find, is a header-inline helper and
compiles into the binary. Whether the built driver actually imports any post-1.0.5
runtime symbol is unverified: run `nm -D` on the built .so before deciding the Mint
strategy. The native protocol is version 3 across 0.3 to 1.x, so a newer client library
connects to a 1.0.5 daemon; but quantum choice, async links and sync groups are daemon
side, so bundling a client closure does not buy 1.4 scheduling on a 1.0.5 daemon. Async
scheduling itself only exists from 1.2.0; on a 1.0.5 daemon, filter connect sets neither
node.loop.class nor node.async and the 1.4.3 one-period mechanism is not expressible.
Consequence: on Ubuntu 24.04/Mint the two honest options are (a) refuse before
registration with a clear message and keep 2026.08.04.1-era behaviour, or (b) a
daemon-version-aware degraded mode with the latency claim withdrawn. Testing against the
real 1.0.5 daemon decides whether (b) is safe; the lifecycle-crash fix makes some 1.5
uptake desirable there if it is.

**Runtime probes.** pw_get_library_version() gives the loaded client library;
pw_core_info.version gives the daemon. Probe both: in the driver at init (log, gate
behaviour) and in setup-prefix before regsvr32 (refuse or warn per policy). The soname
grep goes away.

**Distro matrix (checked 2026-08-10).** Ubuntu 24.04 LTS and Mint 22.x: 1.0.5, no
backport exists in noble-backports. Debian 13: 1.4.2. Fedora 43: 1.4.11; Fedora 44:
1.6.8. Arch: 1.6.8. Ubuntu 26.04 LTS: 1.6.2. The only supported mainstream distros below
the floor are exactly the biggest LTS install base.

**Wine scheduling.** Stock Wine applies NT thread priorities from the wineserver as
niceness only, gated on CAP_SYS_NICE or RLIMIT_NICE for the wineserver process;
realtime-band priorities are explicitly clamped below LOW_REALTIME_PRIORITY
(server/thread.c, the FIXME). THREAD_PRIORITY_TIME_CRITICAL never yields SCHED_FIFO/RR.
Policy reaching Live's threads today comes from launcher inheritance, which is exactly
the B7 collision. The P2 A/B stands: RR 10 default gave 0 xruns vs 242 with RT off on a
4-core cage, at a cost of about 6x startup time there, mechanism unproven. Any change to
the launcher policy or to audio_rt_acquire must re-run that A/B with the 1.5 driver
before shipping.

**timeGetTime (patch 0002's clock).** Wine implements it on QPC over CLOCK_BOOTTIME:
epoch is host boot including suspend, truncated to 32 bits, wrapping every 49.71 days of
host uptime regardless of when Live launched. The MIDI timestamp path must tolerate one
wrap (delta arithmetic in 32-bit space) or the note stream dies on long-uptime machines.

**ASIO registration.** Registration is HKLM\Software\ASIO plus the COM CLSID, written by
regsvr32 in the prefix; upstream's README claim of HKCU is wrong, its code writes HKLM.
Two driver variants must never be registered under one CLSID simultaneously; variant
selection has to be atomic before launch.

## 5. Redo plan

Order of work. Fixes and tests first, optimisation claims separated, no publication steps.

**R1. Packaging that CI can build.** Build the driver and panel through upstream CMake,
run CTest in the container, keep the panel optional (no Qt: skip cleanly, keep INI editing
documented). Preflight pw-dump/pw-top where audio-report needs them. Fix uninstall and
rollback to remove the symlink, desktop entry, icon. Unify every floor string.

**R2. Patch series correctness (0004/0005 rewrite).**
- 0004: range check only, all three former pow2 sites; align fixed small pow2 or omitted;
  granularity 1 in the host-controlled branch; rewrite test_config's validation group to
  the new contract; add a unit test for the INI round trip at 883/960/1000.
- 0005: clear quantum_adopted on Stop/DisposeBuffers and forcer departure; commit
  last_reset_quantum only when the host's rebuild arrives; validate any advertised
  quantum with pipeasio_buffer_size_supported and against the graph's effective quantum;
  make the host-controlled branch of GetBufferSize return the adopted quantum so a
  honoured reset actually converges; one case-insensitive env parse helper used by both
  halves (with strings.h); bound the muted state, and account frames during mute so the
  host callback does not run at a multiplied cadence.
- 0006: resolve the configured output device before anchoring capture; correct the
  warning text.
- 0007: out of the series. Fold what it wanted into documentation plus latency reporting;
  revisit as a pre-start or renegotiation-time mechanism only with a real two-clock rig
  to verify on.
- 0002: keep; make the timestamp delta wrap-safe.
- GUI: port the new buffer contract into the panel (parse, validate, display arbitrary
  sizes; drop 16 from the combo) as a patch upstream would take.

**R3. Version gating.** Driver-side probe of library and daemon versions at init;
setup-side probe before regsvr32 with refusal on unsupported daemons per the decided
policy; `nm -D` audit of the built driver to establish the true runtime symbol floor
before writing the Mint story; a 1.0.5 VM run (81.0x19 has the VM) to test whether the
lifecycle-crash fix stands alone in a degraded mode.

**R4. Scheduling coherence (the actual CPU thread).** Decide the launcher-vs-driver
policy: either audio_rt_acquire demotes to SCHED_OTHER when realtime=false so upstream's
default is real, or the launcher stops blanket-inheriting RR into every thread and the
driver owns its data-loop priority. Re-run the P2 A/B on the 4-core cage with the 1.5
driver for whichever arm changes. Keep the C3/P4 priority-chain work and the P5/P13 idle
patches out of this branch's claims; they are where the CPU numbers will actually come
from. The installer's missing setup-realtime.sh run is a separate fix worth its own
small change.

**R5. Verification matrix before any release claim.** Loopback bit-exactness at 32, 64,
128, 192, 256, 512, 882, 883, 960, 1025, 1536, 5000, 8191, 8192 across the six rates;
quantum-change exercises (global pin before launch, mid-run change, invalid values,
ignored reset); ASan/UBSan/TSan builds of the driver; the ABLETON_RT x realtime 2x2 on
the 4-core cage with per-thread policy and pw-top columns recorded; Live 11 and 12; the
three-distro matrix (CachyOS build machine, Fedora stock rtkit, Ubuntu/Mint 1.0.5) plus
Debian 13 at the floor; the 150 driver-type-switch crash regression on the 1.0.5 VM;
Push 2/hardware MIDI timestamp check for 0002; uninstall and rollback runs. The bench
harness rows (bench-run.sh schema) capture the CPU side; a listening pass on the real
rig closes it.

## 6. Execution addendum, 2026-08-10 (same day, later)

R1 through R3 are implemented in this worktree, uncommitted. Companion records:
PIPEASIO-15-V2-SERIES-VERIFICATION.md (driver series), PIPEASIO-15-V2-BUILD-CHANGES.md
(container/audit/install), PIPEASIO-15-V2-SETUP-DOCS-CHANGES.md (setup probe, docs).

Series shipped as 0001, 0002 (wrap-safe), 0004 (range-only, align 16, granularity 1,
test_config rewritten), 0005 (state machine redesign, shared env parser, mute cadence
accounting), 0006 (playback-first ordering), 0008 (version log plus pre-1.2-daemon
pow2 envelope), 0009 (honest realtime toggle, default unchanged), 0010 (panel
contract). Gaps 0003 and 0007 documented in build-audit. SERIES.sha256 refrozen,
89 patches. Fingerprints reconciled, PIPEASIO_MARKER_TODO emptied; 0010's binary
fingerprint is the tooltip literal (wide), its source marker being a comment.

Verified on this host: series applies fuzz-free and byte-identical via patch and
git am; upstream CMake Release build, zero warnings; ctest 14 of 14; unit tests
clean under ASan and UBSan; asio_probe and asio_loopback PASS at 256 and 883, RTL
1.00 periods, zero discontinuities or bit errors; panel test_panel 173 checks green.
nm audit: 37 undefined pw_* symbols, all present in 1.0.5, zero spa_*; the 1.4.2
floor is build-time only, which is what makes the single-driver distro policy work.
Container build itself not run from here (builder-only); the migrated script was
dry-run end to end on the host, including the ctest gate and the audit's new paths.

Live verification runs, same evening, on the real session PipeWire (1.6.8, quantum
512, no force-quantum set; restored after every exercise):
- Rebuild from the worktree files: clean apply, CMake build, ctest 18 of 18 (the
  four wine+PipeWire integration tests then run manually against a scratch install
  root and throwaway prefix).
- Loopback matrix, 14 sizes (32..8192 including 882/883/960/1025/1536/5000/8191):
  12 of 14 pass bit-exact at RTL exactly 1.00 cycles. 32 and 64 each dropped one
  cycle unprivileged (0.67/1.33 ms deadlines, data loop SCHED_OTHER); the 1.5 xrun
  diagnostic named the miss, the dropped cycle was zero-filled, no discontinuity.
  With PIPEASIO_REALTIME=on (patch 0009's override) both pass clean: 14 of 14.
- Quantum exercises against a reset-ignoring host at size 512: force 128 mid-run
  gives one warning and mutes at ~94 callbacks/s (the 4x cadence bug is gone);
  clearing the force recovers bit-clean, twice; force 7 runs the graph at 7, the
  driver never advertises it, mutes, recovers. No wedge, no crash.
- Case-fold: PIPEASIO_ALLOW_QUANTUM_MISMATCH=ON and =on behave identically (zero
  mute warnings, one play-on line each). The permanent-silence split is dead.
- Inherited RR: the probe's scheduling-topology default leg run under chrt -r 10
  passes, callback and worker threads both at policy 0 (SCHED_OTHER), pw-top ERR
  +0. 0009's demotion works in the launcher scenario.

Listening-pass staging: hardlink clone of the production runtime at
~/.local/opt/wine-d2d1-nspa-11.13-pipeasio15-v2 with the new driver pair swapped
in under both names; production runtime untouched; launch via ABLETON_WINE_ROOT.
This staged driver is a host-local build, not the container artifact; the shipping
binary still comes from the container build and audit.

Listening pass, first run: audio confirmed working. Two findings.
1. The panel was not staged in the first clone (driver only), so the settings
   button had nothing to launch. Fixed: pipeasio-settings copied into the clone
   and symlinked onto ~/.local/bin.
2. A "serious program error" (EXCEPTION_ACCESS_VIOLATION) on exit. Root cause,
   from Log.txt and the usage report: Live services ASIO ControlPanel() on its
   GUI thread and does not drain its internal engine->GUI queue until the call
   returns. The upstream 1.5.0 handler (also present in the shipped 1.2.2 driver,
   so this is a pre-existing latent defect, not a redo regression) opens a modal
   MessageBox there. The box stayed open 85 s while the transport played; Live's
   KStandardQueue overflowed at 79,161 messages (65,758 PerNoteControllerChange)
   and it aborted. New patch 0011 hands the informational dialog to a detached
   thread and returns at once, so the host GUI thread is never blocked. Rebuilt,
   full series applies clean, ctest 18 of 18, marker present in the binary,
   SERIES.sha256 refrozen to 90, build-audit fingerprint added. Restaged.
3. Follow-up: with the crash fixed, the Hardware Setup button only showed the
   "run pipeasio-settings from a terminal" hint, a needless gate now that the
   panel is installed. Patch 0011 extended (still one patch): the detached
   thread resolves pipeasio-settings on PATH (the launcher puts the runtime bin
   on PATH, where the panel installs) and launches it with posix_spawn plus
   POSIX_SPAWN_SETSID, so the button opens the panel directly; the hint box
   remains only as the fallback when the panel is not installed. posix_spawn,
   not fork/exec, because it does not run pthread_atfork handlers inside Wine's
   many-threaded process. Guarded to the non-WoW64 build (the 32-bit PE build
   keeps the hint). Verified: clean build, ctest 18 of 18, and a standalone
   harness confirmed the PATH-walk plus posix_spawn(SETSID) launches a target
   in its own session on this glibc. SERIES refrozen (0011 hash changed, still
   90). This is the proper issue 60 resolution: the button works.

Still gated, unchanged from section 5: the P2 A/B re-run before any realtime or
launcher default changes; the 1.0.5 VM matrix including the issue 150 driver-switch
crash regression; the two-clock rig before any headroom mechanism returns; the Live
listening pass (staged, awaiting ears) and bench rows on the production stack; the
container build and audit on the builder.

## 7. Open questions carried forward

- G2: does Live raise its audio worker threads' NT priorities (decides how much C3/P4 buy).
- G3: what pins yioannides's graph to 192 (pipewire-jack writes force-quantum when
  jack.global-buffer-size is set; unconfirmed on his box).
- Whether the built 1.5 driver imports any post-1.0.5 runtime symbol (nm audit, R3).
- Whether a 1.0.5 daemon runs the 1.5 filter acceptably in degraded mode (VM run, R3).
- The issue 49 reply and the 150/164 follow-ups stay owed once the redo has numbers;
  nothing is posted from this branch.
