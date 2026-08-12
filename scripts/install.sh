#!/usr/bin/env bash
# Install independently selectable runtime, desktop-integration, and Link-asset
# components.  Prefix creation is deliberately separate (setup-prefix.sh).
set -euo pipefail
export LC_ALL=C.UTF-8
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
. "$here/lib/config.sh"
. "$here/lib/lifecycle.sh"
. "$here/lib/manifest.sh"

want_runtime=0
want_integration=0
want_link=0
validate_only=0
dry_run=0
assume_yes=0
transaction_arg=""
operation=install

if [ $# -eq 0 ]; then
    want_runtime=1; want_integration=1; want_link=1
fi
while [ $# -gt 0 ]; do
    case "$1" in
        --all) want_runtime=1; want_integration=1; want_link=1 ;;
        --runtime-only|--runtime) want_runtime=1 ;;
        --integration-only|--integration) want_integration=1 ;;
        --link-assets-only|--link-assets) want_link=1 ;;
        --validate) validate_only=1 ;;
        --dry-run) dry_run=1 ;;
        --yes) assume_yes=1 ;;
        --transaction-dir)
            [ $# -ge 2 ] || { echo "!! --transaction-dir needs a directory" >&2; exit 2; }
            transaction_arg="$2"; shift ;;
        --rollback)
            [ $# -ge 2 ] || { echo "!! --rollback needs a transaction directory" >&2; exit 2; }
            operation=rollback; transaction_arg="$2"; shift ;;
        --commit)
            [ $# -ge 2 ] || { echo "!! --commit needs a transaction directory" >&2; exit 2; }
            operation=commit; transaction_arg="$2"; shift ;;
        *) echo "!! unknown install.sh option: $1" >&2; exit 2 ;;
    esac
    shift
done

ableton_config_init
export WINEPREFIX="$ABLETON_WINEPREFIX"
data="$ABLETON_DATA_HOME"
bin="$ABLETON_BIN_HOME"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
mime_root="${XDG_DATA_HOME:-$HOME/.local/share}/mime"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

rollback_runtime()
{
    local txn="$1" target backup safe
    [ -r "$txn/runtime.tsv" ] || return 0
    IFS=$'\t' read -r target backup < "$txn/runtime.tsv"
    [ -n "$target" ] || return 0
    safe="$(ableton_path_is_safe_delete_target "$target")" || {
        echo "!! refusing unsafe runtime rollback target: $target" >&2; return 1; }
    if [ -e "$safe" ]; then
        [ ! -L "$safe" ] || { echo "!! refusing symlink runtime rollback target: $safe" >&2; return 1; }
        if [ ! -f "$safe/.ableton-linux-runtime" ]; then
            echo "!! refusing to remove unmarked runtime during rollback: $safe" >&2
            return 1
        fi
        rm -rf -- "$safe"
    fi
    if [ "$backup" != absent ] && [ -e "$backup" ]; then
        mv -- "$backup" "$safe"
    fi
    rm -f -- "$txn/runtime.tsv"
}

rollback_transaction()
{
    local txn="$1"
    rollback_runtime "$txn"
    ableton_txn_rollback_files "$txn"
    update-mime-database "$mime_root" >/dev/null 2>&1 || true
    update-desktop-database "$apps" >/dev/null 2>&1 || true
    gtk-update-icon-cache -q "$icons" >/dev/null 2>&1 || true
    rm -f -- "$txn/active"
}

commit_transaction()
{
    local txn="$1" target backup rollback
    if [ -r "$txn/runtime.tsv" ]; then
        IFS=$'\t' read -r target backup < "$txn/runtime.tsv"
        if [ "$backup" != absent ] && [ -e "$backup" ]; then
            rollback="$target-rollback-$stamp"
            [ ! -e "$rollback" ] || rollback="$rollback-$$"
            mv -- "$backup" "$rollback"
            printf '%s\n' "$rollback" > "$txn/runtime-rollback-path"
        fi
    fi
    rm -f -- "$txn/active"
}

case "$operation" in
    rollback) rollback_transaction "$transaction_arg"; exit ;;
    commit) commit_transaction "$transaction_arg"; exit ;;
esac

[ "$want_runtime$want_integration$want_link" != 000 ] || {
    echo "!! select at least one component" >&2; exit 2; }

own_transaction=0
if [ -n "$transaction_arg" ]; then
    ABLETON_TRANSACTION_DIR="$transaction_arg"
elif [ "$validate_only" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
    ABLETON_TRANSACTION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ableton-install-plan.XXXXXX")"
    own_transaction=1
else
    ableton_mark_state_home
    mkdir -p -- "$ABLETON_STATE_HOME/transactions"
    ABLETON_TRANSACTION_DIR="$(mktemp -d "$ABLETON_STATE_HOME/transactions/install.XXXXXX")"
    own_transaction=1
fi
export ABLETON_TRANSACTION_DIR
ableton_txn_init
stage=""
cleanup()
{
    local rc=$?
    trap - EXIT
    [ -z "$stage" ] || rm -rf -- "$stage"
    if [ "$rc" -ne 0 ] && [ -e "$ABLETON_TRANSACTION_DIR/active" ]; then
        echo "!! component installation failed; rolling its recorded mutations back" >&2
        rollback_transaction "$ABLETON_TRANSACTION_DIR" || true
        if [ "$own_transaction" -eq 1 ]; then
            printf 'component=install.sh\nexit=%s\n' "$rc" > "$ABLETON_TRANSACTION_DIR/FAILURE"
            echo "!! rollback complete; failure record: $ABLETON_TRANSACTION_DIR/FAILURE" >&2
        fi
    fi
    if [ "$own_transaction" -eq 1 ] && [ "$rc" -eq 0 ]; then
        commit_transaction "$ABLETON_TRANSACTION_DIR"
        rm -rf -- "$ABLETON_TRANSACTION_DIR"
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

tarball=""
candidate=""
linkd_source=""
unit_source=""

validate_runtime_payload()
{
    # Developer -debug trees lack wineboot/winepath/wine.inf and must never win
    # the newest-version selection over a release tree.
    tarball="$(find "$root/dist" "$root" -maxdepth 1 -type f -name "$ABLETON_RUNTIME_NAME-*.tar.zst" \
        ! -name '*-debug.tar.zst' -print 2>/dev/null | sort -V | tail -n 1 || true)"
    [ -n "$tarball" ] || { echo "!! no $ABLETON_RUNTIME_NAME-*.tar.zst payload found" >&2; return 1; }
    echo "== validate runtime payload: $(basename "$tarball") =="
    if [ -f "$tarball.sha256" ]; then
        ( cd "$(dirname "$tarball")" && sha256sum -c "$(basename "$tarball").sha256" )
    fi
    local parent
    parent="$(dirname "$ABLETON_WINE_ROOT")"
    if [ "$validate_only" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
        stage="$(mktemp -d "${TMPDIR:-/tmp}/ableton-runtime-validate.XXXXXX")"
    else
        mkdir -p -- "$parent"
        stage="$(mktemp -d "$parent/.ableton-runtime-stage.XXXXXX")"
    fi
    local extract_timeout
    extract_timeout="$(ableton_timeout_value "${ABLETON_RUNTIME_EXTRACT_TIMEOUT:-1800}" ABLETON_RUNTIME_EXTRACT_TIMEOUT 60 7200)"
    echo "   extracting and checking the staged runtime (bounded to ${extract_timeout}s)"
    if tar --help 2>&1 | grep -q -- '--checkpoint'; then
        ableton_run_bounded "$extract_timeout" tar --checkpoint=500 --checkpoint-action=dot \
            -C "$stage" -I zstd -xf "$tarball"
        printf '\n' >&2
    else
        ableton_run_bounded "$extract_timeout" tar -C "$stage" -I zstd -xf "$tarball"
    fi
    candidate="$stage/$ABLETON_RUNTIME_NAME"
    # setup-prefix.sh and ableton-live call wineboot, winepath, and wine.inf
    # by absolute path.  A tree without them passes installation and then
    # cannot boot a prefix.  wineboot and winepath are symlinks to wine,
    # which -s follows.
    local required
    for required in \
        bin/wine bin/wineserver bin/wineboot bin/winepath \
        share/wine/wine.inf \
        lib/wine/x86_64-windows/libusb-1.0.dll \
        lib/wine/x86_64-unix/libusb-1.0.so \
        lib/wine/x86_64-unix/comdlg32.so \
        lib/wine/x86_64-unix/winealsa.so \
        lib/wine/x86_64-unix/winegstreamer.so \
        lib/wine/x86_64-windows/pipeasio64.dll \
        lib/wine/x86_64-windows/pipeasio.dll \
        lib/wine/x86_64-unix/pipeasio64.dll.so \
        lib/wine/x86_64-unix/pipeasio.dll.so; do
        [ -s "$candidate/$required" ] || { echo "!! runtime payload is missing $required" >&2; return 1; }
    done
    [ ! -e "$candidate/lib/wine/i386-windows/libusb-1.0.dll" ] || {
        echo "!! runtime unexpectedly contains a 32-bit Push bridge" >&2; return 1; }
    if command -v readelf >/dev/null 2>&1 && command -v strings >/dev/null 2>&1; then
        readelf -d "$candidate/lib/wine/x86_64-unix/libusb-1.0.so" | grep -F 'Shared library: [libusb-1.0.so.0]' >/dev/null
        strings "$candidate/lib/wine/x86_64-unix/comdlg32.so" | grep -F 'org.freedesktop.portal.FileChooser' >/dev/null
        readelf -d "$candidate/lib/wine/x86_64-unix/pipeasio64.dll.so" | grep -F 'Shared library: [libpipewire-0.3.so.0]' >/dev/null
        readelf -d "$candidate/lib/wine/x86_64-unix/winegstreamer.so" | grep -F 'Shared library: [libgstreamer-1.0.so.0]' >/dev/null
    fi
    ableton_run_bounded 30 "$candidate/bin/wine" --version
}

validate_integration_sources()
{
    local required
    for required in ableton-live max9 detect-scale.sh detect-theme.sh shortcut-hold.sh; do
        [ -f "$here/$required" ] || { echo "!! installer kit is missing scripts/$required" >&2; return 1; }
    done
    for required in config.sh lifecycle.sh manifest.sh; do
        [ -f "$here/lib/$required" ] || { echo "!! installer kit is missing scripts/lib/$required" >&2; return 1; }
    done
    [ -f "$root/desktop/ableton-live.desktop.in" ] || { echo "!! installer kit is missing desktop integration" >&2; return 1; }
}

validate_link_sources()
{
    local file needed
    for file in "$here/../bin/ableton-linkd" "$root/dist/ableton-linkd"; do
        [ -f "$file" ] && { linkd_source="$file"; break; }
    done
    [ -n "$linkd_source" ] || { echo "!! installer kit is missing bin/ableton-linkd" >&2; return 1; }
    unit_source="$here/ableton-linkd.service"
    [ -f "$unit_source" ] || unit_source="$root/scripts/ableton-linkd.service"
    [ -f "$unit_source" ] || { echo "!! installer kit is missing ableton-linkd.service" >&2; return 1; }
    [ -f "$here/ableton-linkctl" ] || { echo "!! installer kit is missing ableton-linkctl" >&2; return 1; }
    if command -v readelf >/dev/null 2>&1; then
        needed="$(readelf -d "$linkd_source" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')"
        for file in $needed; do
            case "$file" in linux-vdso.so*|libm.so*|libc.so*|libpthread.so*|libatomic.so*|ld-linux*.so*) ;;
                *) echo "!! ableton-linkd links unexpected library $file" >&2; return 1 ;;
            esac
        done
    fi
    ableton_run_bounded 10 "$linkd_source" --help >/dev/null
}

[ "$want_runtime" -eq 0 ] || validate_runtime_payload
[ "$want_integration" -eq 0 ] || validate_integration_sources
[ "$want_link" -eq 0 ] || validate_link_sources

if [ "$validate_only" -eq 1 ]; then
    echo "OK: selected component payloads are valid"
    rm -f -- "$ABLETON_TRANSACTION_DIR/active"
    exit 0
fi

if [ "$dry_run" -eq 1 ]; then
    echo "PLAN: resolved configuration"
    [ "$want_runtime" -eq 0 ] || {
        printf '  replace runtime tree atomically: %s\n' "$ABLETON_WINE_ROOT"
        printf '  write runtime ownership marker: %s/.ableton-linux-runtime\n' "$ABLETON_WINE_ROOT"
    }
    if [ "$want_integration" -eq 1 ]; then
        printf '  write launcher: %s/ableton-live\n' "$bin"
        printf '  write launcher support: %s/{lib/config.sh,lib/lifecycle.sh,lib/manifest.sh,detect-scale.sh,detect-theme.sh,shortcut-hold.sh}\n' "$data"
        printf '  write helper assets when packaged: %s/{setsyscolors.exe,learnheal.exe}\n' "$data"
        printf '  write desktop entries: %s/{ableton-live,wine-protocol-ableton,wine-extension-auz}.desktop\n' "$apps"
        printf '  write staged protocol entries: %s/{wine-protocol-ableton,wine-extension-auz}.desktop\n' "$data"
        printf '  write icon files below: %s/{scalable,symbolic}\n' "$icons"
        printf '  write MIME packages below: %s/packages\n' "$mime_root"
        printf '  record/modify MIME defaults: %s/mime-prestate.tsv and %s\n' \
            "$ABLETON_STATE_HOME" "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
        if [ -f "$ABLETON_WINEPREFIX/drive_c/Program Files/Cycling '74/Max 9/Max.exe" ]; then
            printf '  write Max launcher and desktop/protocol entries: %s/max9, %s/{max9,wine-protocol-c74max}.desktop\n' "$bin" "$apps"
        fi
    fi
    if [ "$want_link" -eq 1 ]; then
        printf '  write Link binary: %s\n' "$ABLETON_LINKD"
        printf '  write Link controller/setup/unit assets: %s/{ableton-linkctl,setup-link.sh,ableton-linkd.service}\n' "$data"
        printf '  write Link support libraries: %s/lib/{config.sh,lifecycle.sh}\n' "$data"
    fi
    if [ "$want_integration" -eq 1 ] || [ "$want_link" -eq 1 ]; then
        printf '  write component version: %s/VERSION\n' "$data"
        printf '  update ownership manifest: %s/install-manifest.tsv\n' "$ABLETON_STATE_HOME"
    fi
    rm -f -- "$ABLETON_TRANSACTION_DIR/active"
    exit 0
fi

runtime_pids_all()
{
    local proc pid
    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"
        ableton_pid_uses_runtime "$pid" && printf '%s\n' "$pid"
    done
    return 0
}

stop_runtime_clients()
{
    local all scoped foreign pid answer=""
    all="$(runtime_pids_all)"
    [ -n "$all" ] || return 0
    scoped="$(ableton_prefix_pids)"
    foreign=""
    for pid in $all; do
        case " $scoped " in *" $pid "*) ;; *) foreign="$foreign $pid" ;; esac
    done
    if [ -n "$foreign" ]; then
        echo "!! runtime is used by another Wine prefix (PIDs:$foreign); close it before updating" >&2
        return 1
    fi
    echo "!! the selected prefix has running Wine clients: $(tr ' ' '\n' <<< "$scoped" | sed '/^$/d' | paste -sd, -)" >&2
    if [ "$assume_yes" -ne 1 ]; then
        if [ -t 0 ]; then
            printf 'Stop every client in this prefix (including Live or Max)? [y/N] ' >&2
            read -r -t 60 answer || answer=""
            case "$answer" in y|Y|yes|YES|Yes) ;; *) return 1 ;; esac
        else
            echo "!! refusing without --yes in a noninteractive session" >&2
            return 1
        fi
    fi
    ableton_stop_prefix || { echo "!! could not stop all scoped Wine clients" >&2; return 1; }
}

promote_runtime()
{
    local target="$ABLETON_WINE_ROOT" parent backup safe
    stop_runtime_clients
    parent="$(dirname "$target")"
    mkdir -p -- "$parent"
    safe="$(ableton_path_is_safe_delete_target "$target")" || { echo "!! unsafe runtime target: $target" >&2; return 1; }
    backup=absent
    if [ -e "$safe" ]; then
        [ ! -L "$safe" ] || { echo "!! refusing to replace symlink runtime $safe" >&2; return 1; }
        if [ ! -f "$safe/.ableton-linux-runtime" ] \
           && [ "$safe" != "$(ableton_realpath_m "$HOME/.local/opt/$ABLETON_RUNTIME_NAME")" ]; then
            echo "!! refusing to replace an unrecognised runtime directory: $safe" >&2
            return 1
        fi
        backup="$safe.transaction-${ABLETON_TRANSACTION_DIR##*/}"
        [ ! -e "$backup" ] || { echo "!! transaction backup already exists: $backup" >&2; return 1; }
        mv -- "$safe" "$backup"
    fi
    printf '%s\t%s\n' "$safe" "$backup" > "$ABLETON_TRANSACTION_DIR/runtime.tsv"
    mv -- "$candidate" "$safe"
    printf 'format=1\nname=%s\n' "$ABLETON_RUNTIME_NAME" > "$safe/.ableton-linux-runtime"
    ABLETON_RUNTIME_INSTALLED=1
    export ABLETON_RUNTIME_INSTALLED
    "$safe/bin/wine" --version
}

sed_escape()
{
    printf '%s' "$1" | sed 's/[\\&#]/\\&/g'
}

record_mime_prestate()
{
    local state="$ABLETON_STATE_HOME/mime-prestate.tsv" type old
    [ -e "$state" ] && return 0
    ableton_txn_snapshot "$state"
    ableton_mark_state_home
    : > "$state"
    command -v xdg-mime >/dev/null 2>&1 || return 0
    for type in x-scheme-handler/ableton application/x-wine-extension-auz \
                application/x-ableton-live-set application/x-ableton-live-clip \
                application/x-ableton-live-pack application/x-ableton-live-max-device \
                x-scheme-handler/c74max; do
        old="$(xdg-mime query default "$type" 2>/dev/null || true)"
        printf '%s\t%s\n' "$type" "$old" >> "$state"
    done
}

install_integration()
{
    local tool source target tmp newest="" exe live_name="Ableton Live" live_icon=live-suite live_wmclass="" edition d
    echo "== install launchers and host integration =="
    for tool in config.sh lifecycle.sh manifest.sh; do
        ableton_install_file 644 "$here/lib/$tool" "$data/lib/$tool"
    done
    ableton_install_file 755 "$here/ableton-live" "$bin/ableton-live"
    for tool in detect-scale.sh detect-theme.sh shortcut-hold.sh; do
        ableton_install_file 644 "$here/$tool" "$data/$tool"
    done
    for tool in setsyscolors.exe learnheal.exe; do
        for source in "$here/$tool" "$root/tools/$tool"; do
            [ -f "$source" ] || continue
            ableton_install_file 644 "$source" "$data/$tool"
            break
        done
    done

    for exe in "$ABLETON_WINEPREFIX"/drive_c/ProgramData/Ableton/Live*/Program/Ableton\ Live*.exe; do
        [ -e "$exe" ] || continue
        [ -z "$newest" ] || [ "$exe" -nt "$newest" ] || continue
        newest="$exe"
    done
    if [ -n "$newest" ]; then
        live_name="$(basename "$newest" .exe)"
        live_wmclass="$(basename "$newest" | tr '[:upper:]' '[:lower:]')"
        edition="$(printf '%s' "$live_name" | awk '{print tolower($NF)}')"
        [ ! -f "$root/desktop/icons/scalable/apps/live-$edition.svg" ] || live_icon="live-$edition"
    fi
    tmp="$(mktemp)"
    sed -e "s#@HOME@#$(sed_escape "$HOME")#g" \
        -e "s#@BIN@#$(sed_escape "$bin")#g" \
        -e "s#@PREFIX@#$(sed_escape "$ABLETON_WINEPREFIX")#g" \
        -e "s#@NAME@#$(sed_escape "$live_name")#g" \
        -e "s#@ICON@#$(sed_escape "$live_icon")#g" \
        -e "s#@WMCLASS@#$(sed_escape "$live_wmclass")#g" \
        "$root/desktop/ableton-live.desktop.in" > "$tmp"
    [ -n "$live_wmclass" ] || sed -i '/^StartupWMClass=/d' "$tmp"
    if [ -e "$apps/ableton-live.desktop" ] && ! grep -qF "$bin/ableton-live" "$apps/ableton-live.desktop"; then
        echo "   preserving foreign $apps/ableton-live.desktop"
    else
        ableton_install_file 644 "$tmp" "$apps/ableton-live.desktop"
    fi
    rm -f -- "$tmp"

    for d in wine-protocol-ableton wine-extension-auz; do
        tmp="$(mktemp)"
        sed -e "s#@HOME@#$(sed_escape "$HOME")#g" -e "s#@BIN@#$(sed_escape "$bin")#g" \
            "$root/desktop/$d.desktop.in" > "$tmp"
        ableton_install_file 644 "$tmp" "$data/$d.desktop"
        if [ ! -e "$apps/$d.desktop" ] || grep -qF "$bin/ableton-live" "$apps/$d.desktop"; then
            ableton_install_file 644 "$tmp" "$apps/$d.desktop"
        else
            echo "   preserving foreign $apps/$d.desktop"
        fi
        rm -f -- "$tmp"
    done

    for source in "$root"/desktop/icons/scalable/apps/*.svg; do
        ableton_install_file 644 "$source" "$icons/scalable/apps/$(basename "$source")"
    done
    for source in "$root"/desktop/icons/scalable/mimetypes/*.svg; do
        ableton_install_file 644 "$source" "$icons/scalable/mimetypes/$(basename "$source")"
    done
    for source in "$root"/desktop/icons/symbolic/apps/*.svg; do
        ableton_install_file 644 "$source" "$icons/symbolic/apps/$(basename "$source")"
    done
    ableton_install_file 644 "$root/desktop/x-wine-extension-auz.xml" "$mime_root/packages/x-wine-extension-auz.xml"
    ableton_install_file 644 "$root/desktop/icons/application-ableton-live.xml" "$mime_root/packages/application-ableton-live.xml"

    record_mime_prestate
    ableton_txn_snapshot "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default wine-protocol-ableton.desktop x-scheme-handler/ableton
        xdg-mime default wine-extension-auz.desktop application/x-wine-extension-auz
        xdg-mime default ableton-live.desktop application/x-ableton-live-set application/x-ableton-live-clip application/x-ableton-live-pack
    fi

    local max_unix="$ABLETON_WINEPREFIX/drive_c/Program Files/Cycling '74/Max 9/Max.exe"
    if [ -f "$max_unix" ]; then
        ableton_install_file 755 "$here/max9" "$bin/max9"
        for d in max9 wine-protocol-c74max; do
            tmp="$(mktemp)"
            sed -e "s#@HOME@#$(sed_escape "$HOME")#g" -e "s#@BIN@#$(sed_escape "$bin")#g" \
                -e "s#@PREFIX@#$(sed_escape "$ABLETON_WINEPREFIX")#g" \
                "$root/desktop/$d.desktop.in" > "$tmp"
            target="$apps/$d.desktop"
            if [ "$d" != max9 ] || [ ! -e "$target" ] || grep -qF "$bin/max9" "$target"; then
                ableton_install_file 644 "$tmp" "$target"
            fi
            rm -f -- "$tmp"
        done
        if command -v xdg-mime >/dev/null 2>&1; then
            xdg-mime default max9.desktop application/x-ableton-live-max-device
            xdg-mime default wine-protocol-c74max.desktop x-scheme-handler/c74max
        fi
    fi
    update-mime-database "$mime_root" >/dev/null 2>&1 || true
    update-desktop-database "$apps" >/dev/null 2>&1 || true
    gtk-update-icon-cache -q "$icons" >/dev/null 2>&1 || true
}

install_link_assets()
{
    echo "== install Link assets (not enabled or started) =="
    local tool restart_always=0 fragment="" expected_unit
    if [ -x "$ABLETON_LINKD" ]; then
        [ "$ABLETON_LINK_MODE" != always ] || restart_always=1
        if command -v systemctl >/dev/null 2>&1; then
            fragment="$(ableton_run_bounded 20 systemctl --user show -p FragmentPath --value ableton-linkd.service 2>/dev/null || true)"
            expected_unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/ableton-linkd.service"
            if [ -n "$fragment" ] \
               && [ "$(ableton_realpath_m "$fragment")" = "$(ableton_realpath_m "$expected_unit")" ] \
               && grep -qxF 'X-AbletonLinuxOwned=true' "$expected_unit" 2>/dev/null; then
                ableton_run_bounded 20 systemctl --user stop ableton-linkd.service >/dev/null 2>&1 || return 1
            fi
        fi
        "$here/ableton-linkctl" stop || return 1
    fi
    for tool in config.sh lifecycle.sh; do
        ableton_install_file 644 "$here/lib/$tool" "$data/lib/$tool"
    done
    ableton_install_file 755 "$linkd_source" "$ABLETON_LINKD"
    ableton_install_file 755 "$here/ableton-linkctl" "$data/ableton-linkctl"
    ableton_install_file 755 "$here/setup-link.sh" "$data/setup-link.sh"
    ableton_install_file 644 "$unit_source" "$data/ableton-linkd.service"
    if [ "$restart_always" -eq 1 ]; then
        ableton_run_bounded 20 systemctl --user start ableton-linkd.service
    fi
}

[ "$want_runtime" -eq 0 ] || promote_runtime
[ "$want_integration" -eq 0 ] || install_integration
[ "$want_link" -eq 0 ] || install_link_assets

if [ "$want_integration" -eq 1 ] || [ "$want_link" -eq 1 ]; then
    mkdir -p -- "$data"
    printf '%s\n' "$(cat "$root/VERSION" 2>/dev/null || echo unknown)" > "$data/VERSION.tmp"
    ableton_install_file 644 "$data/VERSION.tmp" "$data/VERSION"
    rm -f -- "$data/VERSION.tmp"
fi
if [ "$want_integration" -eq 1 ] || [ "$want_link" -eq 1 ]; then
    ableton_write_ownership_manifest
fi

if [ "$own_transaction" -eq 1 ]; then
    commit_transaction "$ABLETON_TRANSACTION_DIR"
fi
rm -f -- "$ABLETON_TRANSACTION_DIR/active"
trap - EXIT
[ -z "$stage" ] || rm -rf -- "$stage"
[ "$own_transaction" -eq 0 ] || rm -rf -- "$ABLETON_TRANSACTION_DIR"
echo "OK: selected components installed transactionally"
