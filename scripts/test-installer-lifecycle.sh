#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ableton-installer-test.XXXXXX")"
# Checks that expect an installer run to succeed redirect its diagnostics into
# the per-case log, so set -e ends the suite on an unexpected non-zero exit
# with no failure line, leaving make's exit code as the only evidence.  Report
# the case and replay what the run wrote.  The shell can exit while the failing
# command's redirections are still applied, so this reports on a saved copy of
# the suite's own stderr rather than into the log it is replaying.
exec {suite_stderr}>&2
reported=0
cleanup()
{
    local code=$?
    if [ "$code" -ne 0 ] && [ "$reported" -eq 0 ]; then
        [ -z "${base:-}" ] || [ ! -s "$base/err" ] \
            || sed -n '1,40p' "$base/err" >&"$suite_stderr"
        printf 'not ok - a command exited %d unexpectedly in %s\n' \
            "$code" "$(basename "${base:-unknown-case}")" >&"$suite_stderr"
    fi
    [ "${ABLETON_KEEP_TEST_WORK:-0}" -eq 0 ] || { printf 'kept test work: %s\n' "$work" >&2; return; }
    rm -rf -- "$work"
}
trap cleanup EXIT
pass=0

ok()
{
    pass=$((pass + 1))
    printf 'ok - %s\n' "$1"
}

fail()
{
    reported=1
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

# The suite installs real build artifacts: the exact VERSION runtime from the
# runtime-plan check onwards and dist/ableton-linkd from the link-prestate
# check.  A checkout can update the tracked runtime checksum while retaining
# an ignored, now-stale tarball.  Validate the pair here because its first use
# redirects the diagnostic to a temporary log and set -e would otherwise end
# the suite without a failure line or summary.
. "$here/lib/config.sh"
prerequisite_failed=0
version="$(sed -n '1p' "$root/VERSION")"
runtime="$root/dist/$ABLETON_RUNTIME_NAME-$version.tar.zst"
runtime_checksum="$runtime.sha256"
if [ ! -f "$runtime" ]; then
    echo "!! missing build artifact: dist/$(basename "$runtime")" >&2
    prerequisite_failed=1
elif [ ! -s "$runtime_checksum" ]; then
    echo "!! missing build artifact: dist/$(basename "$runtime_checksum")" >&2
    prerequisite_failed=1
elif ! ( cd "$root/dist" && sha256sum -c --quiet "$(basename "$runtime_checksum")" ) \
        >/dev/null 2>&1; then
    echo "!! invalid build artifact: dist/$(basename "$runtime") does not match its checksum" >&2
    prerequisite_failed=1
fi
[ -f "$root/dist/ableton-linkd" ] || [ -f "$root/bin/ableton-linkd" ] || {
    echo "!! missing build artifact: dist/ableton-linkd" >&2
    prerequisite_failed=1
}
if [ "$prerequisite_failed" -eq 1 ]; then
    echo "!! run ./build.sh first" >&2
    fail "prerequisite build artifacts are valid"
fi

new_env()
{
    local name="$1"
    local base="$work/$name"
    mkdir -p -- "$base/home" "$base/tmp"
    printf '%s\n' "$base"
}

run_isolated()
{
    local base="$1"; shift
    env HOME="$base/home" XDG_CONFIG_HOME="$base/config" XDG_DATA_HOME="$base/data" \
        XDG_STATE_HOME="$base/state" XDG_CACHE_HOME="$base/cache" \
        XDG_RUNTIME_DIR="$base/run" TMPDIR="$base/tmp" "$@"
}

base="$(new_env help)"
run_isolated "$base" bash "$here/installer.sh" --help > "$base/out"
grep -q 'runtime install' "$base/out" || fail "help exposes subcommands"
ok "help exposes subcommands"

base="$(new_env live11-repair)"
max_settings="$base/prefix/drive_c/users/test/AppData/Roaming/Cycling '74/Max 8/Settings"
mkdir -p -- "$max_settings"
printf 'WINE REGISTRY Version 2\n' > "$base/prefix/system.reg"
printf 'format=1\nprefix=%s\n' "$base/prefix" > "$base/prefix/.ableton-linux-prefix"
printf 'stale Max preferences\n' > "$max_settings/maxpreferences.maxpref"
run_isolated "$base" bash "$here/installer.sh" prefix repair-live11 \
    --prefix "$base/prefix" >"$base/out" 2>"$base/err" \
    || fail "public Live 11 repair command failed"
if [ -e "$max_settings/maxpreferences.maxpref" ] \
   || ! compgen -G "$max_settings/maxpreferences.maxpref.bak-*" >/dev/null; then
    fail "public Live 11 repair did not move stale preferences aside"
fi
grep -qF 'Max preferences moved aside' "$base/out" \
    || fail "public Live 11 repair did not report its result"
[ ! -e "$base/state" ] \
    || fail "public Live 11 repair created persistent state solely to lock"
ok "public Live 11 repair honors the selected prefix without Wine or PipeWire"

base="$(new_env xdg-parent-symlinks)"
mkdir -p -- "$base/real-config" "$base/real-state"
ln -s -- "$base/real-config" "$base/config-link"
ln -s -- "$base/real-state" "$base/state-link"
# shellcheck disable=SC2016
env HOME="$base/home" XDG_CONFIG_HOME="$base/config-link" \
    XDG_STATE_HOME="$base/state-link" XDG_DATA_HOME="$base/data" \
    XDG_CACHE_HOME="$base/cache" bash -c '
        set -euo pipefail
        . "$1/lib/config.sh"
        ableton_config_init
        ableton_write_config
        ableton_mark_state_home
    ' _ "$here"
[ -L "$base/config-link" ] && [ -L "$base/state-link" ] \
    && [ -f "$base/real-config/ableton-wine/config" ] \
    && [ -f "$base/real-state/ableton-wine/.ableton-linux-state" ] \
    || fail "resolved XDG roots changed their user-owned symlink projections"
ok "resolved XDG roots use real target directories without replacing parent symlinks"

# make-installer's own [5/5] self-check runs --help, which returns before the
# delegation, so only this case guards the header's exit path.
base="$(new_env run-header)"
kit="$base/kit"
mkdir -p "$kit/scripts"
printf '#!/bin/sh\nexit "${STUB_EXIT:-0}"\n' > "$kit/scripts/installer.sh"
tar -cf "$base/payload.tar" -C "$kit" .
sed -e 's/@VERSION@/suite-check/g' \
    -e "s/@PAYLOAD_SHA@/$(sha256sum "$base/payload.tar" | awk '{print $1}')/g" \
    "$here/setup-run-header.sh" > "$base/kit.run"
cat "$base/payload.tar" >> "$base/kit.run"
run_isolated "$base" env STUB_EXIT=0 sh "$base/kit.run" >"$base/out" 2>"$base/err" \
    || fail "a successful delegated install exits zero through the .run header"
status=0
run_isolated "$base" env STUB_EXIT=42 sh "$base/kit.run" >>"$base/out" 2>>"$base/err" || status=$?
[ "$status" -eq 42 ] || fail "a delegated install failure code passes through the .run header"
! find "$base/tmp" -mindepth 1 -maxdepth 1 -name 'ableton-installer.*' 2>/dev/null | grep -q . \
    || fail "the .run header removes its work directory"
ok "the .run header propagates the delegated installer exit code"

base="$(new_env noninteractive)"
if run_isolated "$base" bash "$here/installer.sh" >"$base/out" 2>"$base/err"; then
    fail "noninteractive install requires an explicit payload"
fi
grep -q -- '--live-installer FILE or --skip-live-install' "$base/err" || fail "noninteractive failure explains payload policy"
[ ! -e "$base/config" ] && [ ! -e "$base/data" ] && [ ! -e "$base/state" ] || fail "failed parse is mutation-free"
ok "noninteractive payload failure is mutation-free"

base="$(new_env conflict)"
if run_isolated "$base" bash "$here/installer.sh" install --no-link --link=off --skip-live-install >"$base/out" 2>"$base/err"; then
    fail "conflicting Link options fail"
fi
grep -q 'conflicts' "$base/err" || fail "conflict is reported"
ok "conflicting compatibility and current options fail during parsing"

base="$(new_env parser-model)"
if run_isolated "$base" bash "$here/installer.sh" install --skip-live-install \
    --live-installer "$base/payload.exe" --prefix "$base/one" --prefix "$base/two" \
    >"$base/out" 2>"$base/err"; then
    fail "duplicate immutable options are accepted"
fi
[ ! -e "$base/config" ] && [ ! -e "$base/state" ] || fail "duplicate-option failure mutates state"
run_isolated "$base" bash "$here/installer.sh" --prefix --uninstall --dry-run \
    >"$base/legacy.out" 2>"$base/legacy.err"
grep -q 'delete validated prefix' "$base/legacy.out" \
    || fail "legacy uninstall prefix alias depends on argument order"
ok "immutable options reject duplicates and legacy parsing is order-independent"

base="$(new_env runtime-plan)"
run_isolated "$base" bash "$here/installer.sh" --runtime-only --runtime-root "$base/runtime" --dry-run >"$base/out" 2>"$base/err"
grep -q 'replace runtime tree atomically' "$base/out" || fail "runtime plan contains runtime"
! grep -q 'write launcher:' "$base/out" || fail "runtime plan excludes integration"
! grep -q 'write Link binary:' "$base/out" || fail "runtime plan excludes Link"
[ ! -e "$base/runtime" ] && [ ! -e "$base/config" ] && [ ! -e "$base/state" ] || fail "runtime plan mutates no target"
ok "runtime-only plan contains only the runtime component"

base="$(new_env runtime-install)"
if run_isolated "$base" bash "$here/installer.sh" runtime install \
    --runtime-root "$base/runtime" --yes >"$base/out" 2>"$base/err"; then
    [ -x "$base/runtime/bin/wine" ] && [ -f "$base/runtime/.ableton-linux-runtime" ] \
        || fail "runtime install promotes a marked runtime"
    [ ! -e "$base/config" ] && [ ! -e "$base/data" ] && [ ! -e "$base/state" ] \
        && [ ! -e "$base/cache" ] && [ ! -e "$base/prefix" ] \
        || fail "runtime install writes outside the selected runtime root"
    ok "runtime install writes only the runtime tree"
elif grep -Eq 'PipeWire is unavailable|PipeWire compatibility cannot be checked' "$base/err"; then
    [ ! -e "$base/runtime" ] && [ ! -e "$base/config" ] && [ ! -e "$base/state" ] \
        || fail "failed PipeWire gate mutated runtime-install targets"
    ok "runtime install refuses safely when its native PipeWire probe cannot connect"
else
    sed -n '1,80p' "$base/err" >&2
    fail "runtime install failed for an unrelated reason"
fi

base="$(new_env runtime-conflict)"
if run_isolated "$base" bash "$here/installer.sh" --runtime-only --no-link \
    --runtime-root "$base/runtime" --dry-run >"$base/out" 2>"$base/err"; then
    fail "runtime mode rejects a Link policy"
fi
[ ! -e "$base/runtime" ] && [ ! -e "$base/config" ] && [ ! -e "$base/state" ] \
    || fail "runtime option conflict mutates no state"
ok "runtime-only rejects unrelated Link options before mutation"

base="$(new_env compat-plan)"
run_isolated "$base" bash "$here/installer.sh" --no-launch --dry-run >"$base/out" 2>"$base/err"
grep -q 'write launcher:' "$base/out" || fail "no-launch still means skip Live payload only"
grep -q 'final Link policy: off' "$base/out" || fail "no-launch defaults Link off"
! grep -Eq 'write Link binary:|write Link controller/setup/unit assets:' "$base/out" \
    || fail "no-launch unexpectedly stages Link assets"
! grep -Eq 'write ownership-marked user unit|launchers start session daemon|enable/start the owned user unit' "$base/out" \
    || fail "no-launch plans a Link service action"
grep -q 'deprecated' "$base/err" || fail "compatibility warning is printed"
ok "no-launch compatibility excludes Link assets and service enablement"

base="$(new_env update-policy)"
mkdir -p "$base/config/ableton-wine" "$base/prefix"
printf 'registry\n' > "$base/prefix/system.reg"
cat > "$base/config/ableton-wine/config" <<EOF
# ableton-linux installer configuration; managed by the installer
format=1
runtime_root=$base/runtime
prefix=$base/prefix
live_major=12
link_mode=off
linkd=$base/data/ableton-wine/ableton-linkd
EOF
run_isolated "$base" env ABLETON_DPI_MODE=preserve bash "$here/installer.sh" update --dry-run >"$base/out" 2>"$base/err"
grep -q 'final Link policy: off' "$base/out" || fail "update preserves Link opt-out"
! grep -q 'write Link binary:' "$base/out" || fail "opted-out update excludes Link assets"
ok "update preserves the persistent Link opt-out"

base="$(new_env update-no-prefix)"
if run_isolated "$base" bash "$here/installer.sh" update --dry-run >"$base/out" 2>"$base/err"; then
    fail "update without an existing prefix fails"
fi
grep -q 'update needs an existing prefix' "$base/err" || fail "update without a prefix names the remedy"
! grep -q -- '--refresh' "$base/err" || fail "update failure avoids the component --refresh flag"
[ ! -e "$base/config" ] && [ ! -e "$base/state" ] || fail "update without a prefix mutates state"
ok "update without a prefix fails fast in installer vocabulary"

base="$(new_env mismatch)"
printf 'Ableton Live 11 installer\n' > "$base/Ableton_Live_11_Installer.exe"
if run_isolated "$base" bash "$here/installer.sh" install --live-installer "$base/Ableton_Live_11_Installer.exe" \
    --live-major 12 --link=off --runtime-root "$base/runtime" --prefix "$base/prefix" >"$base/out" 2>"$base/err"; then
    fail "payload-major mismatch fails"
fi
grep -q 'appears to be Live 11' "$base/err" || fail "payload mismatch is explicit"
[ ! -e "$base/runtime" ] && [ ! -e "$base/prefix" ] && [ ! -e "$base/config" ] || fail "payload mismatch mutates no installation state"
ok "Live payload major is validated before installation"

base="$(new_env launcher-preflight)"
mkdir -p "$base/runtime/bin" "$base/prefix"
printf '#!/bin/sh\nexit 0\n' > "$base/runtime/bin/wine"
printf '#!/bin/sh\nexit 0\n' > "$base/runtime/bin/wineserver"
chmod +x "$base/runtime/bin/wine" "$base/runtime/bin/wineserver"
printf 'registry\n' > "$base/prefix/system.reg"
if run_isolated "$base" env ABLETON_WINE_ROOT="$base/runtime" ABLETON_WINEPREFIX="$base/prefix" \
    bash "$here/ableton-live" >"$base/out" 2>"$base/err"; then
    fail "launcher without Live fails"
fi
grep -q 'no Ableton Live installation' "$base/err" || fail "launcher reports missing Live"
[ ! -e "$base/state" ] && [ ! -e "$base/data" ] && [ ! -e "$base/config" ] && [ ! -e "$base/run" ] \
    || fail "launcher preflight mutates no machine state"
ok "launcher validates runtime, prefix, and Live before mutation"

base="$(new_env max-coexist)"
mkdir -p "$base/runtime/bin" "$base/prefix/drive_c/ProgramData/Ableton/Live 12 Suite/Program" "$base/run"
cp /bin/sleep "$base/runtime/bin/wine-client"
cat > "$base/runtime/bin/wine" <<'EOF'
#!/bin/sh
printf 'wine %s\n' "$*" >> "${ABLETON_TEST_LOG:?}"
exit 0
EOF
cat > "$base/runtime/bin/wineserver" <<'EOF'
#!/bin/sh
printf 'wineserver %s\n' "$*" >> "${ABLETON_TEST_LOG:?}"
exit 0
EOF
cat > "$base/runtime/bin/wineboot" <<'EOF'
#!/bin/sh
printf 'wineboot %s\n' "$*" >> "${ABLETON_TEST_LOG:?}"
exit 0
EOF
printf '#!/bin/sh\nexit 0\n' > "$base/runtime/bin/winepath"
chmod +x "$base/runtime/bin/"*
printf 'registry\n' > "$base/prefix/system.reg"
printf 'registry\n' > "$base/prefix/user.reg"
printf 'exe\n' > "$base/prefix/drive_c/ProgramData/Ableton/Live 12 Suite/Program/Ableton Live 12 Suite.exe"
: > "$base/wine.log"
env WINEPREFIX="$base/prefix" bash -c 'exec -a "C:\\Program Files\\Cycling '\''74\\Max 9\\Max.exe" "$1" 60' _ "$base/runtime/bin/wine-client" &
max_pid=$!
sleep 0.1
run_isolated "$base" env ABLETON_WINE_ROOT="$base/runtime" ABLETON_WINEPREFIX="$base/prefix" \
    ABLETON_LINK_MODE=off ABLETON_POWER=off ABLETON_RT=off ABLETON_THEME_MODE=preserve \
    ABLETON_DPI_MODE=preserve ABLETON_UI_FONT=preserve ABLETON_TEXT_SMOOTHING=preserve \
    ABLETON_TEST_LOG="$base/wine.log" bash "$here/ableton-live" >"$base/out" 2>"$base/err" || true
kill -0 "$max_pid" 2>/dev/null || fail "cold Live launch preserves Max"
kill "$max_pid" 2>/dev/null || true
wait "$max_pid" 2>/dev/null || true
! grep -Eq 'wineserver -k|wineboot' "$base/wine.log" || fail "busy prefix avoids kill and boot"
ok "cold Live launch neither kills Max nor boots its busy prefix"

base="$(new_env foreign-runtime)"
mkdir -p "$base/runtime/bin"
cp /bin/sleep "$base/runtime/bin/wine-client"
printf 'format=1\nname=wine-d2d1-nspa-11.13\n' > "$base/runtime/.ableton-linux-runtime"
env WINEPREFIX="$base/foreign-prefix" "$base/runtime/bin/wine-client" 60 &
foreign_pid=$!
sleep 0.1
if run_isolated "$base" bash "$here/installer.sh" runtime install \
    --runtime-root "$base/runtime" --yes >"$base/out" 2>"$base/err"; then
    fail "runtime update proceeds while a foreign prefix uses it"
fi
kill -0 "$foreign_pid" 2>/dev/null || fail "runtime update killed a foreign prefix client"
kill "$foreign_pid" 2>/dev/null || true
wait "$foreign_pid" 2>/dev/null || true
if grep -q 'used by another Wine prefix' "$base/err"; then
    ok "runtime lifecycle refuses, and never signals, a foreign prefix client"
elif grep -Eq 'PipeWire is unavailable|PipeWire compatibility cannot be checked' "$base/err"; then
    ok "PipeWire preflight refuses before a foreign runtime client can be signalled"
else
    fail "runtime refusal did not explain either lifecycle or PipeWire preflight"
fi

base="$(new_env transaction)"
mkdir -p "$base/txn" "$base/data/ableton-wine"
printf 'before\n' > "$base/data/ableton-wine/detect-theme.sh"
run_isolated "$base" env ABLETON_TRANSACTION_DIR="$base/txn" bash -c '
    . "$1/lib/config.sh"
    ableton_config_init
    . "$1/lib/manifest.sh"
    ableton_txn_init
    ableton_txn_snapshot "$2/detect-theme.sh"
    ableton_txn_snapshot "$2/detect-scale.sh"
    after="$(mktemp)"; printf "after\n" > "$after"
    new="$(mktemp)"; printf "new\n" > "$new"
    ableton_txn_expect "$2/detect-theme.sh" "$(ableton_regular_source_token "$after")"
    ableton_txn_expect "$2/detect-scale.sh" "$(ableton_regular_source_token "$new")"
    printf "after\n" > "$2/detect-theme.sh"
    printf "new\n" > "$2/detect-scale.sh"
    ableton_txn_rollback_files "$3"
' _ "$here" "$base/data/ableton-wine" "$base/txn"
[ "$(cat "$base/data/ableton-wine/detect-theme.sh")" = before ] \
    && [ ! -e "$base/data/ableton-wine/detect-scale.sh" ] || fail "file transaction rolls back"
ok "file transaction restores overwritten files and removes new files"

base="$(new_env prefix-host-transaction)"
mkdir -p "$base/txn/prefix-host" "$base/config/pipeasio"
printf 'before\n' > "$base/config/pipeasio/config.ini"
run_isolated "$base" env ABLETON_TRANSACTION_DIR="$base/txn/prefix-host" bash -c '
    . "$1/lib/config.sh"
    ableton_config_init
    . "$1/lib/manifest.sh"
    ableton_txn_init
    ableton_txn_snapshot "$2/config.ini"
    after="$(mktemp)"; printf "after\n" > "$after"
    ableton_txn_expect "$2/config.ini" "$(ableton_regular_source_token "$after")"
' _ "$here" "$base/config/pipeasio"
printf 'after\n' > "$base/config/pipeasio/config.ini"
run_isolated "$base" bash "$here/setup-prefix.sh" --rollback "$base/txn"
[ "$(cat "$base/config/pipeasio/config.ini")" = before ] \
    || fail "prefix rollback leaves a pre-promotion host mutation behind"
ok "prefix rollback restores host files even before prefix promotion"

base="$(new_env uninstall-prestate)"
foreign_icon="$base/data/icons/hicolor/scalable/apps/live-suite.svg"
mkdir -p "$(dirname "$foreign_icon")" "$base/fakebin"
printf 'foreign icon\n' > "$foreign_icon"
cat > "$base/fakebin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$base/fakebin/systemctl"
run_isolated "$base" env PATH="$base/fakebin:$PATH" bash "$here/install.sh" --integration-only >"$base/install.out" 2>"$base/install.err"
grep -q '<svg' "$foreign_icon" || fail "integration did not replace the collision fixture"
run_isolated "$base" env PATH="$base/fakebin:$PATH" bash "$here/uninstall.sh" --keep-prefix --yes >"$base/out" 2>"$base/err"
[ "$(cat "$foreign_icon")" = 'foreign icon' ] || fail "uninstall did not restore overwritten pre-install file"
ok "uninstall restores a pre-existing file overwritten by integration"

base="$(new_env user-config)"
user_config="$base/config/pipeasio/config.ini"
mkdir -p "$(dirname "$user_config")" "$base/state/ableton-wine" "$base/fakebin"
printf 'format=1\nowner=ableton-linux\n' > "$base/state/ableton-wine/.ableton-linux-state"
printf 'seeded\n' > "$user_config"
printf 'config\t%s\t%s\n' "$user_config" "$(sha256sum "$user_config" | awk '{print $1}')" \
    > "$base/state/ableton-wine/install-manifest.tsv"
printf 'user buffer setting\n' > "$user_config"
printf '#!/bin/sh\nexit 0\n' > "$base/fakebin/systemctl"
chmod +x "$base/fakebin/systemctl"
run_isolated "$base" env PATH="$base/fakebin:$PATH" bash "$here/uninstall.sh" \
    --keep-prefix --yes >"$base/out" 2>"$base/err"
[ "$(cat "$user_config")" = 'user buffer setting' ] \
    || fail "uninstall removes user-modified seeded configuration"
grep -q 'kept user-modified configuration' "$base/out" \
    || fail "preserved user configuration is not reported"
ok "uninstall preserves and de-owns user-modified seeded configuration"

base="$(new_env modified-owned)"
run_isolated "$base" bash "$here/install.sh" --integration-only >"$base/first.out" 2>"$base/first.err"
printf '\n# user change\n' >> "$base/data/ableton-wine/detect-scale.sh"
if run_isolated "$base" bash "$here/install.sh" --integration-only >"$base/out" 2>"$base/err"; then
    fail "integration overwrites a modified managed file"
fi
grep -qF '# user change' "$base/data/ableton-wine/detect-scale.sh" || fail "failed update lost managed-file modification"
grep -q 'refusing to overwrite modified managed file' "$base/err" || fail "modified managed file refusal is explicit"
ok "update refuses to overwrite a locally modified managed file"

base="$(new_env link-prestate)"
foreign_linkd="$base/data/ableton-wine/ableton-linkd"
mkdir -p "$(dirname "$foreign_linkd")" "$base/fakebin"
printf '#!/bin/sh\necho foreign\n' > "$foreign_linkd"
chmod +x "$foreign_linkd"
cat > "$base/fakebin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$base/fakebin/systemctl"
run_isolated "$base" env PATH="$base/fakebin:$PATH" bash "$here/install.sh" --link-assets-only >"$base/install.out" 2>"$base/install.err"
grep -qF 'native Ableton Link session anchor' < <(strings "$foreign_linkd") \
    || fail "Link asset install did not replace the collision fixture"
run_isolated "$base" env PATH="$base/fakebin:$PATH" bash "$here/setup-link.sh" disable >"$base/out" 2>"$base/err"
grep -qF 'echo foreign' "$foreign_linkd" || fail "Link disable did not restore overwritten pre-install binary"
ok "Link disable restores a pre-existing binary overwritten by Link assets"

base="$(new_env uninstall-safety)"
if run_isolated "$base" env ABLETON_WINEPREFIX=/ ABLETON_WINE_ROOT="$base/runtime" \
    bash "$here/uninstall.sh" --delete-prefix --yes --dry-run >"$base/out" 2>"$base/err"; then
    fail "unsafe prefix target is rejected"
fi
grep -q 'unsafe prefix target' "$base/err" || fail "unsafe target reason is reported"
ok "uninstall rejects root as a prefix target before mutation"

base="$(new_env uninstall-symlink)"
mkdir -p "$base/victim" "$base/runtime"
printf 'registry\n' > "$base/victim/system.reg"
printf 'format=1\n' > "$base/victim/.ableton-linux-prefix"
ln -s "$base/victim" "$base/prefix-link"
if run_isolated "$base" env ABLETON_WINEPREFIX="$base/prefix-link" ABLETON_WINE_ROOT="$base/runtime" \
    bash "$here/uninstall.sh" --delete-prefix --yes --dry-run >"$base/out" 2>"$base/err"; then
    fail "symlink prefix target is accepted"
fi
[ -f "$base/victim/system.reg" ] || fail "symlink rejection changed its target"
ok "uninstall rejects a symlinked custom prefix before mutation"

base="$(new_env uninstall-link)"
mkdir -p "$base/data/ableton-wine/lib" "$base/config/ableton-wine" \
    "$base/state/ableton-wine" "$base/run/ableton-wine" "$base/runtime/bin" "$base/prefix" "$base/fakebin"
printf 'format=1\nowner=ableton-linux\n' > "$base/state/ableton-wine/.ableton-linux-state"
cp "$here/lib/config.sh" "$base/data/ableton-wine/lib/config.sh"
cp "$here/lib/lifecycle.sh" "$base/data/ableton-wine/lib/lifecycle.sh"
cp "$here/lib/manifest.sh" "$base/data/ableton-wine/lib/manifest.sh"
cp "$here/lib/pipeasio.sh" "$base/data/ableton-wine/lib/pipeasio.sh"
cp "$here/ableton-linkctl" "$base/data/ableton-wine/ableton-linkctl"
cp "$here/setup-link.sh" "$base/data/ableton-wine/setup-link.sh"
cp /bin/sleep "$base/data/ableton-wine/ableton-linkd"
chmod +x "$base/data/ableton-wine/ableton-linkctl" "$base/data/ableton-wine/setup-link.sh" \
    "$base/data/ableton-wine/ableton-linkd"
printf 'format=1\nname=wine-d2d1-nspa-11.13\n' > "$base/runtime/.ableton-linux-runtime"
cat > "$base/runtime/bin/wine" <<'EOF'
#!/bin/sh
case "$*" in
    *'reg query HKCU\Software'*) exit 0 ;;
    *'reg query'*) exit 1 ;;
    *) exit 0 ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' > "$base/runtime/bin/wineserver"
chmod +x "$base/runtime/bin/wine" "$base/runtime/bin/wineserver"
printf 'registry\n' > "$base/prefix/system.reg"
printf 'format=1\nprefix=%s\n' "$base/prefix" > "$base/prefix/.ableton-linux-prefix"
cat > "$base/config/ableton-wine/config" <<EOF
# ableton-linux installer configuration; managed by the installer
format=1
runtime_root=$base/runtime
prefix=$base/prefix
live_major=12
link_mode=session
linkd=$base/data/ableton-wine/ableton-linkd
EOF
cat > "$base/fakebin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$base/fakebin/systemctl"
for owned in "$base/data/ableton-wine/lib/config.sh" "$base/data/ableton-wine/lib/lifecycle.sh" \
    "$base/data/ableton-wine/lib/manifest.sh" "$base/data/ableton-wine/lib/pipeasio.sh" \
    "$base/data/ableton-wine/ableton-linkctl" "$base/data/ableton-wine/setup-link.sh" \
    "$base/data/ableton-wine/ableton-linkd"; do
    printf 'file\t%s\t%s\n' "$owned" "$(sha256sum "$owned" | awk '{print $1}')" \
        >> "$base/state/ableton-wine/install-manifest.tsv"
done
"$base/data/ableton-wine/ableton-linkd" 60 &
link_pid=$!
printf '%s\n' "$link_pid" > "$base/run/ableton-wine/linkd.pid"
run_isolated "$base" env PATH="$base/fakebin:$PATH" bash "$here/installer.sh" uninstall \
    --runtime-root "$base/runtime" --prefix "$base/prefix" --keep-prefix --yes >"$base/out" 2>"$base/err"
wait "$link_pid" 2>/dev/null || true
kill -0 "$link_pid" 2>/dev/null && fail "uninstall leaves detached Link running"
[ ! -e "$base/runtime" ] && [ ! -e "$base/data/ableton-wine/ableton-linkd" ] \
    && [ -e "$base/prefix/system.reg" ] || fail "uninstall removes owned runtime/Link and keeps requested prefix"
ok "uninstall stops an exact-owned detached Link daemon before removing it"

base="$(new_env link-firewall-rollback)"
mkdir -p "$base/data/ableton-wine" "$base/state/ableton-wine" "$base/fakebin"
printf '#!/bin/sh\nexit 0\n' > "$base/data/ableton-wine/ableton-linkctl"
printf '#!/bin/sh\nexit 0\n' > "$base/data/ableton-wine/ableton-linkd"
chmod +x "$base/data/ableton-wine/ableton-linkctl" "$base/data/ableton-wine/ableton-linkd"
printf 'none\n' > "$base/state/ableton-wine/link-firewall"
cat > "$base/fakebin/grep" <<'EOF'
#!/bin/sh
for argument do
    [ "$argument" != /etc/ufw/ufw.conf ] || exit 0
done
exec /usr/bin/grep "$@"
EOF
cat > "$base/fakebin/ufw" <<'EOF'
#!/bin/sh
case "$1" in
    status) [ ! -e "${ABLETON_TEST_UFW:?}" ] || echo '20808/udp ALLOW Anywhere' ;;
    allow) : > "${ABLETON_TEST_UFW:?}" ;;
    delete) rm -f -- "${ABLETON_TEST_UFW:?}" ;;
    *) exit 2 ;;
esac
EOF
cat > "$base/fakebin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
cat > "$base/fakebin/systemctl" <<'EOF'
#!/bin/sh
case "$*" in
    *daemon-reload*) exit 1 ;;
    *show*) exit 0 ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$base/fakebin/grep" "$base/fakebin/ufw" "$base/fakebin/sudo" "$base/fakebin/systemctl"
if run_isolated "$base" env PATH="$base/fakebin:$PATH" ABLETON_TEST_UFW="$base/ufw-rule" \
    bash "$here/setup-link.sh" enable --mode=session >"$base/out" 2>"$base/err"; then
    fail "Link enable succeeds after its systemd registration fails"
fi
[ ! -e "$base/ufw-rule" ] || fail "failed Link enable leaves its new firewall rule"
[ "$(cat "$base/state/ableton-wine/link-firewall")" = none ] \
    || fail "failed Link enable does not restore the prior firewall record"
ok "Link enable failure restores firewall ownership and host state"

for legacy_args in '' ' --linger 0'; do
    case "$legacy_args" in
        '') legacy_name=initial ;;
        *) legacy_name=session ;;
    esac
    base="$(new_env "link-legacy-unit-$legacy_name")"
    unit="$base/config/systemd/user/ableton-linkd.service"
    mkdir -p "$(dirname "$unit")" "$base/data/ableton-wine" "$base/fakebin"
    printf '#!/bin/sh\nexit 0\n' > "$base/data/ableton-wine/ableton-linkctl"
    printf '#!/bin/sh\nexit 0\n' > "$base/data/ableton-wine/ableton-linkd"
    chmod +x "$base/data/ableton-wine/ableton-linkctl" "$base/data/ableton-wine/ableton-linkd"
    cat > "$unit" <<EOF
[Unit]
Description=Ableton Link session anchor (ableton-linkd)
After=default.target

[Service]
ExecStart=%h/.local/share/ableton-wine/ableton-linkd${legacy_args}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    printf '#!/bin/sh\nexit 0\n' > "$base/fakebin/systemctl"
    printf '#!/bin/sh\nexit 0\n' > "$base/fakebin/sudo"
    chmod +x "$base/fakebin/systemctl" "$base/fakebin/sudo"
    if ! run_isolated "$base" env PATH="$base/fakebin:$PATH" \
        bash "$here/setup-link.sh" enable --mode=session >"$base/out" 2>"$base/err"; then
        sed -n '1,80p' "$base/err" >&2
        fail "Link setup cannot adopt the $legacy_name legacy unit"
    fi
    grep -qxF 'X-AbletonLinuxOwned=true' "$unit" \
        || fail "Link setup does not adopt the $legacy_name legacy unit"
    grep -qxF "ExecStart=\"$base/data/ableton-wine/ableton-linkd\" --linger 0" "$unit" \
        || fail "Link setup does not replace the $legacy_name legacy unit"
done
ok "Link setup adopts both exact legacy unit definitions"

base="$(new_env link-modified-legacy-unit)"
unit="$base/config/systemd/user/ableton-linkd.service"
mkdir -p "$(dirname "$unit")" "$base/data/ableton-wine" "$base/fakebin"
printf '#!/bin/sh\nexit 0\n' > "$base/data/ableton-wine/ableton-linkctl"
printf '#!/bin/sh\nexit 0\n' > "$base/data/ableton-wine/ableton-linkd"
chmod +x "$base/data/ableton-wine/ableton-linkctl" "$base/data/ableton-wine/ableton-linkd"
cat > "$unit" <<'EOF'
[Unit]
Description=Ableton Link session anchor (ableton-linkd)
After=default.target

[Service]
ExecStart=%h/.local/share/ableton-wine/ableton-linkd
Environment=FOREIGN_SETTING=1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
cp "$unit" "$base/unit.before"
printf '#!/bin/sh\nexit 0\n' > "$base/fakebin/systemctl"
printf '#!/bin/sh\nexit 0\n' > "$base/fakebin/sudo"
chmod +x "$base/fakebin/systemctl" "$base/fakebin/sudo"
if run_isolated "$base" env PATH="$base/fakebin:$PATH" \
    bash "$here/setup-link.sh" enable --mode=session >"$base/out" 2>"$base/err"; then
    fail "Link setup replaces a modified legacy-shaped unit"
fi
cmp -s "$base/unit.before" "$unit" || fail "Link setup changes a refused unit"
grep -q 'refusing to replace foreign systemd unit' "$base/err" \
    || fail "Link setup does not explain the modified unit refusal"
ok "Link setup keeps modified legacy-shaped units"

base="$(new_env link-unit-ownership)"
unit="$base/config/systemd/user/ableton-linkd.service"
link_binary="$base/data/ableton-wine/link%d"
mkdir -p "$(dirname "$unit")" "$(dirname "$link_binary")" "$base/fakebin"
printf '#!/bin/sh\nexit 0\n' > "$link_binary"
chmod +x "$link_binary"
printf '[Service]\nExecStart=/usr/bin/foreign-linkd\n' > "$unit"
cat > "$base/fakebin/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${ABLETON_TEST_SYSTEMCTL:?}"
exit 0
EOF
chmod +x "$base/fakebin/systemctl"
if run_isolated "$base" env PATH="$base/fakebin:$PATH" ABLETON_LINK_MODE=always \
    ABLETON_LINKD="$link_binary" ABLETON_TEST_SYSTEMCTL="$base/systemctl.log" \
    bash "$here/ableton-linkctl" start >"$base/out" 2>"$base/err"; then
    fail "Link controller starts a foreign canonical systemd unit"
fi
[ ! -e "$base/systemctl.log" ] || fail "foreign Link unit reaches systemctl"
cat > "$unit" <<EOF
[Unit]
X-AbletonLinuxOwned=true
[Service]
ExecStart="$base/data/ableton-wine/link%%d" --linger 0
EOF
run_isolated "$base" env PATH="$base/fakebin:$PATH" ABLETON_LINK_MODE=always \
    ABLETON_LINKD="$link_binary" ABLETON_TEST_SYSTEMCTL="$base/systemctl.log" \
    bash "$here/ableton-linkctl" start >"$base/owned.out" 2>"$base/owned.err"
grep -q -- '--user start ableton-linkd.service' "$base/systemctl.log" \
    || fail "exact owned Link unit is not started"
ok "Link controller starts only the exact ownership-marked unit"

base="$(new_env legacy-ownership)"
foreign_desktop="$base/data/applications/ableton-live.desktop"
mkdir -p "$(dirname "$foreign_desktop")" "$base/fakebin"
printf '[Desktop Entry]\nName=Foreign application\n' > "$foreign_desktop"
printf '#!/bin/sh\nexit 0\n' > "$base/fakebin/systemctl"
chmod +x "$base/fakebin/systemctl"
if run_isolated "$base" env PATH="$base/fakebin:$PATH" bash "$here/uninstall.sh" \
    --keep-prefix --yes >"$base/out" 2>"$base/err"; then
    fail "manifest-free uninstall reports full success with a foreign canonical file"
fi
[ -f "$foreign_desktop" ] || fail "legacy uninstall removes an unrecognised canonical desktop file"
grep -q 'kept unrecognised or modified legacy file' "$base/err" \
    || fail "legacy ownership refusal is not reported"
[ -f "$base/config/ableton-wine/config" ] \
    || fail "partial legacy uninstall discards the configuration needed to retry"
ok "legacy uninstall retains unrecognised canonical files"

printf 'PASS: %s installer lifecycle checks\n' "$pass"
