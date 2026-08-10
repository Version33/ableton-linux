#!/usr/bin/env bash
# Runs inside the Ubuntu 22.04 container (invoked by build.sh); /src = repo (ro), /out = dist/ (rw).
# Produces a relocatable patched-Wine tarball with PipeASIO baked in.
set -euo pipefail

SRC=/src
OUT=/out
WORK=/work
JOBS="${JOBS:-$(nproc)}"
VERSION="$(cat "$SRC/VERSION")"
NAME="wine-d2d1-nspa-11.13"
CONFIGURE_PREFIX="${INSTALL_PREFIX:?build.sh must pass INSTALL_PREFIX}"
[ "$(basename "$CONFIGURE_PREFIX")" = "$NAME" ] || {
    echo "!! INSTALL_PREFIX must end in /$NAME" >&2
    exit 2
}
DESTDIR="$WORK/stage"
PREFIX_ROOT="$DESTDIR$CONFIGURE_PREFIX"
npatch="$(ls "$SRC"/patches/00*.patch | wc -l)"

echo "== [1/8] unpack pristine Wine base (giang17 d2d1-dcomp-11.13 @ 5c23dd1c) =="
mkdir -p "$WORK/wine-src"
zstd -dc --long=27 "$SRC/vendor/wine-base-5c23dd1c.tar.zst" | tar -x -C "$WORK/wine-src"

echo "== [2/8] git init + apply the $npatch-patch fix series =="
cd "$WORK/wine-src"
# Rootless podman can bind-mount /work owned by a UID outside the container's
# user namespace; git (>=2.35.2) refuses to operate on a tree it doesn't own.
# Scoped to this exact path, not a global opt-out.
git config --global --add safe.directory "$WORK/wine-src"
git init -q
git -c user.email=build@localhost -c user.name=dist add -A
git -c user.email=build@localhost -c user.name=dist commit -q -m "base 5c23dd1c"
# The series ships without From:/Date: mail headers; git am refuses to commit
# with an empty author, so supply a fixed neutral ident (fixed date keeps the
# apply reproducible). Patches that still carry headers keep their own.
for p in "$SRC"/patches/00*.patch; do
    if head -8 "$p" | grep -q '^From: '; then
        git -c user.email=build@localhost -c user.name=dist am --3way "$p"
    else
        { printf 'From: dist <build@localhost>\nDate: Thu, 01 Jan 2026 00:00:00 +0000\n'
          cat "$p"
        } | git -c user.email=build@localhost -c user.name=dist am --3way
    fi
done
patch_head="$(git rev-parse HEAD)"
echo "   HEAD: $(git log --oneline -1)"

echo "== [3/8] configure + build Wine (WoW64: clang/lld PE, gcc Unix) =="
mkdir -p "$WORK/build" && cd "$WORK/build"
# CPPFLAGS: the vendored ntsync UAPI header (Containerfile), nothing else in
# that dir, so the 5.15 system headers stay authoritative for everything else.
CPPFLAGS="-I/opt/ntsync-uapi" ../wine-src/configure \
    --prefix="$CONFIGURE_PREFIX" \
    --enable-archs=i386,x86_64 \
    --disable-tests
make -j"$JOBS"
make install DESTDIR="$DESTDIR"
mkdir -p "$(dirname "$CONFIGURE_PREFIX")"
ln -s "$PREFIX_ROOT" "$CONFIGURE_PREFIX"
"$PREFIX_ROOT/bin/wine" --version

bridge_pe="$PREFIX_ROOT/lib/wine/x86_64-windows/libusb-1.0.dll"
bridge_unix="$PREFIX_ROOT/lib/wine/x86_64-unix/libusb-1.0.so"
portal_unix="$PREFIX_ROOT/lib/wine/x86_64-unix/comdlg32.so"
i386_bridge_pe="$PREFIX_ROOT/lib/wine/i386-windows/libusb-1.0.dll"
i386_bridge_unix="$PREFIX_ROOT/lib/wine/i386-unix/libusb-1.0.so"
[ -f "$bridge_pe" ] || { echo "!! Push 2 bridge PE missing: $bridge_pe" >&2; exit 1; }
[ -f "$bridge_unix" ] || { echo "!! Push 2 bridge Unix side missing: $bridge_unix" >&2; exit 1; }
[ -f "$portal_unix" ] || { echo "!! comdlg32 (XDG portal) missing: $portal_unix" >&2; exit 1; }
[ ! -e "$i386_bridge_pe" ] || { echo "!! Push 2 bridge unexpectedly built for i386: $i386_bridge_pe" >&2; exit 1; }
[ ! -e "$i386_bridge_unix" ] || { echo "!! Push 2 bridge unexpectedly built for i386: $i386_bridge_unix" >&2; exit 1; }

expected_exports=$'4 libusb_alloc_transfer\n10 libusb_cancel_transfer\n12 libusb_claim_interface\n16 libusb_close\n26 libusb_error_name\n32 libusb_exit\n40 libusb_free_device_list\n50 libusb_free_transfer\n72 libusb_get_device_descriptor\n74 libusb_get_device_list\n110 libusb_handle_events_timeout\n120 libusb_init\n132 libusb_open\n140 libusb_release_interface\n154 libusb_set_option\n161 libusb_submit_transfer'
actual_exports="$(llvm-readobj --coff-exports "$bridge_pe" | awk '
    /^Export / { ordinal = ""; name = "" }
    /Ordinal:/ { ordinal = $2 }
    /Name: libusb_/ { name = $2 }
    /^}/ && name != "" { print ordinal, name }
')"
if [ "$actual_exports" != "$expected_exports" ]; then
    echo "!! Push 2 bridge export/ordinal mismatch" >&2
    diff -u <(printf '%s\n' "$expected_exports") <(printf '%s\n' "$actual_exports") || true
    exit 1
fi
readelf -d "$bridge_unix" | grep -F 'Shared library: [libusb-1.0.so.0]' >/dev/null
strings "$portal_unix" | grep -F 'org.freedesktop.portal.FileChooser' >/dev/null

# configure silently drops winealsa (ALSA MIDI) when libasound2-dev is absent: fail, don't ship without it.
winealsa_unix="$PREFIX_ROOT/lib/wine/x86_64-unix/winealsa.so"
if [ ! -s "$winealsa_unix" ]; then
    echo "!! winealsa.so missing: libasound2-dev not present at configure time; no ALSA MIDI" >&2
    exit 1
fi

# configure also silently drops winegstreamer (mp3/mp4/wma import) without
# the gstreamer-1.0 dev packages — shipped unnoticed until issue #44.
winegstreamer_unix="$PREFIX_ROOT/lib/wine/x86_64-unix/winegstreamer.so"
if [ ! -s "$winegstreamer_unix" ]; then
    echo "!! winegstreamer.so missing: libgstreamer1.0-dev/libgstreamer-plugins-base1.0-dev not present at configure time; no mp3/mp4/wma import" >&2
    exit 1
fi

# configure also silently drops ntsync without linux/ntsync.h; every NT sync
# wait then becomes a wineserver round trip (~1.3 cores with Live running).
# Shipped unnoticed twice in 2026-07. Check BOTH halves: the 07-12 build lost
# only the wineserver one. notes/ABLETON-WINE-NTSYNC-REGRESSION.md
if ! grep -q '^#define HAVE_LINUX_NTSYNC_H 1' "$WORK/build/include/config.h"; then
    echo "!! HAVE_LINUX_NTSYNC_H not set; linux/ntsync.h not seen at configure time" >&2
    exit 1
fi
# grep -c, not grep -q: -q exits on first match, strings dies of SIGPIPE and
# pipefail turns the success into a false "missing" (this killed a good build).
ntsync_srv="$(strings "$PREFIX_ROOT/bin/wineserver" | grep -c ntsync || true)"
ntsync_ntd="$(strings "$PREFIX_ROOT/lib/wine/x86_64-unix/ntdll.so" | grep -c ntsync || true)"
if [ "${ntsync_srv:-0}" -eq 0 ]; then
    echo "!! no ntsync in wineserver; waits would fall back to server round trips" >&2
    exit 1
fi
if [ "${ntsync_ntd:-0}" -eq 0 ]; then
    echo "!! no ntsync in ntdll.so; waits would fall back to server round trips" >&2
    exit 1
fi
ntsync_hdr_sha="$(sha256sum /opt/ntsync-uapi/linux/ntsync.h | awk '{print $1}')"
echo "   ntsync: compiled in (header $ntsync_hdr_sha)"
bridge_pe_sha="$(sha256sum "$bridge_pe" | awk '{print $1}')"
bridge_unix_sha="$(sha256sum "$bridge_unix" | awk '{print $1}')"
portal_unix_sha="$(sha256sum "$portal_unix" | awk '{print $1}')"
echo "   libusb bridge: PE $bridge_pe_sha / Unix $bridge_unix_sha"

echo "== [4/8] build PipeASIO 1.5.0 against THIS Wine (upstream CMake + CTest) =="
mkdir -p "$WORK/pipeasio"
tar xzf "$SRC/vendor/pipeasio-1.5.0.tar.gz" -C "$WORK/pipeasio" --strip-components=1
cd "$WORK/pipeasio"
# Apply the pipeasio patch series (patches/pipeasio/): every *.patch, sorted;
# the glob is the whole contract, no file list is hardcoded here.
nasio="$(ls "$SRC"/patches/pipeasio/*.patch 2>/dev/null | wc -l)"
[ "$nasio" -gt 0 ] || { echo "!! no pipeasio patches found in $SRC/patches/pipeasio" >&2; exit 1; }
for p in "$SRC"/patches/pipeasio/*.patch; do
    echo "   applying $(basename "$p")"
    patch -p1 --no-backup-if-mismatch -i "$p"
done
export PATH="$PREFIX_ROOT/bin:$PATH"          # this Wine's winegcc/winebuild take PATH priority
# 64-bit only (Live 12 is 64-bit). Built through upstream CMake, which drives
# the same winebuild/winegcc pipeline against this Wine's tools and headers
# (WINEBUILD/WINEGCC pinned below; the header probe follows winebuild to
# $PREFIX_ROOT/include). Hand-driving gcc/moc here is what broke PR #160 in
# CI: jammy's Qt 6.2.4 ships no pkg-config .pc files (Qt gained them in 6.3),
# so `pkg-config Qt6Widgets` expanded to nothing and g++ ran without Qt
# flags. Qt discovery must go through CMake, and jammy does ship Qt's CMake
# config files.
#   - PipeWire comes from the vendored SDK (Containerfile). Its .pc files say
#     prefix=/usr, so PKG_CONFIG_SYSROOT_DIR rewrites every -I/-L under
#     /opt/pipewire-sdk. Link-time only: the .so records DT_NEEDED
#     libpipewire-0.3.so.0 and resolves against the host PipeWire at runtime
#     (declared floor 1.4.2, upstream's build-time minimum; the SDK is 1.6.2).
#   - --allow-shlib-undefined (native test executables only): the SDK's .so
#     wants glibc 2.38 (__isoc23_*) and this container has 2.35, so the
#     default no-allow-shlib-undefined check would fail the pw_probe and
#     test_pw_buffer_region links. Nothing in the ctest scope below calls
#     into libpipewire at runtime (stubbed there for the loader's sake).
#   - CC/CXX name the PATH-resolved compilers so the ccache shims keep
#     working; cmake's default /usr/bin/cc would bypass them.
PW_SDK=/opt/pipewire-sdk
PKG_CONFIG_PATH="$PW_SDK/usr/lib/x86_64-linux-gnu/pkgconfig" \
PKG_CONFIG_SYSROOT_DIR="$PW_SDK" \
CC=gcc CXX=g++ \
cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DWINEBUILD="$PREFIX_ROOT/bin/winebuild" \
    -DWINEGCC="$PREFIX_ROOT/bin/winegcc" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,--allow-shlib-undefined" \
    -DBUILD_SETTINGS_PANEL=ON \
    -DBUILD_TESTS=ON
cmake --build build -j "$JOBS"

# The panel must exist here: this container installs qt6-base-dev, so a
# configure that skipped gui/ means Qt6 CMake discovery broke in the image.
# Fail rather than ship a runtime without the panel (issue #60 all over
# again). Outside this container PIPEASIO_ALLOW_NO_PANEL=1 records the skip
# and keeps the driver build; the build audit still refuses a tarball
# without the panel, so nothing panel-less can ship.
panel_state="built"
if [ ! -x build/gui/pipeasio-settings ]; then
    if [ "${PIPEASIO_ALLOW_NO_PANEL:-0}" = 1 ]; then
        panel_state="skipped (no Qt6)"
        echo "   panel: skipped (no Qt6)"
    else
        echo "!! pipeasio-settings did not build: CMake did not find Qt6 Widgets" >&2
        echo "!! qt6-base-dev is pinned in the Containerfile; a skipped panel in this container is a broken image" >&2
        exit 1
    fi
fi

# In-container test scope: the Linux-native unit suite (ctest label "unit":
# test_config, test_offsets, test_admission_gate, test_pw_buffer_region,
# test_handle_table, plus whatever the patch series adds under that label)
# and the headless Qt panel suite (test_panel, QT_QPA_PLATFORM=offscreen).
# Everything else (asio_probe*, asio_loopback, pw_*_probe, register_script)
# needs a running PipeWire daemon, a registered driver, or exercises install
# paths we do not ship; those run on real machines, not here. The stub
# satisfies the loader for test binaries carrying a libpipewire DT_NEEDED:
# the SDK's real .so cannot load on this glibc, and the unit scope never
# calls PipeWire at runtime (undefined pw_ symbols, if any, become no-ops).
teststub="$(mktemp -d)"
for t in build/tests/unit/test_*; do
    [ -f "$t" ] && [ -x "$t" ] || continue
    # || true: a statically-satisfied binary makes nm -D return nonzero, and
    # under pipefail that would kill the build from inside this generator.
    nm -D "$t" 2>/dev/null | awk '$1 == "U" && $2 ~ /^pw_/ { print "void " $2 "(void) {}" }' || true
done | sort -u > "$teststub/stub.c"
gcc -shared -fPIC -Wl,-soname,libpipewire-0.3.so.0 \
    -o "$teststub/libpipewire-0.3.so.0" "$teststub/stub.c"
LD_LIBRARY_PATH="$teststub" ctest --test-dir build -L '^unit$' \
    --no-tests=error --output-on-failure
if [ "$panel_state" = built ]; then
    LD_LIBRARY_PATH="$teststub" ctest --test-dir build -R '^test_panel$' \
        --no-tests=error --output-on-failure
fi
rm -rf "$teststub"

# Install by hand, not `cmake --install`: the four driver names stay copies
# (not upstream's symlinks) at the exact paths every release has shipped, and
# upstream's pipeasio-register does not ride along. kernelbase is linked by
# upstream's CMake itself (add_wine_dll LIBS, needed since 1.3.0 for the
# generation-based Stop's WaitOnAddress/WakeByAddressAll).
# Must link the host's PipeWire by soname, no SDK path baked in.
readelf -d build/pipeasio64.dll.so | grep -F 'Shared library: [libpipewire-0.3.so.0]' >/dev/null
if readelf -d build/pipeasio64.dll.so | grep -qE 'RPATH|RUNPATH'; then
    echo "!! pipeasio64.dll.so carries an rpath into the build container" >&2
    exit 1
fi
install -m644 build/pipeasio64.dll    "$PREFIX_ROOT/lib/wine/x86_64-windows/pipeasio64.dll"
install -m644 build/pipeasio64.dll.so "$PREFIX_ROOT/lib/wine/x86_64-unix/pipeasio64.dll.so"
# Wine resolves pipeasio64.dll to builtin name "pipeasio.dll" (from its spec file) and looks for the
# unix half under that name: install both names or LoadLibrary fails with STATUS_DLL_NOT_FOUND.
install -m644 build/pipeasio64.dll    "$PREFIX_ROOT/lib/wine/x86_64-windows/pipeasio.dll"
install -m644 build/pipeasio64.dll.so "$PREFIX_ROOT/lib/wine/x86_64-unix/pipeasio.dll.so"

if [ "$panel_state" = built ]; then
    # pipeasio-settings: the native Qt panel the Hardware Setup dialog points
    # at (issue #60). Links the container's Qt 6.2 by soname, so it runs
    # against any host Qt >= 6.2; a host without Qt6 gets a load error from
    # this one binary and nothing else is affected (install.sh checks and
    # says which package to add). src/config.c is compiled into the panel,
    # so it writes exactly what the driver reads.
    if readelf -d build/gui/pipeasio-settings | grep -qE 'RPATH|RUNPATH'; then
        echo "!! pipeasio-settings carries an rpath into the build container" >&2
        exit 1
    fi
    install -m755 build/gui/pipeasio-settings "$PREFIX_ROOT/bin/pipeasio-settings"
    install -D -m644 gui/pipeasio-settings.desktop \
        "$PREFIX_ROOT/share/applications/pipeasio-settings.desktop"
    install -D -m644 docs/icon.svg \
        "$PREFIX_ROOT/share/icons/hicolor/scalable/apps/pipeasio.svg"
fi

echo "== [5/8] strip + prune (dev files served their purpose in [4/8]; nothing below runs on user machines) =="
# Debug info is ~3/4 of every PE builtin and ~5/6 of the unix halves. Exports,
# resources, .rodata literals (the audit fingerprints) and the builtin signature
# all live outside the symtab; the relocation gate re-runs the stripped tree.
# .dll16/.tlb/.vxd etc. are not COFF and stay untouched.
find "$PREFIX_ROOT/lib/wine" \( -name '*.dll' -o -name '*.exe' -o -name '*.sys' \
    -o -name '*.drv' -o -name '*.cpl' -o -name '*.ocx' \) -exec llvm-strip --strip-all {} +
strip --strip-unneeded "$PREFIX_ROOT"/lib/wine/*-unix/*.so
for f in "$PREFIX_ROOT"/bin/*; do strip --strip-unneeded "$f" 2>/dev/null || true; done  # sh wrappers in bin/ are not ELF
rm -f "$PREFIX_ROOT"/lib/wine/*-windows/*.a
rm -rf "$PREFIX_ROOT/include" "$PREFIX_ROOT/share/man"
rm -f "$PREFIX_ROOT"/bin/widl "$PREFIX_ROOT"/bin/winebuild "$PREFIX_ROOT"/bin/winecpp \
      "$PREFIX_ROOT"/bin/winedump "$PREFIX_ROOT"/bin/wineg++ "$PREFIX_ROOT"/bin/winegcc \
      "$PREFIX_ROOT"/bin/winemaker "$PREFIX_ROOT"/bin/wmc "$PREFIX_ROOT"/bin/wrc \
      "$PREFIX_ROOT"/bin/function_grep.pl
# BUILD-INFO must hash the files as shipped, i.e. post-strip
bridge_pe_sha="$(sha256sum "$bridge_pe" | awk '{print $1}')"
bridge_unix_sha="$(sha256sum "$bridge_unix" | awk '{print $1}')"
portal_unix_sha="$(sha256sum "$portal_unix" | awk '{print $1}')"

pipeasio_pe="$PREFIX_ROOT/lib/wine/x86_64-windows/pipeasio64.dll"
pipeasio_unix="$PREFIX_ROOT/lib/wine/x86_64-unix/pipeasio64.dll.so"
test -s "$pipeasio_pe"
test -s "$pipeasio_unix"
pipeasio_pe_sha="$(sha256sum "$pipeasio_pe" | awk '{print $1}')"
pipeasio_unix_sha="$(sha256sum "$pipeasio_unix" | awk '{print $1}')"
echo "   PipeASIO: PE $pipeasio_pe_sha / Unix $pipeasio_unix_sha"

echo "== [6/8] package =="
# Stamp per-patch sha256s into the tree; build-audit.sh diffs this against patches/SERIES.sha256.
stack_stamp="$PREFIX_ROOT/ABLETON-WINE-PATCH-STACK.txt"
( cd "$SRC/patches" && sha256sum 00*.patch pipeasio/*.patch ) > "$stack_stamp"
stack_sha="$(sha256sum "$stack_stamp" | awk '{print $1}')"
build_info="$PREFIX_ROOT/ABLETON-WINE-BUILD-INFO.txt"
{
    echo "dist-version: $VERSION"
    echo "wine:         $("$PREFIX_ROOT/bin/wine" --version)"
    echo "base:         giang17/wine d2d1-dcomp-11.13 @ 5c23dd1c"
    echo "prefix:       $CONFIGURE_PREFIX (configure-time only; tarball is relocatable, see relocation gate)"
    echo "patches:      $((npatch + nasio))"     # wine series + pipeasio series
    echo "wine-patches: $npatch"
    echo "pipeasio-patches: $nasio"
    echo "patch-head:   $patch_head"
    echo "patch-stack:  $stack_sha"
    echo "pipeasio:     1.5.0"
    echo "pipewire-floor: 1.4.2 (upstream's build-time minimum; Ubuntu 24.04/Mint 22 ship 1.0.5, below it)"
    if [ "$panel_state" = built ]; then
        echo "pipeasio-settings: $(sha256sum "$PREFIX_ROOT/bin/pipeasio-settings" | awk '{print $1}') (Qt 6.2 link)"
    else
        echo "pipeasio-settings: skipped (no Qt6)"
    fi
    if [ "$panel_state" = built ]; then
        echo "pipeasio-tests: ctest unit scope + test_panel, passed in-container"
    else
        echo "pipeasio-tests: ctest unit scope passed in-container (panel test skipped)"
    fi
    echo "ntsync:       yes (vendored linux/ntsync.h $ntsync_hdr_sha)"
    echo "libusb-pe:    $bridge_pe_sha"
    echo "libusb-unix:  $bridge_unix_sha"
    echo "portal-unix:  $portal_unix_sha"
    echo "pipeasio-pe:  $pipeasio_pe_sha"
    echo "pipeasio-unix: $pipeasio_unix_sha"
    echo "built-on:     Ubuntu 22.04 (glibc 2.35)"
} > "$build_info"
cp "$build_info" "$OUT/BUILD-INFO-${VERSION}.txt"
cp "$build_info" "$OUT/BUILD-INFO.txt"
tarball="$OUT/${NAME}-${VERSION}.tar.zst"
# --long=27 (128 MiB window, zstd's default decode limit: no flags needed to unpack)
# lets the i386/x86_64 builtin pairs dedup against each other.
tar -C "$(dirname "$PREFIX_ROOT")" -c "$NAME" | zstd -T0 -19 --long=27 -q -f -o "$tarball"
( cd "$OUT" && sha256sum "$(basename "$tarball")" > "$(basename "$tarball").sha256" )

echo "== [7/8] relocation + registration gate: run the packaged tree from a random path =="
# Remove the configure-path symlink so Wine's compiled-in fallback can't mask a broken relative lookup.
rm -f "$CONFIGURE_PREFIX"
reloc="$(mktemp -d /tmp/reloc-gate.XXXXXX)"
tar -C "$reloc" -I zstd -xf "$tarball"
WINEPREFIX="$reloc/prefix" WINEDEBUG=-all \
    "$reloc/$NAME/bin/wine" cmd /c "echo relocation-ok" 2>/dev/null | grep -q relocation-ok
# Register PipeASIO through Live's load path; catches builtin-name mismatches presence checks miss.
# Registration only loads the DLL and writes registry keys, but dlopen of the
# unix half still needs libpipewire-0.3.so.0 to resolve. The SDK's .so targets
# a newer glibc than this container, so satisfy the loader with a stub that
# exports exactly the pw_ symbols the driver references.
pwstub="$(mktemp -d)"
nm -D "$reloc/$NAME/lib/wine/x86_64-unix/pipeasio64.dll.so" \
    | awk '$1 == "U" && $2 ~ /^pw_/ { print "void " $2 "(void) {}" }' > "$pwstub/stub.c"
gcc -shared -fPIC -Wl,-soname,libpipewire-0.3.so.0 -o "$pwstub/libpipewire-0.3.so.0" "$pwstub/stub.c"
WINEPREFIX="$reloc/prefix" WINEDEBUG=-all \
    LD_LIBRARY_PATH="$pwstub" \
    "$reloc/$NAME/bin/wine" regsvr32 pipeasio64.dll >/dev/null 2>&1
WINEPREFIX="$reloc/prefix" WINEDEBUG=-all \
    "$reloc/$NAME/bin/wine" reg query \
    'HKCR\CLSID\{2D3CA9E2-1193-4C5D-B5FD-38798F3DC074}\InprocServer32' >/dev/null 2>&1
WINEPREFIX="$reloc/prefix" "$reloc/$NAME/bin/wineserver" -k 2>/dev/null || true
WINEPREFIX="$reloc/prefix" "$reloc/$NAME/bin/wineserver" -w 2>/dev/null || true
rm -rf "$reloc"
echo "   relocation + registration gate passed (cmd.exe ran, PipeASIO registered)"

echo "== [8/8] build audit: every patch verified against the shipped tarball =="
bash "$SRC/scripts/build-audit.sh" "$tarball"

echo
echo "OK: $(basename "$tarball") ($(du -h "$tarball" | cut -f1))"
