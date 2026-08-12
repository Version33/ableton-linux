# PipeASIO 1.5 v2: patch series and verification record

Date: 2026-08-12

Branch: `moonshot-pipeasio-15-v2`

This note describes the final downstream series applied to
`vendor/pipeasio-1.5.0.tar.gz`. The achievable contract is bounded: prevent
buffer corruption and wrong-speed output, fail silent while an unresolved
quantum mismatch exists, and recover through bounded reset requests inside the
declared PipeWire and device envelope. It is not a promise of uninterrupted
audio during arbitrary CPU starvation, device loss, or daemon failure.

## Series layout

The series contains nine patches:

1. `0001-asio-clamp-unavailable-sample-rate-requests.patch`
2. `0002-asio-report-timeGetTime-in-ASIO-systemTime.patch`
3. `0004-accept-any-buffer-size-in-range-log-every-adjustment.patch`
4. `0005-converge-on-a-foreign-quantum-predict-adopt-mute.patch`
5. `0006-anchor-fallback-capture-report-clock-domains.patch`
6. `0008-log-pipewire-versions-gate-pre-1-2-daemons-to-pow2.patch`
7. `0009-honest-realtime-toggle.patch`
8. `0010-gui-accept-any-buffer-size.patch`
9. `0011-controlpanel-dialog-off-the-host-gui-thread.patch`

`0003` remains a documented gap because its earlier work was absorbed into the
quantum patch. `0007` is deliberately retired: mutating
`api.alsa.headroom` on a shared active node was neither a demonstrated
clock-drift repair nor a safe ownership model, and it contained ineffective
mid-stream writes, restoration hazards, and a data race.

## Patch behaviour

### 0001: sample-rate correction state

The Live-specific unavailable-rate workaround remains: a request the device
cannot satisfy keeps the actual current rate and reports that truth to the
host. The equality path now also updates the remembered host request. A daemon
correction accepted by the host therefore cannot reactivate an older stale
request on the next engine start. The tests cover correction followed by
reactivation.

### 0002: MIDI-compatible ASIO time

ASIO `systemTime` uses Wine `timeGetTime()` for Live's MIDI timestamp domain.
The 32-bit millisecond counter is extended to 64 bits before conversion to
nanoseconds, preserving monotonic time across its approximately 49.7-day wrap.
The implementation covers the single wrap possible between consecutive audio
callbacks. A real long-uptime MIDI hardware observation remains open.

### 0004: arbitrary buffer sizes without allocator corruption

The accepted range is every integer from 32 through 8192 frames. INI,
environment, `GetBufferSize()`, and `CreateBuffers()` use the same range;
`GetBufferSize()` reports granularity 1 rather than the power-of-two value -1.
Values such as 192, 882, 883, 960, 1025, 1536, 5000, and 8191 are therefore
representable rather than silently rewritten.

`SPA_PARAM_BUFFERS_align` is a fixed valid power-of-two value of 16 and is
independent of the period length. The allocator is never given an arbitrary
period-derived alignment. Unit and GUI tests were rewritten to the range
contract instead of bypassing the old power-of-two expectations.

### 0005: quantum prediction, adoption, muting, and restoration

The convergence state machine distinguishes configured preference, observed
graph duration, pending adoption, committed adoption, and pending restoration.

- Only supported values are advertised or accepted.
- A global forced quantum visible before activation can be predicted without
  losing the ownership needed to restore the configured preference later.
- A reset target is not committed when `kAsioResetRequest` is sent. It is
  committed only when a successful `CreateBuffers()` rebuild reaches the
  admitted target.
- Ordinary Stop/Start and DisposeBuffers sequences preserve adoption state
  needed by the still-active graph policy; explicit policy changes clear it.
- When a forcer disappears, restoration stays pending until the host actually
  rebuilds. An ignored reset is retried after five seconds, bounded to three
  requests per minute. Reappearing/flapping forcing does not reopen the budget.
- Fixed mode commits only the configured target. Host-controlled mode may
  commit another valid, successful, unforced rebuild.

Foreign `node.force-quantum` is live state, not a registry snapshot. Node
proxies listen for `PW_NODE_CHANGE_MASK_PROPS`, so in-place `0 -> Q -> 0`
changes are observed without node removal. Settings metadata is accepted only
for `PW_ID_CORE`, and cached global values clear when that metadata object
disappears.

During an unresolved mismatch, output is zeroed and captured input is not
published to the host. Graph frames are banked so the host-sized DSP callback
runs at its intended average sample cadence rather than once per smaller graph
cycle. This avoids the former 512-on-128 four-times workload. Invalid or
unrepresentable durations remain fail-silent instead of driving unbounded DSP.

`PIPEASIO_ALLOW_QUANTUM_MISMATCH` uses one case-insensitive on/off parser in
both halves, eliminating the earlier `ON` split-brain. The optional WoW64 path
also consults the mute state before copying or publishing audio. Its Unix-half
scheduler/logging source passes a target-equivalent syntax compile.

### 0006: capture follows the selected playback card

Playback is resolved before fallback capture. An explicit `output_device` is
therefore part of the anchor decision. With no explicit input, capture first
tries a physical source whose strictly parsed `device.id` matches the selected
playback node, then the system default, then the deterministic lowest-ID
fallback. An explicit input always wins. Diagnostics report when selected
capture and playback use separate clock domains.

### 0008: live PipeWire state and old-daemon compatibility code

The driver logs both its loaded PipeWire client version and the daemon version
from core information. The patch also contains the older-daemon power-of-two
compatibility envelope and the live registry/metadata property tracking used
by 0005.

The packaged installer has a stricter release policy than that internal
compatibility code: it refuses either a client or daemon below 1.4.2 before
runtime replacement or registration. The 1.0.5 path is therefore not claimed
as supported by this artifact.

### 0009: an honest realtime-off mode

With PipeASIO realtime disabled, the data-loop thread is explicitly moved to
`SCHED_OTHER` priority zero even when Wine inherited `SCHED_RR` from the
launcher. Drop is symmetric and demotes a thread that remains realtime even if
the driver did not perform the original raise. The WoW64 pump follows the same
policy. `PIPEASIO_REALTIME=on|off` is parsed consistently on both halves, and
logs report the observed before/after scheduler state.

The default remains realtime off. Any default change depends on the pending
four-combination low-core scheduler experiment.

### 0010: settings panel contract

The panel can display and save an arbitrary current buffer value inside
32-8192 rather than forcing it into a preset or back to 1024. The invalid
16-frame preset is absent. Invalid/intermediate text blocks Apply instead of
destructively substituting a default.

The channel controls cannot save zero inputs and zero outputs together, which
the driver would reject on reopen. Save failure keeps the inline status and
opens a non-blocking critical error dialog naming the configuration path.
Successful Apply reports that the audio device must be restarted.

### 0011: Hardware Setup process lifetime

The fallback worker pins the driver module with
`GetModuleHandleEx(...FROM_ADDRESS...)` before creating the thread and exits
through `FreeLibraryAndExitThread`. The DLL cannot unload while its code is
still scheduled or the dialog is open.

The worker launches the native settings process with a clean signal mask and
ordinary scheduler, waits for and reaps it, and treats an early nonzero exit as
startup failure. Missing Qt libraries or a QPA plugin therefore produces the
fallback message instead of a silent button and a zombie. The panel and its
children do not inherit Live's realtime scheduling policy.

## Source and artifact verification

The complete series applies to the vendored 1.5.0 archive with GNU patch
`--fuzz=0`, without rejects. `patches/SERIES.sha256` verifies the full frozen
manifest. The build audit has concrete binary fingerprints for all nine
patches; no PipeASIO patch relies on the transitional marker-TODO path.

Source-tree verification completed as follows:

- RelWithDebInfo CMake build and CTest: 19/19 passed; nine live-runtime probes
  skipped because no test graph was available;
- ASan+UBSan-labelled suite: 17/17 passed;
- TSan native units: 6/6 passed;
- optional WoW64 Unix half: target-equivalent syntax compile passed;
- full i686 MinGW link: not run because the compiler is unavailable;
- `git diff --check`: clean.

The final Jammy artifact build then passed production and no-Qt CMake/CTest,
ASan+UBSan 11/11, TSan 6/6, relocation, registration, and the independent
142/142 packaged-tree audit. Both exact driver-only panel-skip variants passed
134/134 audits. The native version probe reports client 1.6.8 and daemon 1.6.8
on the build host; its runtime and `dist/` copies are byte-identical.

Installer lifecycle verification on the PR #182 structure passed 158/158
checks: 45 shortcut, 29 dispatcher/lifecycle, and 84 focused PipeASIO and
transaction checks. The final bounded audit also passed both guarded
custom-Link retirement windows: a replacement before capture is preserved and
de-owned, while a replacement after capture is preserved and seals a conflict
that prevents commit or rollback from overwriting it.

## Release gates not satisfied by these tests

No automated result above substitutes for the final runtime matrix. Still
required are:

- exact-artifact Live 11 and Live 12 tests, including Hardware Setup lifetime
  and panel startup failures;
- bit-exact loopback at 32, 64, 128, 192, 256, 512, 882, 883, 960, 1025,
  1536, 5000, 8191, and 8192 frames at all six advertised rates;
- end-to-end global and JACK `0 -> Q -> 0`, invalid values, reset acceptance,
  reset refusal, and forcing-node lifetime;
- real capture/playback alignment, same-card duplex, separate clocks, hotplug,
  suspend/resume, reconnect, and PipeWire restart;
- Live MIDI on hardware and long-uptime timestamp wrap;
- all `ABLETON_RT` by `PIPEASIO_REALTIME` combinations with thread-policy,
  CPU, DSP, and `pw-top` measurements;
- Debian 13 at 1.4.2, safe Ubuntu/Mint 1.0.5 refusal, current Fedora/Arch,
  X11/Wayland, missing Qt, rollback, and uninstall.

Upstream has not confirmed PipeASIO 1.5 with Ableton Live. The recorded null
and automated results do not support a claim that the update reduces CPU use.
