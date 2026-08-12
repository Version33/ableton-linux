#!/usr/bin/env bash
# File-level transaction and ownership manifest helpers for installer components.
# Paths containing newlines are rejected by config.sh; tab is rejected here so
# the on-disk records remain simple and auditable.

declare -Ag ABLETON_TXN_SEEN=()
declare -ag ABLETON_OWNED_PATHS=()
declare -Ag ABLETON_OWNED_KINDS=()

ableton_manifest_path_ok()
{
    case "$1" in *$'\n'*|*$'\r'*|*$'\t'*)
        ableton_config_error "managed path contains a newline or tab: $1"; return 1 ;;
    esac
}

ableton_txn_init()
{
    [ -n "${ABLETON_TRANSACTION_DIR:-}" ] || return 0
    mkdir -p -- "$ABLETON_TRANSACTION_DIR/files"
    : > "$ABLETON_TRANSACTION_DIR/active"
    touch "$ABLETON_TRANSACTION_DIR/files.tsv"
}

ableton_txn_snapshot()
{
    local path="$1" id backup
    [ -n "${ABLETON_TRANSACTION_DIR:-}" ] || return 0
    ableton_manifest_path_ok "$path" || return 1
    [ -z "${ABLETON_TXN_SEEN[$path]+x}" ] || return 0
    ABLETON_TXN_SEEN["$path"]=1
    id="$(wc -l < "$ABLETON_TRANSACTION_DIR/files.tsv")"
    backup="$ABLETON_TRANSACTION_DIR/files/$id"
    if [ -e "$path" ] || [ -L "$path" ]; then
        cp -a -- "$path" "$backup"
        printf 'present\t%s\t%s\n' "$path" "$backup" >> "$ABLETON_TRANSACTION_DIR/files.tsv"
    else
        printf 'absent\t%s\t-\n' "$path" >> "$ABLETON_TRANSACTION_DIR/files.tsv"
    fi
}

ableton_record_owned()
{
    ableton_manifest_path_ok "$1" || return 1
    ABLETON_OWNED_PATHS+=("$1")
    ABLETON_OWNED_KINDS["$1"]="${2:-file}"
}

ableton_legacy_owned_path()
{
    local path="$1" data_root="${XDG_DATA_HOME:-$HOME/.local/share}"
    case "$path" in
        "$ABLETON_DATA_HOME/ableton-linkd")
            strings "$path" 2>/dev/null | grep -qF 'ableton-linkd: native Ableton Link session anchor and probe' ;;
        "$ABLETON_DATA_HOME/setup-link.sh") grep -qF 'Ableton Link setup' "$path" 2>/dev/null ;;
        "$ABLETON_DATA_HOME/ableton-linkctl") grep -qF 'Project-owned Ableton Link lifecycle controller' "$path" 2>/dev/null ;;
        "$ABLETON_DATA_HOME/ableton-linkd.service") grep -qF 'ableton-linkd' "$path" 2>/dev/null ;;
        "$ABLETON_DATA_HOME/VERSION") grep -Eq '^20[0-9]{2}[.]' "$path" 2>/dev/null ;;
        "$ABLETON_DATA_HOME/wine-protocol-ableton.desktop"|"$ABLETON_DATA_HOME/wine-extension-auz.desktop")
            grep -Eqi 'ableton|auz' "$path" 2>/dev/null ;;
        "$ABLETON_DATA_HOME/detect-scale.sh") grep -qF 'Sourceable display-scale detection' "$path" 2>/dev/null ;;
        "$ABLETON_DATA_HOME/detect-theme.sh") grep -qF 'Sourceable theme detection helpers' "$path" 2>/dev/null ;;
        "$ABLETON_DATA_HOME/shortcut-hold.sh") grep -qF 'GNOME shortcut hold' "$path" 2>/dev/null ;;
        "$ABLETON_DATA_HOME/setsyscolors.exe"|"$ABLETON_DATA_HOME/learnheal.exe") return 0 ;;
        "$ABLETON_BIN_HOME/ableton-live") grep -qF 'Ableton Live launcher for the patched Wine stack' "$path" 2>/dev/null ;;
        "$ABLETON_BIN_HOME/max9") grep -qF 'Max 9 launcher' "$path" 2>/dev/null ;;
        "$data_root/applications/ableton-live.desktop"|\
        "$data_root/applications/max9.desktop"|\
        "$data_root/applications/wine-protocol-ableton.desktop"|\
        "$data_root/applications/wine-extension-auz.desktop"|\
        "$data_root/applications/wine-protocol-c74max.desktop")
            grep -Eqi 'ableton|c74max' "$path" 2>/dev/null ;;
        "$data_root/mime/packages/x-wine-extension-auz.xml"|\
        "$data_root/mime/packages/application-ableton-live.xml")
            grep -qF 'ableton' "$path" 2>/dev/null ;;
        *) return 1 ;;
    esac
}

ableton_persist_file_prestate()
{
    local target="$1" source="${2:-}" manifest="$ABLETON_STATE_HOME/install-manifest.tsv"
    local index="$ABLETON_STATE_HOME/install-prestate.tsv" id backup expected current
    [ -e "$target" ] || [ -L "$target" ] || return 0
    [ -z "$source" ] || ! cmp -s -- "$source" "$target" || return 0
    if [ -r "$manifest" ]; then
        expected="$(awk -F '\t' -v p="$target" '($1=="file" || $1=="config") && $2==p { print $3; exit }' "$manifest")"
        if [ -n "$expected" ]; then
            current="$(sha256sum -- "$target" 2>/dev/null | awk '{print $1}')"
            [ "$current" = "$expected" ] && return 0
            ableton_config_error "refusing to overwrite modified managed file $target"
            return 1
        fi
    fi
    if [ -r "$index" ] && awk -F '\t' -v p="$target" '$2==p { found=1 } END { exit !found }' "$index"; then
        return 0
    fi
    ableton_legacy_owned_path "$target" && return 0
    ableton_mark_state_home
    mkdir -p -- "$ABLETON_STATE_HOME/install-prestate"
    ableton_txn_snapshot "$index"
    [ -e "$index" ] || : > "$index"
    id="$(printf '%s' "$target" | sha256sum | awk '{print $1}')"
    backup="$ABLETON_STATE_HOME/install-prestate/$id"
    ableton_txn_snapshot "$backup"
    cp -a -- "$target" "$backup"
    printf 'present\t%s\t%s\n' "$target" "$backup" >> "$index"
}

ableton_install_file()
{
    local mode="$1" source="$2" target="$3" kind="${4:-file}"
    ableton_persist_file_prestate "$target" "$source"
    ableton_txn_snapshot "$target"
    mkdir -p -- "$(dirname "$target")"
    install -m "$mode" -- "$source" "$target"
    ableton_record_owned "$target" "$kind"
}

ableton_copy_file()
{
    local source="$1" target="$2" kind="${3:-file}"
    ableton_persist_file_prestate "$target" "$source"
    ableton_txn_snapshot "$target"
    mkdir -p -- "$(dirname "$target")"
    cp -f -- "$source" "$target"
    ableton_record_owned "$target" "$kind"
}

ableton_remove_managed_file()
{
    local target="$1"
    ableton_txn_snapshot "$target"
    rm -f -- "$target"
}

ableton_write_ownership_manifest()
{
    local manifest="$ABLETON_STATE_HOME/install-manifest.tsv" tmp path digest
    local -A touched=()
    ableton_mark_state_home
    ableton_txn_snapshot "$manifest"
    tmp="$(mktemp "$ABLETON_STATE_HOME/.manifest.XXXXXX")"
    # Preserve records for components this invocation did not touch.  Touched
    # paths are replaced below by their new digest.
    for path in "${ABLETON_OWNED_PATHS[@]}"; do touched["$path"]=1; done
    if [ -r "$manifest" ]; then
        while IFS=$'\t' read -r kind path digest; do
            [ -n "$path" ] || continue
            [ -z "${touched[$path]+x}" ] || continue
            printf '%s\t%s\t%s\n' "$kind" "$path" "$digest" >> "$tmp"
        done < "$manifest"
    fi
    for path in "${ABLETON_OWNED_PATHS[@]}"; do
        [ -f "$path" ] || [ -L "$path" ] || continue
        digest="$(sha256sum -- "$path" | awk '{print $1}')"
        printf '%s\t%s\t%s\n' "${ABLETON_OWNED_KINDS[$path]:-file}" "$path" "$digest" >> "$tmp"
    done
    if [ "${ABLETON_RUNTIME_INSTALLED:-0}" -eq 1 ]; then
        printf 'runtime\t%s\t%s\n' "$ABLETON_WINE_ROOT" "$ABLETON_RUNTIME_NAME" >> "$tmp"
    fi
    sort -u "$tmp" -o "$tmp"
    chmod 600 "$tmp"
    mv -f -- "$tmp" "$manifest"
}

ableton_txn_rollback_files()
{
    local txn="$1" reversed status path backup
    [ -r "$txn/files.tsv" ] || return 0
    reversed="$txn/files.reverse.tsv"
    tac "$txn/files.tsv" > "$reversed"
    while IFS=$'\t' read -r status path backup; do
        [ -n "$path" ] || continue
        case "$status" in
            absent) rm -f -- "$path" ;;
            present)
                rm -f -- "$path"
                mkdir -p -- "$(dirname "$path")"
                cp -a -- "$backup" "$path" ;;
        esac
    done < "$reversed"
}
