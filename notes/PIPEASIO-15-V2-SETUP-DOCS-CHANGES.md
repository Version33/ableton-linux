# PipeASIO 1.5 v2: setup gating and user docs changes, 2026-08-10

Scope of this pass: scripts/setup-prefix.sh, scripts/setup-run-header.sh,
scripts/audio-report.sh, TROUBLESHOOTING.md, CHANGELOG.md. Spec:
notes/FINDINGS-PIPEASIO-15-REDO-2026-08-10.md sections 2D, 3 B10, 4 (version
floors, distro matrix), 5 R1/R3. Nothing here is committed.

## Decisions implemented

- One driver ships everywhere. Setup never refuses: every probe outcome
  warns or logs and proceeds to regsvr32. The restricted mode on daemons
  older than 1.2 (standard power-of-two sizes only) is the driver's own
  behaviour (patch 0008, parallel agent); setup and docs only describe it.
- The rejected branch's soname-only grep (pipeasio-15 setup-prefix.sh:583)
  and its hard "1.4.2 floor, Ubuntu/Mint stay on 2026.08.04.1" docs language
  are both replaced, not carried.
- Follower-headroom automation (old patch 0007) is retired. The replacement
  is detection (audio-report.sh) plus documented user configuration:
  api.alsa.headroom via a WirePlumber monitor.alsa.rules fragment in
  ~/.config/wireplumber/wireplumber.conf.d/.

## setup-prefix.sh (step 4/5)

Two-sided probe replacing the ldconfig soname grep:

- Client library: pkg-config --modversion libpipewire-0.3, else the
  "Linked with libpipewire" line of pw-cli --version, else pipewire
  --version.
- Daemon: version field of pw-cli info 0, else a jq-free grep of pw-dump 0.
- All probes bounded (timeout 5 when available) and failure-proof under
  set -euo pipefail; grep never uses -q against ldconfig (SIGPIPE under
  pipefail, same reason as the header script).
- Policy bands (pw_ver_ge via sort -V):
  - daemon >= 1.4.2: one log line with both versions, silent otherwise.
  - 1.2 <= daemon < 1.4.2: proceed, note lowest-latency untested here.
  - daemon < 1.2: plain warning naming the version, standard-buffer-size
    behaviour, crackle is an audio-server fault fixed in newer PipeWire,
    update or continue. Setup continues.
  - No daemon reachable (chroot/container): library presence check alone,
    warn, proceed; the driver re-checks at first launch.
- Verified: syntax; live run on this host (1.6.8, silent band); no-daemon
  run (diverted runtime dirs); synthetic band classification for 1.0.5,
  0.3.56, 1.2, 1.2.7, 1.4.1, 1.4.2, 1.4.11, 1.6.8, 2.0 (1.4.11 > 1.4.2
  confirms sort -V handles multi-digit components).

## setup-run-header.sh

The missing-library warning's version clause moves from "0.3.56 or newer"
to "1.4.2 or newer recommended, older versions run with standard buffer
sizes only". Nothing else changed in the header.

## audio-report.sh

New in this worktree (main does not carry it); ported from the moonshot
version, with a daemon-version line added to the versions section and a new
final section "follower resync (two-device setups)". The section is
read-only:

- Greps the session log for resync/xrun lines (last 8 shown).
- Samples pw-top -b -n 2, keeps the last iteration, classifies ALSA nodes
  into graph driver (no "+") and followers ("+" prefix).
- Maps an ALSA path from a resync line (hw:XXX) to node.name through
  pw-dump (awk over object boundaries, no jq); falls back to the pw-top
  follower when the log names no mappable device.
- With a follower plus resyncs: prints the device and a copy-ready
  WirePlumber fragment (monitor.alsa.rules matching that node.name,
  api.alsa.headroom = 512, file under wireplumber.conf.d), restart
  instructions, and the remove-it-if-it-does-not-help note.
- Verified: negative path on this host; positive path with stubbed
  pw-top/pw-dump and a real-format resync line (hw:PCH mapped to its node,
  fragment filled in correctly).

Headroom value: 512, matching what the retired automation targeted (the C8
evidence showed a ~256-frame deficit; 512 is the same number in the script
and in TROUBLESHOOTING so the two never disagree).

## TROUBLESHOOTING.md

- "Live has no sound": crackle advice now names PipeASIO Settings first,
  env var second. No floor language.
- New "Crackle on Ubuntu 24.04 and Linux Mint 22": pipewire --version as
  the check, standard-sizes behaviour, crackle is a fault in that PipeWire
  version, full fix is 1.4.2+ via distro upgrade, larger buffer until then;
  the driver-type-switch crash on older project releases and update as its
  fix.
- New "Crackle with two audio devices": detection via audio-report
  (extract-kit invocation plus repo-checkout form), the WirePlumber
  fragment with a placeholder node name, restart/logout step, removal note.
  No automation promised.
- "Audio cuts out for a few seconds, or plays at the wrong speed" carried
  from the moonshot branch as the buffer-size entry and updated: wrong
  speed = releases up to 2026.08.08.1, update; force-quantum clear command
  kept; any-size contract stated (any size in range on PipeWire 1.2+,
  standard sizes on older, cross-reference to the Mint entry).
- "Audio latency remains high": first paragraph rewritten (PipeASIO
  Settings, engine restart via device None-and-back, halved round trip
  with PipeWire 1.4.2+ vs releases up to 2026.08.08.1). The stale
  "PipeWire 1.6 quantum matching" line is gone. Rest of the entry
  untouched.

## CHANGELOG.md

Six bullets at the top of Unreleased, fenced by DRAFT comments naming this
branch and stating the verification matrix has not run: driver update with
halved round trip on PipeWire 1.4.2+ (5.3 ms vs 10.7 ms at default
buffer), any buffer size, wrong-speed fix, PipeASIO Settings ships (issue
60), Ubuntu/Mint supported with standard sizes, installer realtime-setup
notice. Latency claimed, CPU not claimed (spec: the CPU gain does not
exist).

## Open questions / handoffs

- The driver-type-switch crash fix on 1.0.5 is plausible, not confirmed;
  the TROUBLESHOOTING and CHANGELOG lines claiming it need the 1.0.5 VM
  regression run (R3/R5) before release. Same for the restricted-mode
  behaviour itself (patch 0008, parallel agent): docs describe the decided
  behaviour ahead of its verification.
- The installer realtime-setup notice bullet describes work owned
  elsewhere (spec listed it for the changelog; my setup-run-header change
  was limited to the one pipewire line). If no agent lands that notice,
  drop the bullet before release.
- The WirePlumber fragment is the 0.5+ conf.d format. Ubuntu 24.04/Mint 22
  ship WirePlumber 0.4 (Lua config); docs and script say "WirePlumber 0.5
  or newer". A 0.4 Lua variant was not written; the primary two-device
  audience (C8, Fedora-class hosts) is on 0.5+.
- install.sh does not install audio-report.sh to ~/.local/share; docs use
  the --extract invocation, same pattern as the Max for Live repair entry.
- container-build.sh still carries two "0.3.56" floor strings (lines
  147/223); that file is owned by the packaging agent (R1 says unify every
  floor string).
- The session log audio-report reads is written by the moonshot launcher;
  this worktree's launcher does not write it yet. The script already
  handles its absence.
