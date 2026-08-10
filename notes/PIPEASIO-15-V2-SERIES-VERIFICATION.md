# PipeASIO 1.5 v2 series: rework and verification, 2026-08-10

Branch `moonshot-pipeasio-15-v2`. This note records the rework of the
`patches/pipeasio` series against `vendor/pipeasio-1.5.0.tar.gz`, executed to
the plan in notes/FINDINGS-PIPEASIO-15-REDO-2026-08-10.md (sections 3, 4 and
5/R2), and the verification runs behind it. Nothing here is committed or
published; the patch files in `patches/pipeasio/` are the deliverable.

The series is now seven patches: 0001, 0002, 0004, 0005, 0006, 0008, 0009.
0003 stays a documented gap (retired into 0005 in the first port). 0007
(follower headroom) is removed from the series entirely; its mechanism does
not work mid-stream (a live Props write only changes default_headroom, which
is re-read at the next renegotiation, never mid-stream) and it carried
ownership, restore and crash-residue faults. The C8 follower-headroom class
returns later as a pre-start or renegotiation-time mechanism with a real
two-clock rig to verify on, or as a documented WirePlumber rule.
0010-gui-accept-any-buffer-size.patch is owned by the settings-panel work and
was not touched; it applies cleanly on top of this series (checked with
patch --fuzz=0 on the patched tree).

## Per-patch changes

**0001 asio: clamp unavailable sample-rate requests.** Unchanged in content;
regenerated so the mail header carries the new series position. Live treats a
SetSampleRate refusal as fatal, so an unavailable rate keeps the current rate
and reports success; GetSampleRate tells the host the truth.

**0002 asio: report timeGetTime in ASIO systemTime.** Carried, plus wrap
safety. timeGetTime is a 32-bit millisecond counter over the host's
CLOCK_BOOTTIME and wraps every 49.71 days of host uptime, regardless of when
Live launched. The driver now keeps a 64-bit extension (last raw DWORD
reading plus accumulated rollovers; the raw counter is monotonic, so a
smaller reading can only be a wrap) and scales the extended value to the ASIO
nanosecond domain. The extension state lives in the driver object and is
touched only on the process path. One wrap between two consecutive process
cycles is the covered case.

**0004 config: accept any buffer size in range, log every adjustment.**
Rewritten. Validation is range-only [32, 8192] at all three former pow2
sites: the INI loader (src/config.c), the PIPEASIO_PREFERRED_BUFFERSIZE
environment override, and the host-controlled branch of CreateBuffers. Out of
range falls back to the previous value (the default for the INI loader) with
a log line; in-range non-pow2 values pass through untouched. GetBufferSize's
host-controlled branch advertises min 32, max 8192, granularity 1: per the
ASIO SDK a positive granularity means arithmetic steps and -1 means pow2
steps, so -1 no longer matched the CreateBuffers contract. Upstream's
SPA_PARAM_BUFFERS_align no longer derives from the buffer size: PipeWire's
allocator does pure bitmask arithmetic on align and validates nothing, so a
non-pow2 align silently corrupts the buffer layout; align is a fixed 16, the
context's SIMD minimum. test_config's validation group moved to the new
contract (1000/883/960 valid; below-floor and above-ceiling values fall back
to the default) and gained INI round-trip cases for 883, 960 and 1000. The
upstream test that expected buffer_size=1000 to fall back is gone with it.

**0005 converge on a foreign quantum: predict, adopt, mute.** State machine
rewritten around the review's B4/B5/B6 findings.

- Adoption state lifetime: `quantum_adopted` clears on Stop, on
  DisposeBuffers, and when the forcing condition ends. Forcing-condition
  tracking is new: the registry counts foreign nodes carrying a nonzero
  node.force-quantum (own node excluded, count decremented on node removal)
  and the settings metadata's global clock.force-quantum is tracked as
  before; `audio_forcer_present` exposes both to the watcher. The clear fires
  when no forcer is visible and no mismatch is active, so an in-flight rebuild
  against a forcer the registry cannot see is not cancelled mid-reset.
- Commit timing: the watcher no longer commits the reset target when issuing
  kAsioResetRequest. It records `adopt_pending_quantum`, which survives the
  host's Stop/DisposeBuffers, and CreateBuffers commits it on arrival: a
  rebuild at the target makes the adoption effective, any other size discards
  the target and the watcher may retry the same quantum. The
  3-adoptions-per-minute cap is the loop bound for ignored resets.
- Validation: every quantum advertised to the host passes
  pipeasio_buffer_size_supported, and the predict path prefers the graph's
  running clock.duration over the raw metadata string (the daemon clamps
  forced values to clock.quantum-limit, so metadata and reality can
  disagree). The observed quantum resets on deactivate so stale values never
  drive a later advertisement. A size CreateBuffers would reject is never
  advertised.
- Host-controlled convergence: GetBufferSize returns the adoption target
  (pending first, then the converged session's quantum) as preferredSize in
  host-controlled mode, so a host that honours the reset rebuilds at the
  adopted quantum. Previously the adopted value was read by nothing on that
  path.
- Shared env parser: `pipeasio_env_on_off` in include/pipeasio_parse.h,
  strcasecmp with `#include <strings.h>` (glibc and mingw-w64 both declare it
  there; the unix objects build with -Werror=implicit-function-declaration).
  Both halves parse PIPEASIO_ALLOW_QUANTUM_MISMATCH through it; the old
  lstrcmpiA-vs-strcmp split made "=ON" mute one half only.
- Mute cadence: while sizes disagree the host callback no longer runs once
  per graph cycle at host size (a 512-frame host on a 128 graph ran 4x DSP
  and raced the transport). Graph frames accumulate and one host callback
  fires per buffer_size frames banked, with a bounded loop when the quantum
  exceeds the host size (both values range-validated, so the bound is at most
  max/min per cycle). Transport advances at real speed, DSP stays at 1x,
  output stays muted, one warning per episode (the warning re-arms when the
  mismatch clears).
- No persistent unix-side adoption state: the live node.force-quantum drop
  applies to the current filter instance only. Every rebuild tears the filter
  down and re-enters arbitration with our own force at the new size, which
  converges by construction (same value as the forcer, or a fresh episode if
  the forcer has moved on).
- WoW64: four new appended calls (PAU_GLOBAL_FORCE_QUANTUM,
  PAU_QUANTUM_MUTED, PAU_FORCER_PRESENT, PAU_DROP_FORCE_QUANTUM), both
  dispatch tables extended, and tests/wow64/unix_abi_layout.c updated (that
  compile-time guard pins the enum and count; the PR #160 series would have
  failed it).

**0006 audio: anchor the fallback capture, report clock domains.** The
ordering fault is fixed: CreateBuffers now resolves the playback endpoints
before the capture endpoints, so the no-input-configured capture fallback
anchors to the card the output side actually resolved to, an explicit
output_device included. Previously inputs resolved first against the system
default or lowest-id playback node, so explicit USB output plus unset input
anchored capture to the onboard card and the warning named the wrong card.
The capture fallback reads the recorded playback choice (chosen_node[1])
first and only falls back to the metadata default when playback has not
resolved. The warning names the chosen source, the playback device it shares
a card with, and the lowest-id candidate it displaced. The
different-cards-in-use report (once per pair) is unchanged in mechanism.

**0008 log the PipeWire versions at init, gate pre-1.2 daemons to pow2.**
New. At init the driver logs pw_get_library_version() and the daemon version
from pw_core_info (a core info handler is new; the info event lands during
audio_open's first core sync, so the version is known before Init returns).
When the daemon parses older than 1.2 (Ubuntu 24.04 / Mint 22.x ship 1.0.5):
one log line names the daemon version and the restriction, and the driver
runs in a restricted envelope instead of refusing. CreateBuffers and
GetBufferSize revert to the pow2 contract (granularity -1), non-pow2
configured or derived sizes round to the nearest power of two with a logged
adjustment, the predict path only advertises pow2 pins, and the adopt path
never asks the host for a non-pow2 rebuild. An unparseable version string is
logged and treated as current. WoW64 gains PAU_DAEMON_RESTRICTED, with the
ABI guard extended.

**0009 make realtime=false real: demote inherited scheduling, add
PIPEASIO_REALTIME.** New. audio_rt_acquire with realtime=false used to log
"left SCHED_OTHER" and return without touching policy; under the production
launcher (chrt -r 10 wine) glibc's PTHREAD_INHERIT_SCHED hands every created
thread SCHED_RR, so the log line was false there and the shipped default
never took effect. acquire now reads the thread's actual policy first
(pthread_getschedparam on the data-loop thread) and with realtime off
explicitly demotes to SCHED_OTHER priority 0; before and after policies are
logged in every branch. audio_rt_drop is symmetric: it demotes whenever the
thread is not SCHED_OTHER, even when the raise was never ours. The WoW64
pump gets the same treatment. PIPEASIO_REALTIME=on/off is a per-launch
override parsed with the shared case-insensitive helper on both halves
(configure_driver on the PE side, the acquire path and the pump on the unix
side); the existing PIPEASIO_RT_PRIORITY spellings keep the last word for
compatibility. The shipped default stays realtime=false; the P2 scheduling
A/B decides any flip separately.

## Marker strings for build-audit reconciliation

All markers verified present as literal strings in the built
x86_64-unix driver (`strings` on pipeasio64.dll.so; counts in parentheses).
scripts/build-audit.sh is owned elsewhere and was not touched; it needs the
0007 entry removed, a PIPEASIO_GAPS entry for 0007, and entries for
0008/0009.

| patch | markers |
|---|---|
| 0001 | pipeasio-clamp-sample-rate (1) |
| 0002 | pipeasio-midi-timebase (1) |
| 0004 | pipeasio-any-buffer-size (2) |
| 0005 | pipeasio-quantum-converge (2), pipeasio-quantum-arbitration (1) |
| 0006 | pipeasio-clock-domains (2) |
| 0008 | pipeasio-daemon-version (4) |
| 0009 | pipeasio-honest-realtime (4) |
| 0007 | removed; pipeasio-follower-headroom no longer appears (0) |

## Verification runs

Host: CachyOS, wine 11.13 (Staging), system PipeWire 1.6.8
(pkg-config libpipewire-0.3 = 1.6.8, so the worktree's vendored pipewire-sdk
was not needed), cmake 4.4.2, gcc 16.1.1, git 2.55.0. Build tree under the
session scratchpad (series-rework/), throwaway git repo on the pristine
1.5.0 extract, one commit per patch.

1. Application. The regenerated series applies to a pristine extract of
   `vendor/pipeasio-1.5.0.tar.gz` with `patch -p1 --fuzz=0` (zero fuzz, zero
   offsets) and independently with `git am`; both resulting trees are
   byte-identical to the tree the commits produced and everything below was
   built from. 0010 (gui) applies cleanly on top.

2. Build. Upstream CMake, Release: configure and full build exit 0 with zero
   warnings and zero errors in the build log (grep over the captured log).
   Driver, register script, probes, unit tests and the Qt panel all built.

3. ctest. Full suite: 18 tests, 14 passed, 4 skipped (asio_probe,
   asio_probe_rt, asio_probe_err, asio_loopback skip under ctest because the
   driver is not installed under $HOME/.local; both were then run manually,
   next item). Passing set includes the rewritten test_config plus
   test_offsets, test_admission_gate, test_pw_buffer_region,
   test_handle_table, the wow64_unix_abi_layout guard (now pinning
   PAU_CALL_COUNT == 34), register_script, the pw probes, the interleave
   lifecycle tests and test_panel. ASan/UBSan: a second build with
   -DPIPEASIO_ASAN=ON; the five instrumented unit test binaries were run
   directly (the ctest fixture insists on a fully instrumented driver
   artifact, which was not needed for this check) with halt_on_error=1:
   test_config 72 checks, test_offsets 927, test_admission_gate 55,
   test_pw_buffer_region 39, test_handle_table 11287, zero failures, zero
   sanitizer reports.

4. Driver runs against the live session daemon (PipeWire 1.6.8, null-sink
   loopback per the pipeasio-15 branch's notes/ABLETON-WINE-PIPEASIO.md
   recipe, throwaway wineprefix, cmake --install into a scratch root):
   - tests/asio_probe, 5 s: PASS. Lifecycle, cadence (47 cycles/s at 1024),
     position, latency settle, measured rate, concurrent-stop and restart
     checks all ok.
   - tests/asio_loopback, SIZES="256 883", 6 s per phase: PASS both phases.
     bs=256: RTL 256 samples, exactly 1.00 cycles (5.33 ms), 0
     discontinuities, 0 bit errors, 0 sign errors. bs=883 (non-pow2 through
     the new range-only contract and the align=16 buffers pod): RTL 883
     samples, exactly 1.00 cycles (18.40 ms), 0/0/0. Matches the
     moonshot-pipeasio-15 branch's one-period numbers.
   - Not run here: Ableton Live itself, real hardware, the WoW64 32-bit
     front end (BUILD_WOW64_32=OFF by default; its i686-mingw link was not
     exercised), any 1.0.5 daemon (no such host available; the 0008
     restricted envelope is exercised only through its non-restricted branch
     and needs the planned VM run).

5. Runtime-floor symbol audit. `nm -D --undefined-only` on the built
   x86_64-unix driver: 37 undefined pw_* dynamic symbols, zero spa_* (all
   SPA usage is header-inline). DT_NEEDED is libpipewire-0.3.so.0, libm,
   libc, ld-linux only; no rpath. Full list:

   pw_context_connect, pw_context_destroy, pw_context_get_data_loop,
   pw_context_new, pw_core_disconnect, pw_data_loop_get_loop,
   pw_data_loop_set_thread_utils, pw_data_loop_start, pw_data_loop_stop,
   pw_filter_add_port, pw_filter_connect, pw_filter_dequeue_buffer,
   pw_filter_destroy, pw_filter_get_node_id, pw_filter_get_state,
   pw_filter_new_simple, pw_filter_queue_buffer, pw_filter_state_as_string,
   pw_filter_update_properties, pw_get_library_version, pw_properties_free,
   pw_properties_new, pw_properties_set, pw_properties_setf, pw_init,
   pw_proxy_destroy, pw_thread_loop_destroy, pw_thread_loop_get_loop,
   pw_thread_loop_get_time, pw_thread_loop_lock, pw_thread_loop_new,
   pw_thread_loop_signal, pw_thread_loop_start, pw_thread_loop_stop,
   pw_thread_loop_timed_wait_full, pw_thread_loop_unlock,
   pw_thread_loop_wait.

   Every symbol in that list is 0.3-era API. The built driver imports no
   post-1.0.5 runtime symbol, so the binary loads against a 1.0.5 client
   library; the 1.4.2 floor is a build-time header requirement only. This
   answers the redo note's open nm question and keeps the
   daemon-version-aware envelope (0008) as the mechanism for the Ubuntu
   24.04 / Mint population, rather than a hard client-library floor.

## Open items

- Live-level verification: no Ableton Live run happened here. The scratch
  build carries the driver only; a production run needs the container build.
- Container build and audit: scripts/build-audit.sh needs the 0007 entry
  removed, PIPEASIO_GAPS for 0007, and FINGERPRINTS entries for 0008/0009
  (marker table above); patches/SERIES.sha256 needs regeneration. Both files
  are owned outside this task and were not touched.
- The 0008 restricted envelope needs the planned 1.0.5 VM run (81.0x19 has
  the VM) together with the issue 150 driver-type-switch crash regression.
- The 0009 demotion changes scheduling behaviour under the production
  launcher; the P2 ABLETON_RT x realtime A/B on the 4-core cage must re-run
  with this driver before any release claim, and the realtime default stays
  off until it does.
- Quantum-converge exercises against a real forcing client (pipewire-jack
  global pin before launch, mid-run change, ignored-reset host) ran only in
  the predict form here (loopback at forced sizes); the adopt/mute/retry
  paths are code-reviewed and unit-buildable but have no end-to-end run yet.
- The WoW64 32-bit front end is unbuilt on this host; 0002's timeGetTime
  call in the shared host-call path predates this rework and the i686 link
  list carries no winmm import library, so a BUILD_WOW64_32=ON build should
  be checked once before that front end ships anywhere.
- Follower headroom (retired 0007): the C8 class remains owned by the P3
  host arm; two-device sessions still rely on PipeWire's own resampling
  headroom until a renegotiation-time mechanism exists.
