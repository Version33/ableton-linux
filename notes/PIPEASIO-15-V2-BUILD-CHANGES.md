# PipeASIO 1.5 v2: build and packaging changes, 2026-08-10

Branch moonshot-pipeasio-15-v2, build/packaging arm of the PR #160 redo. Spec:
notes/FINDINGS-PIPEASIO-15-REDO-2026-08-10.md, sections 2E, 3 B1/B10, 5 R1.
Files owned by this pass: scripts/container-build.sh, scripts/build-audit.sh,
scripts/install.sh, scripts/uninstall.sh, Containerfile. Nothing here is
committed; the container build itself has not been run (builder-only).

## What changed per file

### scripts/container-build.sh

Step [4/8] rebuilt around upstream CMake instead of the hand-driven
gcc/moc/winebuild pipeline. That pipeline is what failed CI run 31287663024:
jammy's Qt 6.2.4 ships CMake config files but no pkg-config .pc files (Qt
gained those in 6.3), so `pkg-config Qt6Widgets` expanded to nothing under a
failed-substitution blind spot and g++ compiled the panel without Qt flags.

- Vendor bump in the build: pipeasio-1.5.0.tar.gz (tarball and sha256 were
  already in place in this worktree).
- Patch apply loop unchanged in shape: every patches/pipeasio/*.patch in
  sorted glob order, count-checked, nothing hardcoded. The parallel series
  rewrite (0007 out, 0008/0009/0010 in) needs no build-script change.
- Configure: `cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release` with
  `-DWINEBUILD`/`-DWINEGCC` pinned to this build's staged Wine tools (the
  upstream WineDLL.cmake header probe then follows winebuild to
  $PREFIX_ROOT/include, the same three include dirs the old hand build
  passed). BUILD_SETTINGS_PANEL=ON, BUILD_TESTS=ON.
- PipeWire SDK: same vendored /opt/pipewire-sdk as before, now fed through
  upstream's `pkg_check_modules(... libpipewire-0.3>=1.4.2)` via
  PKG_CONFIG_PATH plus PKG_CONFIG_SYSROOT_DIR (the SDK .pc files say
  prefix=/usr; the sysroot rewrites every -I and -L under /opt/pipewire-sdk).
  Link-time only, exactly as before: DT_NEEDED libpipewire-0.3.so.0 by
  soname, rpath forbidden, both still asserted.
- `-DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined`: the SDK's 1.6.2 .so
  is an Ubuntu 26.04 build and references __isoc23_* at GLIBC_2.38; the
  container's glibc is 2.35, and ld's default for executables is to reject
  undefined symbols in linked shared libraries. Without the flag the native
  test executables (pw probes, test_pw_buffer_region) fail to link. The flag
  applies to native executables only; the driver .so link (winegcc -shared)
  never needed it. Verified locally that the default rejects and the flag
  links.
- kernelbase: upstream's CMake already links it (add_wine_dll LIBS, present
  since 1.3.0 for the generation-based Stop). Verified in the vendored
  1.5.0 CMakeLists and in the generated link line. Nothing added.
- CC=gcc CXX=g++ on the configure so cmake resolves compilers through PATH
  and hits the ccache shims; cmake's default /usr/bin/cc bypasses them.
- CTest runs in-container and a test failure fails the build (see scope
  below).
- Panel gate: after the build, build/gui/pipeasio-settings must exist. In
  this container qt6-base-dev is pinned, so a configure that skipped gui/
  means Qt6 CMake discovery broke and the build fails with a message saying
  so. Outside the container, PIPEASIO_ALLOW_NO_PANEL=1 downgrades that to
  "panel: skipped (no Qt6)" (recorded in BUILD-INFO) and the driver still
  builds; the build audit still refuses a tarball without the panel, so a
  panel-less artifact cannot ship.
- Install: by hand, not `cmake --install`. The four driver files stay plain
  copies at the exact paths every release has shipped (pipeasio64.dll,
  pipeasio.dll, pipeasio64.dll.so, pipeasio.dll.so; upstream would install
  symlinks for the second name), and upstream's pipeasio-register script
  does not ride along. Panel destinations mirror the old branch exactly:
  bin/pipeasio-settings, share/applications/pipeasio-settings.desktop,
  share/icons/hicolor/scalable/apps/pipeasio.svg. rpath checks on the driver
  .so and the panel binary kept from the old branch.
- BUILD-INFO: pipeasio 1.5.0; pipewire-floor line now says 1.4.2 (upstream's
  build-time minimum, with the Ubuntu 24.04/Mint 22 caveat); new
  pipeasio-settings hash line (post-strip) and a pipeasio-tests line
  recording the in-container ctest scope and result.

### Containerfile

- Added cmake and ninja-build (PipeASIO now configures and builds through
  upstream CMake; jammy's cmake 3.22.1 satisfies upstream's 3.20 minimum).
- Added qt6-base-dev, qt6-base-dev-tools (panel build, moc for AUTOMOC) and
  qt6-qpa-plugins. The last one is new relative to the old branch: it carries
  the offscreen platform plugin, and with --no-install-recommends nothing
  else pulls it in; without it the headless test_panel run cannot start
  (jammy packages the platform plugins there, not in libqt6gui6).
- Comment updates only, no other package changes: the PipeWire SDK section
  now states the 1.4.2 floor and the PKG_CONFIG_SYSROOT_DIR mechanism, and
  the Qt section records the no-.pc-files-in-6.2.4 fact that broke CI.

### scripts/build-audit.sh

- Ported the old branch's independent pipeasio numbering loop with
  PIPEASIO_GAPS. [0003] kept verbatim (retired into 0005). [0007] added:
  follower headroom retired 2026-08-10, mechanism ineffective mid-stream (a
  live api.alsa.headroom write lands in default_headroom only and takes
  effect at the next renegotiation). Gap entries are inert while the number
  is still present in SERIES, so the entry is transition-safe before the
  final series lands.
- pipeasio fingerprints now aim at lib/wine/x86_64-unix/pipeasio.dll.so (the
  spec-file name Wine actually loads), matching the old branch; 0001 and
  0002 markers carried over as live entries.
- Marker placeholders for the rewritten 0004/0005/0006 and new
  0008/0009/0010: a commented block headed TODO(reconcile-markers) holds the
  expected entry shape (module plus last-known marker; 0010's marker lives
  in bin/pipeasio-settings, not the driver), and a PIPEASIO_MARKER_TODO list
  makes those patch numbers pass on sha plus stack stamp alone. A loud
  NOTICE block prints at the end of every audit run while any of them is
  still deferred. Filling a FINGERPRINTS entry automatically takes that
  patch out of the TODO path; emptying PIPEASIO_MARKER_TODO afterwards is
  part of the reconciliation.
- Structural must-checks added: bin/pipeasio-settings, the desktop file, and
  the icon (the old branch checked the first two; the icon is new).
- The [4/4] readelf DT_NEEDED and rpath checks moved from pipeasio64.dll.so
  to pipeasio.dll.so, matching the fingerprint target.
- Verified against a synthetic repo and tree shaped like the final series
  (0001, 0002, 0004, 0005, 0006, 0008, 0009, 0010): both gaps report as
  documented, TODO patches pass via stack stamp, the NOTICE prints, all new
  must-checks pass, and only the fixture-inherent DT_NEEDED checks fail
  (text files, not ELF).

### scripts/install.sh

- Panel install ported from the old branch, unchanged in mechanism: symlink
  ~/.local/bin/pipeasio-settings into the runtime (so upgrades track), a
  runtime-missing-Qt hint via ldd naming the distro package, desktop entry
  rewritten with the absolute Exec path, icon into XDG hicolor.
- Rollback path fix (review blocker B10): the failure cleanup now removes
  the panel symlink, desktop entry, and icon when the runtime left in place
  after the rollback has no bin/pipeasio-settings. A restored runtime that
  does have a panel keeps all three, since the symlink target is
  version-independent.
- New post-install realtime notice: when the invoking user's `ulimit -r` is
  0, the script says realtime scheduling is not granted and points at
  scripts/setup-realtime.sh (needs sudo, applies at next login). With a
  terminal it offers to run it, read from /dev/tty, default No, 60 second
  timeout; without a terminal it only prints the notice. The block runs
  after the install is complete and the EXIT trap is cleared, and the
  setup-realtime invocation is failure-guarded, so nothing in it can undo
  or fail an otherwise successful install.

### scripts/uninstall.sh

- Removes the three panel artifacts install.sh creates: the
  ~/.local/bin/pipeasio-settings symlink, the desktop entry, and the icon,
  using the same XDG_DATA_HOME-aware paths install.sh writes to.

## In-container CTest scope

Two invocations, both fatal on failure, both --no-tests=error:

1. `ctest -L '^unit$'`: the Linux-native unit suite (test_config,
   test_offsets, test_admission_gate, test_pw_buffer_region,
   test_handle_table, plus anything the patch series adds through
   pipeasio_add_unit_test, which applies the label automatically).
2. `ctest -R '^test_panel$'`: the Qt panel suite, headless via its own
   QT_QPA_PLATFORM=offscreen property (needs qt6-qpa-plugins, added). This
   is the test that covers the review's B3 class (panel-side INI contract),
   so it stays in scope even though it is not labelled unit.

Excluded and why:

- asio_probe*, asio_loopback: need a running PipeWire daemon, a registered
  driver, and wine runtime plumbing. Exercised on real machines (R5 matrix).
- pw_filter_probe, pw_delivery_probe, pw_default_probe: same daemon need,
  and additionally they cannot even load in this container: they call real
  pw_ functions and the SDK's .so requires GLIBC_2.38 against the
  container's 2.35, so they would fail at load, not skip with 77.
- register_script: tests upstream's pipeasio-register, which we do not ship.
- wine_install_root_relative: guards a cmake cache variable we do not use.
- wow64_unix_abi_layout: WoW64 32-bit front end is not built (BUILD_WOW64_32
  stays OFF; Live 12 is 64-bit).

Loader shim for the scope: a stub libpipewire-0.3.so.0 (generated from the
union of undefined pw_ symbols across the built unit-test binaries, usually
empty) sits on LD_LIBRARY_PATH for both ctest runs, because a unit binary
that links the SDK .so may carry its DT_NEEDED while the real SDK library
cannot load on this glibc. The unit scope never calls into PipeWire at
runtime. Same technique the relocation gate already uses for regsvr32.

Validated end to end on the host (pipx cmake 4.x, host wine tools, extracted
vendor SDK behind PKG_CONFIG_SYSROOT_DIR, current mid-flight patch series):
configure finds libpipewire 1.6.2 from the sysroot, the full tree builds
including both wine halves and the panel, driver DT_NEEDED and no-rpath hold,
test_panel and 4 of 5 unit tests pass, and test_pw_buffer_region passes
against the empty stub.

## Open reconciliation items

1. test_config currently fails, by design of the gate: the mid-flight 0004
   still leaves upstream's expectation that buffer_size=1000 falls back to
   1024 (tests/unit/test_config.c line ~141), which 0004 makes valid. This
   is the exact break named in the findings note, section 3. The rewritten
   0004 must update the validation group (spec R2) or the container build
   now dies at ctest. Confirmed live in the local dry-run.
2. Marker reconciliation: fill the TODO(reconcile-markers) FINGERPRINTS
   entries for 0004/0005/0006/0008/0009/0010 once the series is final, then
   empty PIPEASIO_MARKER_TODO. The audit prints a NOTICE on every run until
   this is done. Note 0010's marker (pipeasio-any-buffer-size-panel today)
   belongs in bin/pipeasio-settings.
3. SERIES.sha256 refreeze (scripts/build-audit.sh --freeze) after the final
   series lands, with 0007 gone and 0008/0009/0010 in. The PIPEASIO_GAPS
   entries are already transition-safe in both directions.
4. Floor unification outside my files: setup-prefix.sh and
   setup-run-header.sh still carry 0.3.56 strings (B10); owned by the
   setup-scripts agent. My files now say 1.4.2 everywhere.
5. The container image needs a rebuild (new pinned-snapshot packages: cmake,
   ninja-build, qt6-base-dev, qt6-base-dev-tools, qt6-qpa-plugins). Package
   versions stay deterministic via the existing UBUNTU_SNAPSHOT pin.
   Expect artifact hashes in BUILD-INFO to move (toolchain-driven, as the
   Containerfile header documents).
6. The real container build and audit have not been run from here
   (builder-only, 10 GB image). Host-side validation covered the cmake
   configure and build shape, the scoped ctest runs, the stub mechanism,
   the ld flag behavior, and a synthetic full run of build-audit.sh.
7. PIPEASIO_ALLOW_NO_PANEL=1 exists for driver-only experiments outside the
   pinned container; it records "panel: skipped (no Qt6)" in BUILD-INFO and
   the audit still blocks shipping such a tarball.
