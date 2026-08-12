#!/usr/bin/env bash
# Remove only project-owned installation state.  Parsing, target validation,
# prefix confirmation, and running-client checks all precede the first mutation.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
for lib in "$here/lib/config.sh" "$here/config.sh" \
           "${XDG_DATA_HOME:-$HOME/.local/share}/ableton-wine/lib/config.sh"; do
    if [ -r "$lib" ]; then . "$lib"; break; fi
done
declare -F ableton_config_init >/dev/null 2>&1 || { echo "!! uninstall: config helper is missing" >&2; exit 1; }
ableton_config_init
for lib in "$here/lib/lifecycle.sh" "$ABLETON_DATA_HOME/lib/lifecycle.sh"; do
    if [ -r "$lib" ]; then . "$lib"; break; fi
done
declare -F ableton_prefix_busy >/dev/null 2>&1 || { echo "!! uninstall: lifecycle helper is missing" >&2; exit 1; }
for lib in "$here/lib/manifest.sh" "$ABLETON_DATA_HOME/lib/manifest.sh"; do
    if [ -r "$lib" ]; then . "$lib"; break; fi
done
declare -F ableton_legacy_owned_path >/dev/null 2>&1 || {
    echo "!! uninstall: ownership helper is missing" >&2; exit 1; }

delete_prefix=0
keep_prefix=0
assume_yes=0
dry_run=0
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
Usage: uninstall.sh [--keep-prefix|--delete-prefix] [--yes] [--dry-run]

The prefix is kept by default. --delete-prefix removes Live and its Wine-side
authorisation after validating a project marker (or the legacy default path).
EOF
            exit 0 ;;
        --keep-prefix) keep_prefix=1 ;;
        --delete-prefix) delete_prefix=1 ;;
        --prefix) delete_prefix=1; echo "WARNING: --prefix is deprecated; use --delete-prefix" >&2 ;;
        --yes|-y) assume_yes=1 ;;
        --dry-run) dry_run=1 ;;
        *) echo "!! unknown uninstall option: $1" >&2; exit 2 ;;
    esac
    shift
done
[ "$delete_prefix" -eq 0 ] || [ "$keep_prefix" -eq 0 ] || { echo "!! --keep-prefix and --delete-prefix conflict" >&2; exit 2; }

manifest="$ABLETON_STATE_HOME/install-manifest.tsv"
safe_runtime="$(ableton_path_is_safe_delete_target "$ABLETON_WINE_ROOT")" || {
    echo "!! unsafe runtime target in configuration: $ABLETON_WINE_ROOT" >&2; exit 2; }
safe_prefix="$(ableton_path_is_safe_delete_target "$ABLETON_WINEPREFIX")" || {
    echo "!! unsafe prefix target in configuration: $ABLETON_WINEPREFIX" >&2; exit 2; }
[ ! -L "$ABLETON_WINE_ROOT" ] || { echo "!! refusing symlink runtime: $ABLETON_WINE_ROOT" >&2; exit 2; }
[ ! -L "$ABLETON_WINEPREFIX" ] || { echo "!! refusing symlink prefix: $ABLETON_WINEPREFIX" >&2; exit 2; }

if [ "$delete_prefix" -eq 1 ] && [ -e "$safe_prefix" ]; then
    if [ ! -f "$safe_prefix/.ableton-linux-prefix" ] \
       && [ "$safe_prefix" != "$(ableton_realpath_m "$HOME/.wine-ableton")" ]; then
        echo "!! refusing to delete unrecognised custom prefix: $safe_prefix" >&2
        exit 2
    fi
    [ -f "$safe_prefix/system.reg" ] || {
        echo "!! refusing prefix deletion because system.reg is missing: $safe_prefix" >&2; exit 2; }
fi
if [ -e "$safe_runtime" ] && [ ! -f "$safe_runtime/.ableton-linux-runtime" ] \
   && [ "$safe_runtime" != "$(ableton_realpath_m "$HOME/.local/opt/$ABLETON_RUNTIME_NAME")" ]; then
    echo "!! refusing to delete unrecognised custom runtime: $safe_runtime" >&2
    exit 2
fi

managed_runtimes=("$safe_runtime")
if [ -r "$manifest" ]; then
    while IFS=$'\t' read -r kind path detail; do
        [ "$kind" = runtime ] || continue
        candidate="$(ableton_path_is_safe_delete_target "$path")" || {
            echo "!! unsafe runtime in ownership manifest: $path" >&2; exit 2; }
        [ ! -L "$path" ] || { echo "!! refusing symlink runtime from ownership manifest: $path" >&2; exit 2; }
        [ ! -e "$candidate" ] || [ -f "$candidate/.ableton-linux-runtime" ] || {
            echo "!! refusing unmarked runtime from ownership manifest: $candidate" >&2; exit 2; }
        duplicate=0
        for path in "${managed_runtimes[@]}"; do [ "$path" != "$candidate" ] || duplicate=1; done
        [ "$duplicate" -eq 1 ] || managed_runtimes+=("$candidate")
    done < "$manifest"
fi

if [ "$dry_run" -eq 1 ]; then
    echo "PLAN: uninstall project-owned state"
    printf '  remove marked runtime tree(s) and marked rollback siblings: %s\n  ownership manifest: %s\n' \
        "${managed_runtimes[*]}" "$manifest"
    if [ -r "$manifest" ]; then cut -f2 "$manifest" | sed 's/^/  owned file: /'; else echo "  legacy owned integration paths"; fi
    printf '  restore MIME defaults from: %s/mime-prestate.tsv\n' "$ABLETON_STATE_HOME"
    printf '  remove managed config/state after owned files: %s, %s\n' "$ABLETON_CONFIG_FILE" "$ABLETON_STATE_HOME"
    "$here/setup-link.sh" plan-disable
    [ "$delete_prefix" -eq 0 ] || printf '  delete validated prefix: %s\n' "$safe_prefix"
    exit 0
fi

# Gather all consent before stopping anything or deleting any file.
if [ "$delete_prefix" -eq 1 ] && [ -e "$safe_prefix" ] && [ "$assume_yes" -ne 1 ]; then
    answer=""
    if [ -t 0 ]; then
        printf 'Delete %s? This removes Live and its Wine-side authorisation. [y/N] ' "$safe_prefix" >&2
        read -r -t 60 answer || answer=""
    fi
    case "$answer" in y|Y|yes|YES|Yes) ;; *) echo "!! prefix deletion was not confirmed; nothing was changed" >&2; exit 1 ;; esac
fi

runtime_pids_all=""
for proc in /proc/[0-9]*; do
    pid="${proc#/proc/}"
    ableton_pid_uses_runtime "$pid" && runtime_pids_all="$runtime_pids_all $pid"
done
if [ -n "$runtime_pids_all" ]; then
    scoped=" $(ableton_prefix_pids | tr '\n' ' ') "
    for pid in $runtime_pids_all; do
        case "$scoped" in *" $pid "*) ;; *)
            echo "!! runtime is used by another prefix (PID $pid); close it before uninstalling" >&2
            exit 1 ;;
        esac
    done
    if [ "$assume_yes" -ne 1 ]; then
        answer=""
        if [ -t 0 ]; then
            printf 'Stop every running client in the selected prefix and uninstall? [y/N] ' >&2
            read -r -t 60 answer || answer=""
        fi
        case "$answer" in y|Y|yes|YES|Yes) ;; *) echo "!! nothing was changed" >&2; exit 1 ;; esac
    fi
fi

# A previous configured runtime may also remain in the ownership manifest.
# Never delete it while any process still executes from it; those clients are
# outside the currently selected runtime coordinator and must be closed first.
for candidate in "${managed_runtimes[@]}"; do
    [ "$candidate" != "$safe_runtime" ] || continue
    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"
        exe="$(readlink -f "$proc/exe" 2>/dev/null || true)"
        case "$exe" in "$candidate"/*)
            echo "!! previously managed runtime $candidate is still in use by PID $pid; close it before uninstalling" >&2
            exit 1 ;;
        esac
    done
done

echo "== stop project-owned services and processes =="
uninstall_partial=0
"$here/setup-link.sh" disable
ableton_prefix_busy && ableton_stop_prefix

shortcut_helper="$ABLETON_DATA_HOME/shortcut-hold.sh"
shortcut_state="$ABLETON_STATE_HOME/hold-v2"
legacy_shortcut_state="$safe_prefix/.ableton-shortcut-hold"
if [ -e "$shortcut_state" ] || [ -e "$legacy_shortcut_state" ]; then
    if [ -r "$shortcut_helper" ] && command -v gsettings >/dev/null 2>&1; then
        # prepare with holding disabled performs both V1 migration and V2 crash
        # recovery, while preserving any shortcut the user changed meanwhile.
        . "$shortcut_helper"
        ABLETON_SHORTCUTS=preserve ableton_shortcuts_prepare "" "$legacy_shortcut_state" 0
    fi
    if [ -e "$shortcut_state" ] || [ -e "$legacy_shortcut_state" ]; then
        echo "!! shortcut recovery state could not be fully restored; keeping installer state for retry" >&2
        uninstall_partial=1
    fi
fi

remove_owned_manifest_files()
{
    local kind path digest current backup prestate="$ABLETON_STATE_HOME/install-prestate.tsv"
    [ -r "$manifest" ] || return 1
    while IFS=$'\t' read -r kind path digest; do
        case "$kind" in
            file|config)
                backup=""
                if [ -r "$prestate" ]; then
                    backup="$(awk -F '\t' -v p="$path" '$1=="present" && $2==p { print $3; exit }' "$prestate")"
                fi
                if [ ! -e "$path" ] && [ ! -L "$path" ]; then
                    if [ -n "$backup" ] && { [ -e "$backup" ] || [ -L "$backup" ]; }; then
                        mkdir -p -- "$(dirname "$path")"
                        cp -a -- "$backup" "$path"
                        echo "restored pre-install file $path"
                    fi
                    continue
                fi
                current="$(sha256sum -- "$path" 2>/dev/null | awk '{print $1}')"
                if [ "$current" = "$digest" ]; then
                    rm -f -- "$path"
                    if [ -n "$backup" ] && { [ -e "$backup" ] || [ -L "$backup" ]; }; then
                        mkdir -p -- "$(dirname "$path")"
                        cp -a -- "$backup" "$path"
                        echo "restored pre-install file $path"
                    else
                        echo "removed $path"
                    fi
                else
                    if [ "$kind" = config ]; then
                        echo "kept user-modified configuration $path"
                    else
                        echo "kept modified file $path" >&2
                        uninstall_partial=1
                    fi
                fi ;;
            runtime) ;;
        esac
    done < "$manifest"
    return 0
}

remove_legacy_files()
{
    local data_root apps icons mime path source relative
    data_root="${XDG_DATA_HOME:-$HOME/.local/share}"
    apps="$data_root/applications"; icons="$data_root/icons/hicolor"; mime="$data_root/mime/packages"

    legacy_remove_if_owned()
    {
        local target="$1" original="${2:-}"
        [ -e "$target" ] || [ -L "$target" ] || return 0
        if ableton_legacy_owned_path "$target" \
           || { [ -n "$original" ] && [ -f "$original" ] && cmp -s -- "$original" "$target"; }; then
            rm -f -- "$target"
            echo "removed legacy project file $target"
        else
            echo "kept unrecognised or modified legacy file $target" >&2
            uninstall_partial=1
        fi
    }

    for path in \
        "$ABLETON_BIN_HOME/ableton-live" "$ABLETON_BIN_HOME/max9" \
        "$ABLETON_DATA_HOME/$ABLETON_PROTOCOL_DESKTOP_ID" \
        "$ABLETON_DATA_HOME/$ABLETON_AUZ_DESKTOP_ID" \
        "$ABLETON_DATA_HOME/wine-protocol-ableton.desktop" \
        "$ABLETON_DATA_HOME/wine-extension-auz.desktop" \
        "$apps/ableton-live.desktop" "$apps/$ABLETON_PROTOCOL_DESKTOP_ID" \
        "$apps/$ABLETON_AUZ_DESKTOP_ID" "$apps/wine-protocol-ableton.desktop" \
        "$apps/wine-extension-auz.desktop" "$apps/max9.desktop" \
        "$apps/wine-protocol-c74max.desktop" \
        "$mime/x-wine-extension-auz.xml" "$mime/application-ableton-live.xml"; do
        legacy_remove_if_owned "$path"
    done
    for source in "$here/../desktop/icons/scalable/apps"/*.svg \
                  "$here/../desktop/icons/scalable/mimetypes"/*.svg \
                  "$here/../desktop/icons/symbolic/apps"/*.svg; do
        [ -f "$source" ] || continue
        relative="${source#"$here/../desktop/icons/"}"
        legacy_remove_if_owned "$icons/$relative" "$source"
    done
}

echo "== remove owned runtime and integration =="
remove_owned_manifest_files || remove_legacy_files
for candidate in "${managed_runtimes[@]}"; do
    if [ -e "$candidate" ]; then
        rm -rf -- "$candidate"
        echo "removed $candidate"
    fi
    # Dated rollbacks and failed candidates are project-owned siblings.  Do
    # not traverse symlinks and require a Wine binary or marker before deletion.
    runtime_parent="$(dirname "$candidate")"
    runtime_base="$(basename "$candidate")"
    while IFS= read -r old_runtime; do
        [ -n "$old_runtime" ] || continue
        [ ! -L "$old_runtime" ] || { echo "kept symlink rollback $old_runtime" >&2; continue; }
        [ -f "$old_runtime/.ableton-linux-runtime" ] || [ -x "$old_runtime/bin/wine" ] || continue
        rm -rf -- "$old_runtime"
        echo "removed $old_runtime"
    done < <(find "$runtime_parent" -maxdepth 1 -mindepth 1 -type d \
        \( -name "$runtime_base-rollback-*" -o -name "$runtime_base.failed-*" -o -name "$runtime_base.transaction-*" \) -print 2>/dev/null)
done

restore_mime="$ABLETON_STATE_HOME/mime-prestate.tsv"
if [ -r "$restore_mime" ] && command -v xdg-mime >/dev/null 2>&1; then
    echo "== restore MIME defaults =="
    while IFS=$'\t' read -r type prior; do
        current="$(xdg-mime query default "$type" 2>/dev/null || true)"
        case "$current" in ableton-live.desktop|"$ABLETON_PROTOCOL_DESKTOP_ID"|"$ABLETON_AUZ_DESKTOP_ID"|wine-protocol-ableton.desktop|wine-extension-auz.desktop|max9.desktop|wine-protocol-c74max.desktop)
            if [ -n "$prior" ]; then
                xdg-mime default "$prior" "$type" || true
            else
                mimeapps="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
                [ -f "$mimeapps" ] && sed -i "\\#^${type//\//\\/}=#d" "$mimeapps" || true
            fi ;;
        esac
    done < "$restore_mime"
fi
update-mime-database "${XDG_DATA_HOME:-$HOME/.local/share}/mime" >/dev/null 2>&1 || true
update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications" >/dev/null 2>&1 || true

if [ "$delete_prefix" -eq 1 ] && [ -e "$safe_prefix" ]; then
    rm -rf -- "$safe_prefix"
    echo "removed $safe_prefix"
else
    echo "kept Wine prefix $safe_prefix"
fi

if [ "$uninstall_partial" -eq 1 ]; then
    echo "!! uninstall left modified managed files in place; ownership state was retained" >&2
    exit 1
fi
if [ -f "$ABLETON_CONFIG_FILE" ] && grep -qF 'managed by the installer' "$ABLETON_CONFIG_FILE"; then
    rm -f -- "$ABLETON_CONFIG_FILE"
fi
safe_cache="$(ableton_path_is_safe_delete_target "$ABLETON_CACHE_HOME")" || safe_cache=""
[ ! -L "$ABLETON_CACHE_HOME" ] || safe_cache=""
[ -z "$safe_cache" ] || rmdir -- "$safe_cache" 2>/dev/null || true
rm -f -- "$manifest" "$restore_mime"
rmdir -- "$ABLETON_CONFIG_HOME" "$ABLETON_DATA_HOME/lib" "$ABLETON_DATA_HOME" 2>/dev/null || true
safe_state="$(ableton_path_is_safe_delete_target "$ABLETON_STATE_HOME")" || safe_state=""
[ ! -L "$ABLETON_STATE_HOME" ] || safe_state=""
if [ -n "$safe_state" ] \
   && [ -f "$safe_state/.ableton-linux-state" ] \
   && grep -qxF 'owner=ableton-linux' "$safe_state/.ableton-linux-state"; then
    rm -rf -- "$safe_state"
elif [ -n "$safe_state" ]; then
    rmdir -- "$safe_state/transactions" "$safe_state/logs" "$safe_state/run" "$safe_state" 2>/dev/null || true
fi
echo "OK: uninstall complete"
