{
  stdenv,
  lib,
  removeReferencesTo,
  wine,
  pipeasio,
  cabextract,
  unzip,
  # pipeasioSettings: pin PipeASIO config.ini keys from nix, e.g.
  #   ableton-wine.override { pipeasioSettings = { buffer_size = 256; inputs = 8; }; }
  # The driver's only config surface is ~/.config/pipeasio/config.ini (1.2.2
  # reads no env vars besides PIPEASIO_DEBUG), so the launch shim pins exactly
  # the given keys on every start and leaves every other key to the user and
  # the PipeASIO Qt panel. A pinned key therefore overrides later hand/panel
  # edits at each launch (one notice per re-pin goes to stderr).
  # Keys are the driver's own names, values checked against its validate():
  #   inputs, outputs        int, 0..256 (hardware channel counts)
  #   buffer_size            int, power of two, 16..8192 frames — match the
  #                          host's PipeWire quantum
  #   sample_rate            int Hz, 0 = follow the PipeWire graph
  #   fixed_buffer_size, auto_connect, follow_device_clock   bool
  #   output_device, input_device, node_name                 string
  pipeasioSettings ? { },
}:

let
  s = pipeasioSettings;
  validKeys = [
    "inputs"
    "outputs"
    "buffer_size"
    "fixed_buffer_size"
    "sample_rate"
    "auto_connect"
    "follow_device_clock"
    "output_device"
    "input_device"
    "node_name"
  ];
  unknownKeys = lib.filter (k: !(lib.elem k validKeys)) (lib.attrNames s);
  intIn = k: lo: hi: !(s ? ${k}) || (lib.isInt s.${k} && lo <= s.${k} && s.${k} <= hi);
  isPow2 = n: lib.isInt n && n > 0 && builtins.bitAnd n (n - 1) == 0;

  renderValue = v: if lib.isBool v then lib.boolToString v else toString v;

  # Fresh-file seed: the same defaults setup-prefix.sh writes, plus the pins.
  # On an existing file only the pinned keys are touched (see the shim).
  seed = {
    inputs = 2;
    outputs = 2;
    buffer_size = 256;
    fixed_buffer_size = true;
    auto_connect = true;
  }
  // s;
  seedLines = [ "[pipeasio]" ] ++ lib.mapAttrsToList (k: v: "${k} = ${renderValue v}") seed;
in

# Out-of-range pins fail at eval time with the driver's real limits; the
# driver itself would only silently reset them to defaults (validate()).
assert lib.assertMsg (unknownKeys == [ ]) ''
  ableton-wine: unknown pipeasioSettings key(s): ${toString unknownKeys}
  valid keys: ${toString validKeys}'';
assert lib.assertMsg (intIn "inputs" 0 256 && intIn "outputs" 0 256)
  "ableton-wine: pipeasioSettings.inputs/outputs must be integers in 0..256";
assert lib.assertMsg (!(s ? buffer_size) || (isPow2 s.buffer_size && 16 <= s.buffer_size && s.buffer_size <= 8192))
  "ableton-wine: pipeasioSettings.buffer_size must be a power of two in 16..8192";
assert lib.assertMsg (!(s ? sample_rate) || (lib.isInt s.sample_rate && s.sample_rate >= 0))
  "ableton-wine: pipeasioSettings.sample_rate must be an integer >= 0 (0 = follow the graph)";
assert lib.assertMsg
  (lib.all (k: !(s ? ${k}) || lib.isBool s.${k}) [ "fixed_buffer_size" "auto_connect" "follow_device_clock" ])
  "ableton-wine: pipeasioSettings.fixed_buffer_size/auto_connect/follow_device_clock must be booleans";
assert lib.assertMsg
  (lib.all (k: !(s ? ${k}) || (lib.isString s.${k} && !lib.hasInfix "\n" s.${k})) [
    "output_device"
    "input_device"
    "node_name"
  ])
  "ableton-wine: pipeasioSettings.output_device/input_device/node_name must be single-line strings";

stdenv.mkDerivation {
  pname = "ableton-wine";
  inherit (wine) version;

  dontUnpack = true;

  nativeBuildInputs = [
    removeReferencesTo
  ];

  installPhase = ''
        runHook preInstall

        # -- Wine tree + PipeASIO --
        cp -a ${wine} $out
        chmod -R u+w $out
        # Both names: Wine resolves pipeasio64.dll to builtin "pipeasio.dll"
        # (from its spec) and looks for the unix half under that name.
        for pair in \
          pipeasio64.dll:x86_64-windows \
          pipeasio64.dll.so:x86_64-unix \
          pipeasio.dll:x86_64-windows \
          pipeasio.dll.so:x86_64-unix; do
          file=''${pair%%:*}
          dir=''${pair##*:}
          cp -f ${pipeasio}/lib/wine/$dir/$file $out/lib/wine/$dir/
        done
        # Prune the winegcc toolchain and headers now that pipeasio has used
        # them (wine.nix already dropped the other dev tools).
        rm -rf $out/include $out/share/man
        rm -f $out/bin/winegcc $out/bin/wineg++ $out/bin/winebuild

        # The copied binaries embed the donor wine's store path (configure
        # --prefix) as dormant self-location fallbacks — runtime resolution goes
        # through /proc/self/exe (see the wrapper below). Left in place they drag
        # the full donor tree into this closure (~2x size); scrub them.
        # disallowedReferences below turns any new embedding into a build failure.
        remove-references-to -t ${wine} \
          $out/bin/.wine-wrapped $out/bin/wineserver \
          $out/lib/wine/x86_64-unix/ntdll.so

        # cp -a preserved bin/wine, which execs the ORIGINAL wine store path;
        # wine self-locates its builtin dll dir from /proc/self/exe, so the
        # pipeasio builtins copied above would never be found (regsvr32 fails
        # with STATUS_DLL_NOT_FOUND). Regenerate the wrapper to exec THIS tree.
        # PipeASIO needs no library path help: its unix half carries a RUNPATH
        # to nixpkgs' libpipewire (see nix/pipeasio.nix).
        cat > $out/bin/wine <<WRAPWRP
    #!/bin/sh
    export LD_LIBRARY_PATH="${wine.libPath}\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
    # -a "\$0": apploader symlinks (wineboot, regsvr32, ...) need argv[0] intact.
    exec -a "\$0" $out/bin/.wine-wrapped "\$@"
    WRAPWRP
        chmod +x $out/bin/wine

        # -- Launcher --
        mkdir -p $out/bin $out/libexec
        # The stock launcher, unmodified: it finds its detect-scale/detect-theme
        # libs and setsyscolors.exe through its own $WINE_ROOT/share fallbacks.
        install -m755 ${../scripts/ableton-live} $out/libexec/ableton-live
        # bin/ableton-live: point the stock launcher at this tree and exec it.
        # Quoted heredocs ('SHIM'): nothing shell-expands at build time; the
        # @out@ token is substituted afterwards (and gated in installCheck).
        # Nix interpolation still applies while this installPhase string is
        # built, so runtime shell ''${...} is written with the '''' escape.
        cat > $out/bin/ableton-live <<'SHIM'
    #!/bin/sh
    # Generated by nix/ableton-wine.nix. pipeasioSettings pins are appended
    # below when configured: ableton-wine.override { pipeasioSettings = { ... }; }
    export ABLETON_WINE_ROOT="''${ABLETON_WINE_ROOT:-@out@}"
    export PATH="@out@/bin:$PATH"
    SHIM
        ${lib.optionalString (s != { }) ''
              cat >> $out/bin/ableton-live <<'SHIM'
          # Flake-pinned PipeASIO settings. config.ini is the driver's only config
          # surface (1.2.2 reads no env vars besides PIPEASIO_DEBUG); pin exactly
          # the configured keys, leave the rest to the user / the Qt panel.
          ini="''${XDG_CONFIG_HOME:-$HOME/.config}/pipeasio/config.ini"
          if [ ! -s "$ini" ]; then
              mkdir -p "''${ini%/*}"
              printf '%s\n' ${lib.escapeShellArgs seedLines} > "$ini"
          fi
          SHIM
              cat >> $out/bin/ableton-live <<'SHIM'
          ${lib.concatStrings (
            lib.mapAttrsToList (
              k: v:
              let
                val = renderValue v;
              in
              # Key names come from the validKeys whitelist (plain identifiers, no
              # regex metacharacters); values only ever appear shell-quoted. The
              # pin is delete + append — never a sed replacement, whose escaping
              # rules are where arbitrary strings go wrong. Appending lands inside
              # [pipeasio]: it is the only section the file ever has (the driver
              # even treats keys before any header as belonging to it), and the
              # driver takes the LAST occurrence of a key — which is also why the
              # current-value probe below reads the last one.
              ''
                if [ "$(sed -n 's/^[[:space:]]*${k}[[:space:]]*=[[:space:]]*//p' "$ini" | tail -n 1)" != ${lib.escapeShellArg val} ]; then
                    echo "ableton-live: pinning PipeASIO ${k} (nix pipeasioSettings)" >&2
                    sed -i '/^[[:space:]]*${k}[[:space:]]*=/d' "$ini"
                    printf '%s\n' ${lib.escapeShellArg "${k} = ${val}"} >> "$ini"
                fi
              ''
            ) s
          )}SHIM
        ''}
        cat >> $out/bin/ableton-live <<'SHIM'
    exec "@out@/libexec/ableton-live" "$@"
    SHIM
        chmod +x $out/bin/ableton-live
        substituteInPlace $out/bin/ableton-live --replace-fail '@out@' "$out"

        # -- Supporting scripts (match original repo layout: scripts/ + vendor/) --
        mkdir -p $out/share/ableton-wine/scripts
        mkdir -p $out/share/ableton-wine/vendor
        install -m755 ${../scripts/detect-scale.sh}      $out/share/ableton-wine/scripts/detect-scale.sh
        install -m755 ${../scripts/detect-theme.sh}      $out/share/ableton-wine/scripts/detect-theme.sh
        install -m755 ${../scripts/setup-prefix.sh}      $out/share/ableton-wine/scripts/setup-prefix.sh
        install -m755 ${../scripts/check-live-audio.sh}  $out/share/ableton-wine/scripts/check-live-audio.sh
        install -m755 ${../scripts/check-ntsync.sh}      $out/share/ableton-wine/scripts/check-ntsync.sh
        # Mid-session theme repaint helper (PE binary, run through this wine);
        # the tarball flow stages it in ~/.local/share/ableton-wine.
        install -m644 ${../tools/setsyscolors.exe}       $out/share/ableton-wine/scripts/setsyscolors.exe
        # Host-policy helpers (both standalone: no wine, no repo paths beyond
        # the Link note installed below).
        install -m755 ${../scripts/setup-realtime.sh}    $out/share/ableton-wine/scripts/setup-realtime.sh
        install -m755 ${../scripts/setup-link.sh}        $out/share/ableton-wine/scripts/setup-link.sh
        # setup-link.sh points at the jack_link build/unit instructions in
        # notes/ — ship that one note so the pointer resolves from the store.
        mkdir -p $out/share/ableton-wine/notes
        install -m644 ${../notes/ABLETON-WINE-LINK.md}   $out/share/ableton-wine/notes/ABLETON-WINE-LINK.md
        # install.sh / uninstall.sh are tarball-install tools; under Nix the
        # store path is immutable and GC'd by nix, so they are not shipped.

        # Patch default WINE_ROOT (and the launcher path) in scripts that use them.
        for script in setup-prefix.sh check-live-audio.sh check-ntsync.sh; do
          substituteInPlace $out/share/ableton-wine/scripts/$script \
            --replace-fail '$HOME/.local/opt/wine-d2d1-nspa-11.11' "$out"
        done
        substituteInPlace $out/share/ableton-wine/scripts/check-live-audio.sh \
          --replace-fail '$HOME/.local/bin/ableton-live' "$out/bin/ableton-live"

        # Vendored winetricks (pinned, tested with this patch series) — not
        # nixpkgs' — so the nix package exercises the same setup path as the
        # tarball install. The winetricks download cache stays out of the store:
        # winetricks writes into its cache dir, and the store is read-only.
        install -m755 ${../vendor/winetricks}       $out/share/ableton-wine/vendor/winetricks
        # cabextract: winetricks corefonts; unzip: setup-prefix's Ableton Live
        # step (unpacks the user's ableton_live*.zip from ~/Proprietary).
        # Symlinks — the closure is identical either way, no need to copy.
        ln -s ${cabextract}/bin/cabextract   $out/bin/cabextract
        ln -s ${lib.getBin unzip}/bin/unzip  $out/bin/unzip

        # -- Desktop entries (manual install; see README) --
        mkdir -p $out/share/ableton-wine/desktop
        cp ${../desktop/ableton-live.desktop.in} \
           $out/share/ableton-wine/desktop/ableton-live.desktop.in
        cp ${../desktop/wine-protocol-ableton.desktop.in} \
           $out/share/ableton-wine/desktop/wine-protocol-ableton.desktop.in

        runHook postInstall
  '';

  # Closure gate: the donor wine tree must not leak into this output's
  # references (see the remove-references-to scrub in installPhase).
  disallowedReferences = [ wine ];

  # Gate: the packaged wine must find, load and register its builtin PipeASIO
  # through Live's load path (regsvr32 dlopens the unix half, so the
  # libpipewire RUNPATH is exercised too). The wrapper-exec failure mode
  # (wine self-locating in the original wine store path) shipped once — the
  # CLSID query catches builtin-name mismatches that presence checks miss.
  doInstallCheck = true;
  installCheckPhase = ''
    grep -qF "$out/bin/.wine-wrapped" $out/bin/wine \
      || { echo "bin/wine wrapper does not exec this tree"; exit 1; }
    # Shim gate: valid shell, no unsubstituted tokens, execs the launcher.
    ${stdenv.shell} -n $out/bin/ableton-live || { echo "launch shim has a syntax error"; exit 1; }
    if grep -qF '@out@' $out/bin/ableton-live; then echo "launch shim has unsubstituted @out@ tokens"; exit 1; fi
    grep -qF "exec \"$out/libexec/ableton-live\"" $out/bin/ableton-live \
      || { echo "launch shim does not exec the launcher"; exit 1; }
    echo "PipeASIO registration gate"
    gate=$(mktemp -d)
    export WINEPREFIX=$gate/prefix WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
    # Bare symlink invocations on purpose: setup-prefix.sh calls "wineboot -u"
    # through PATH, which exercises the apploader argv[0] path (a plain
    # "exec" wrapper without -a "$0" breaks exactly this).
    $out/bin/wineboot -u || { echo "wineboot failed"; exit 1; }
    $out/bin/wineserver -w
    $out/bin/regsvr32 /s pipeasio64.dll \
      || { echo "regsvr32 /s pipeasio64.dll failed"; exit 1; }
    $out/bin/wine reg query 'HKCR\CLSID\{2D3CA9E2-1193-4C5D-B5FD-38798F3DC074}\InprocServer32' >/dev/null \
      || { echo "PipeASIO CLSID not registered"; exit 1; }
    $out/bin/wineserver -k 2>/dev/null || true
    echo "  pipeasio registration gate passed"
  '';

  meta = {
    description = "Ableton Live runtime — patched Wine 11.11 + PipeASIO + launcher";
    mainProgram = "ableton-live"; # lets `nix run` work on .override variants too
    platforms = [ "x86_64-linux" ];
    license = with lib.licenses; [ lgpl21Plus gpl3Plus ]; # wine LGPL-2.1+, pipeasio GPL-3.0+
  };
}
