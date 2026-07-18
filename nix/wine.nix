{
  stdenv,
  lib,
  zstd,
  llvmPackages,
  # Build tools
  flex,
  bison,
  perl,
  gettext,
  pkg-config,
  git,
  python3,
  # X11 / GL / Vulkan
  libx11,
  libxext,
  libxrandr,
  libxrender,
  libxi,
  libxfixes,
  libxcursor,
  libxcomposite,
  libxinerama,
  libxxf86vm,
  libxkbcommon,
  libGL,
  libGLU,
  vulkan-loader,
  # Fonts
  freetype,
  fontconfig,
  # Audio
  alsa-lib,
  libpulseaudio,
  # Network / USB / system
  gnutls,
  libusb1,
  udev,
  dbus,
  # Source inputs
  wineSrc,
  patchesDir,
  ntsyncUapi,
  clangUnwrapped ? llvmPackages.clang-unwrapped, # PE cross-compiler: Nix wrapper breaks -target
}:

stdenv.mkDerivation rec {
  pname = "wine-d2d1-nspa";
  version = "11.11";

  src = wineSrc;

  nativeBuildInputs = [
    zstd
    # LLVM for PE (Windows) cross-compilation: WoW64 needs clang/lld
    llvmPackages.llvm # llvm-strip, llvm-dlltool, llvm-ar, llvm-ranlib, llvm-readobj
    llvmPackages.clang # clang, clang++ (PE compiler — both 32-bit and 64-bit targets)
    llvmPackages.lld # lld (PE linker)
    # Standard build tools
    flex
    bison
    perl
    gettext
    pkg-config
    git
    python3
  ];

  buildInputs = [
    # X11 + GL
    libx11
    libxext
    libxrandr
    libxrender
    libxi
    libxfixes
    libxcursor
    libxcomposite
    libxinerama
    libxxf86vm
    libxkbcommon
    libGL
    libGLU
    vulkan-loader
    # Fonts
    freetype
    fontconfig
    # Audio
    alsa-lib
    libpulseaudio
    # Network / USB / system
    gnutls
    libusb1
    udev
    dbus
  ];

  # The tarball is zstd-compressed with no top-level directory.
  unpackPhase = ''
    runHook preUnpack
    ${zstd}/bin/zstd -dc --long=27 $src | tar -x
    runHook postUnpack
  '';
  sourceRoot = ".";

  # Apply the wine patch series, driven by SERIES.sha256 (the pinned-series
  # manifest): checksums must match, every on-disk wine patch must be listed,
  # and an empty series fails the build — a silently unpatched wine would
  # still pass the ntsync/relocation gates below.
  # Patches are git format-patch style (Subject: + diff --git) without
  # From:/Date: headers — patch -p1 handles them directly.
  postUnpack = ''
    echo "Applying patch series from ${patchesDir} (pinned by SERIES.sha256)"
    series=$(grep -E '^[0-9a-f]{64}  [0-9]{4}-.*\.patch$' ${patchesDir}/SERIES.sha256 | awk '{print $2}')
    [ -n "$series" ] || { echo "!! SERIES.sha256 lists no wine patches" >&2; exit 1; }
    (cd ${patchesDir} && grep -E '^[0-9a-f]{64}  [0-9]{4}-.*\.patch$' SERIES.sha256 | sha256sum -c --quiet) \
      || { echo "!! patch series does not match SERIES.sha256" >&2; exit 1; }
    for f in ${patchesDir}/[0-9]*.patch; do
      echo "$series" | grep -qx "$(basename $f)" \
        || { echo "!! $(basename $f) on disk but not in SERIES.sha256 — update the manifest" >&2; exit 1; }
    done
    n=0
    for p in $series; do
      echo "  $p"
      patch -p1 < ${patchesDir}/$p
      n=$((n+1))
    done
    echo "Applied $n wine patches"
  '';

  # The Nix clang wrapper adds --no-default-config and host-target flags that
  # prevent `clang -target i686-windows` from working. Wine's configure needs
  # a clean clang to cross-compile PE (Windows) binaries for WoW64.
  # Create target-prefixed wrappers around clang-unwrapped so configure finds
  # them first (it probes i686-w64-mingw32-clang before bare clang).
  preConfigure = ''
        mkdir -p "$TMPDIR/wine-pe-tools"
        for target in i686-w64-mingw32 x86_64-w64-mingw32; do
          cat > "$TMPDIR/wine-pe-tools/$target-clang" <<'WRAPPER'
    #!/bin/sh
    exec ${clangUnwrapped}/bin/clang "$@"
    WRAPPER
          chmod +x "$TMPDIR/wine-pe-tools/$target-clang"
        done
        export PATH="$TMPDIR/wine-pe-tools:$PATH"
  '';

  # WoW64: build both 32-bit and 64-bit PE sides with clang.
  # Unix side built with stdenv's gcc. --disable-tests saves ~40% build time.
  configureFlags = [
    "--prefix=${placeholder "out"}"
    "--enable-archs=i386,x86_64"
    "--disable-tests"
  ];

  # ntsync: configure silently drops it without linux/ntsync.h; every NT sync
  # wait then becomes a wineserver round trip (~1.3 cores with Live running).
  # The vendored UAPI header pins it regardless of nixpkgs' kernel headers;
  # the dir holds ONLY linux/ntsync.h, so system headers stay authoritative
  # for everything else. Runtime needs /dev/ntsync (kernel 6.14+, CONFIG_NTSYNC).
  CPPFLAGS = "-I${ntsyncUapi}";
  postConfigure = ''
    grep -q '^#define HAVE_LINUX_NTSYNC_H 1' include/config.h \
      || { echo "!! HAVE_LINUX_NTSYNC_H not set; linux/ntsync.h not seen at configure time" >&2; exit 1; }
  '';

  enableParallelBuilding = true;
  # Strip PE files with llvm-strip (standard strip can't touch COFF),
  # then strip ELF .so files. Prune dev files that have no runtime role.
  dontStrip = true;
  # Wine dlopen's many system libs (freetype, X11, GL, etc.) at runtime.
  # Nix's shrink-rpath removes paths without DT_NEEDED — we need them all.
  dontPatchELF = true;

  postInstall = ''
        # ntsync gate — BEFORE stripping (ntdll's client half has no string
        # literals, only symbol names; wineserver owns /dev/ntsync). Check BOTH
        # halves: the 2026-07-12 container build lost only the wineserver one
        # (notes/ABLETON-WINE-NTSYNC-REGRESSION.md).
        for f in bin/wineserver lib/wine/x86_64-unix/ntdll.so; do
          n=$(strings $out/$f | grep -c ntsync || true)
          [ "$n" -gt 0 ] || { echo "!! no ntsync in $f; waits would fall back to server round trips" >&2; exit 1; }
        done
        echo "ntsync gate passed (wineserver + ntdll)"

        echo "Stripping PE builtins"
        find $out/lib/wine \( -name '*.dll' -o -name '*.exe' -o -name '*.sys' \
          -o -name '*.drv' -o -name '*.cpl' -o -name '*.ocx' \) \
          -exec ${llvmPackages.llvm}/bin/llvm-strip --strip-all {} + 2>/dev/null || true

        echo "Stripping Unix .so files"
        find $out/lib/wine/*-unix -name '*.so' -exec ${stdenv.cc.bintools.targetPrefix}strip --strip-unneeded {} + 2>/dev/null || true
        for f in $out/bin/*; do
          ${stdenv.cc.bintools.targetPrefix}strip --strip-unneeded "$f" 2>/dev/null || true
        done

        echo "Pruning dev-only files"
        rm -f $out/lib/wine/*-windows/*.a
        rm -f $out/bin/widl $out/bin/winecpp \
              $out/bin/winedump $out/bin/winemaker $out/bin/wmc $out/bin/wrc \
              $out/bin/function_grep.pl

        # Wine dlopen's system libraries (freetype, X11, GL, ALSA, etc.) at
        # runtime. Nix's RPATH only covers DT_NEEDED — dlopen needs LD_LIBRARY_PATH.
        mv $out/bin/wine $out/bin/.wine-wrapped
        cat > $out/bin/wine <<WRAPWRP
    #!/bin/sh
    export LD_LIBRARY_PATH="${passthru.libPath}\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
    # -a "\$0": the apploader symlinks (wineboot, regsvr32, ...) point here and
    # the wine loader picks the app to run from argv[0]; losing it makes
    # "wineboot -u" try to ShellExecute "-u".
    exec -a "\$0" $out/bin/.wine-wrapped "\$@"
    WRAPWRP
        chmod +x $out/bin/wine
  '';

  # Runtime dlopen path for downstream wrappers (ableton-wine regenerates
  # bin/wine against its own tree using this same list).
  passthru.libPath = lib.makeLibraryPath buildInputs;

  # Build-time smoke gate: the installed tree must run wine end to end
  # (prefix creation, builtin load). Note: bin/wine execs $out by absolute
  # path, so this does not prove path-relocatability — only a working tree.
  doInstallCheck = true;
  installCheckPhase = ''
    echo "Relocation gate: verify wine runs from its installed path"
    reloc=$(mktemp -d)
    cp -a $out $reloc/wine
    WINEPREFIX=$reloc/prefix WINEDEBUG=-all \
      $reloc/wine/bin/wine cmd /c "echo relocation-ok" 2>/dev/null | grep -q relocation-ok
    echo "  relocation gate passed"
    rm -rf $reloc
  '';

  meta = with lib; {
    description = "Wine 11.11 with D2D1-DCOMP + NSPA fixes for Ableton Live 12";
    platforms = [ "x86_64-linux" ];
    license = licenses.lgpl21Plus;
  };
}
