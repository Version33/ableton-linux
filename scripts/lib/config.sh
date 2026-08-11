#!/usr/bin/env bash
# Shared, side-effect-free configuration and bounded-process helpers.
# Source this file, then call ableton_config_init.  Values are resolved in this
# order: an already-exported environment variable, the persistent config, then
# the compatibility default.  The .run CLI exports its resolved arguments, so
# command-line values naturally outrank the environment.

ABLETON_RUNTIME_NAME="wine-d2d1-nspa-11.13"

ableton_config_error()
{
    printf '!! %s\n' "$*" >&2
    return 1
}

ableton_require_home()
{
    [ -n "${HOME:-}" ] || ableton_config_error "HOME is not set"
}

ableton_config_file_value()
{
    local wanted="$1" line key value
    [ -r "$ABLETON_CONFIG_FILE" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        key="${line%%=*}"
        value="${line#*=}"
        [ "$key" = "$wanted" ] || continue
        printf '%s\n' "$value"
        return 0
    done < "$ABLETON_CONFIG_FILE"
    return 1
}

ableton_config_init()
{
    ableton_require_home || return 1

    : "${ABLETON_DATA_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/ableton-wine}"
    : "${ABLETON_CONFIG_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/ableton-wine}"
    : "${ABLETON_STATE_HOME:=${XDG_STATE_HOME:-$HOME/.local/state}/ableton-wine}"
    : "${ABLETON_CACHE_HOME:=${XDG_CACHE_HOME:-$HOME/.cache}/ableton-wine}"
    : "${ABLETON_BIN_HOME:=$HOME/.local/bin}"
    : "${ABLETON_CONFIG_FILE:=$ABLETON_CONFIG_HOME/config}"

    local configured
    if [ -z "${ABLETON_WINE_ROOT+x}" ]; then
        configured="$(ableton_config_file_value runtime_root 2>/dev/null || true)"
        ABLETON_WINE_ROOT="${configured:-$HOME/.local/opt/$ABLETON_RUNTIME_NAME}"
    fi
    if [ -z "${ABLETON_WINEPREFIX+x}" ]; then
        configured="$(ableton_config_file_value prefix 2>/dev/null || true)"
        ABLETON_WINEPREFIX="${configured:-$HOME/.wine-ableton}"
    fi
    if [ -z "${ABLETON_LINK_MODE+x}" ]; then
        configured="$(ableton_config_file_value link_mode 2>/dev/null || true)"
        if [ -z "$configured" ]; then
            case "$(sed -n '1p' "$ABLETON_DATA_HOME/link-configured" 2>/dev/null || true)" in
                configured) configured=session ;;
                declined) configured=off ;;
            esac
            if [ -L "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/default.target.wants/ableton-linkd.service" ]; then
                configured=always
            fi
        fi
        ABLETON_LINK_MODE="${configured:-off}"
    fi
    if [ -z "${ABLETON_LIVE_VERSION+x}" ]; then
        configured="$(ableton_config_file_value live_major 2>/dev/null || true)"
        [ -z "$configured" ] || ABLETON_LIVE_VERSION="$configured"
    fi
    if [ -z "${ABLETON_LINKD+x}" ]; then
        configured="$(ableton_config_file_value linkd 2>/dev/null || true)"
        ABLETON_LINKD="${configured:-$ABLETON_DATA_HOME/ableton-linkd}"
    fi

    case "$ABLETON_LINK_MODE" in off|session|always) ;;
        *) ableton_config_error "link mode must be off, session, or always (got '$ABLETON_LINK_MODE')"; return 1 ;;
    esac
    case "${ABLETON_LIVE_VERSION:-}" in ''|11|12) ;;
        *) ableton_config_error "Live major must be 11 or 12 (got '$ABLETON_LIVE_VERSION')"; return 1 ;;
    esac
    for configured in "$ABLETON_WINE_ROOT" "$ABLETON_WINEPREFIX" "$ABLETON_DATA_HOME" \
                      "$ABLETON_CONFIG_HOME" "$ABLETON_STATE_HOME" "$ABLETON_CACHE_HOME"; do
        [ -n "$configured" ] || { ableton_config_error "a resolved installation path is empty"; return 1; }
        case "$configured" in *$'\n'*|*$'\r'*|*$'\t'*)
            ableton_config_error "installation paths may not contain newlines or tabs"; return 1 ;;
        esac
    done

    ABLETON_WINE_ROOT="$(ableton_realpath_m "$ABLETON_WINE_ROOT")" || return 1
    ABLETON_WINEPREFIX="$(ableton_realpath_m "$ABLETON_WINEPREFIX")" || return 1
    ABLETON_DATA_HOME="$(ableton_realpath_m "$ABLETON_DATA_HOME")" || return 1
    ABLETON_CONFIG_HOME="$(ableton_realpath_m "$ABLETON_CONFIG_HOME")" || return 1
    ABLETON_STATE_HOME="$(ableton_realpath_m "$ABLETON_STATE_HOME")" || return 1
    ABLETON_CACHE_HOME="$(ableton_realpath_m "$ABLETON_CACHE_HOME")" || return 1
    ABLETON_BIN_HOME="$(ableton_realpath_m "$ABLETON_BIN_HOME")" || return 1
    ABLETON_CONFIG_FILE="$(ableton_realpath_m "$ABLETON_CONFIG_FILE")" || return 1
    ABLETON_LINKD="$(ableton_realpath_m "$ABLETON_LINKD")" || return 1

    local -a independent_paths=("$ABLETON_WINE_ROOT" "$ABLETON_WINEPREFIX" "$ABLETON_DATA_HOME" \
        "$ABLETON_CONFIG_HOME" "$ABLETON_STATE_HOME" "$ABLETON_CACHE_HOME")
    local i j first second
    for ((i=0; i<${#independent_paths[@]}; i++)); do
        first="$(ableton_realpath_m "${independent_paths[i]}")" || return 1
        for ((j=i+1; j<${#independent_paths[@]}; j++)); do
            second="$(ableton_realpath_m "${independent_paths[j]}")" || return 1
            if [ "$first" = "$second" ] || [[ "$first" = "$second/"* ]] || [[ "$second" = "$first/"* ]]; then
                ableton_config_error "installation roots overlap: $first and $second"
                return 1
            fi
        done
    done

    export ABLETON_WINE_ROOT ABLETON_WINEPREFIX ABLETON_LINK_MODE ABLETON_LINKD
    export ABLETON_DATA_HOME ABLETON_CONFIG_HOME ABLETON_STATE_HOME ABLETON_CACHE_HOME
    export ABLETON_BIN_HOME ABLETON_CONFIG_FILE
}

ableton_write_config()
{
    ableton_config_init || return 1
    local tmp major="${ABLETON_LIVE_VERSION:-}"
    mkdir -p -- "$ABLETON_CONFIG_HOME"
    tmp="$(mktemp "$ABLETON_CONFIG_HOME/.config.XXXXXX")" || return 1
    chmod 600 "$tmp"
    {
        printf '# ableton-linux installer configuration; managed by the installer\n'
        printf 'format=1\n'
        printf 'runtime_root=%s\n' "$ABLETON_WINE_ROOT"
        printf 'prefix=%s\n' "$ABLETON_WINEPREFIX"
        printf 'live_major=%s\n' "$major"
        printf 'link_mode=%s\n' "$ABLETON_LINK_MODE"
        printf 'linkd=%s\n' "$ABLETON_LINKD"
    } > "$tmp"
    mv -f -- "$tmp" "$ABLETON_CONFIG_FILE"
}

ableton_mark_state_home()
{
    ableton_config_init || return 1
    if [ -d "$ABLETON_STATE_HOME" ] \
       && [ ! -e "$ABLETON_STATE_HOME/.ableton-linux-state" ] \
       && [ "$(basename "$ABLETON_STATE_HOME")" != ableton-wine ] \
       && find "$ABLETON_STATE_HOME" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
        ableton_config_error "refusing to claim nonempty unmarked state directory $ABLETON_STATE_HOME"
        return 1
    fi
    mkdir -p -- "$ABLETON_STATE_HOME"
    if [ ! -e "$ABLETON_STATE_HOME/.ableton-linux-state" ]; then
        printf 'format=1\nowner=ableton-linux\n' > "$ABLETON_STATE_HOME/.ableton-linux-state"
        chmod 600 "$ABLETON_STATE_HOME/.ableton-linux-state"
    fi
}

ableton_timeout_value()
{
    local value="$1" name="$2" min="${3:-1}" max="${4:-86400}"
    case "$value" in ''|*[!0-9]*) ableton_config_error "$name must be a whole number of seconds"; return 1 ;; esac
    [ "$value" -ge "$min" ] && [ "$value" -le "$max" ] || {
        ableton_config_error "$name must be between $min and $max seconds"
        return 1
    }
    printf '%s\n' "$value"
}

ableton_run_bounded()
{
    local seconds="$1"; shift
    seconds="$(ableton_timeout_value "$seconds" timeout 1 86400)" || return 2
    command -v timeout >/dev/null 2>&1 || {
        ableton_config_error "GNU timeout is required to supervise external processes"
        return 127
    }
    timeout --signal=TERM --kill-after=5s "${seconds}s" "$@"
}

ableton_realpath_m()
{
    if command -v realpath >/dev/null 2>&1; then
        realpath -m -- "$1"
    else
        readlink -m -- "$1"
    fi
}

ableton_path_is_safe_delete_target()
{
    local raw="$1" resolved home_resolved home_parent
    [ -n "$raw" ] || return 1
    resolved="$(ableton_realpath_m "$raw")" || return 1
    home_resolved="$(ableton_realpath_m "$HOME")" || return 1
    home_parent="$(dirname "$home_resolved")"
    case "$resolved" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|"$home_resolved"|"$home_parent") return 1 ;;
    esac
    [ "${#resolved}" -gt 4 ] || return 1
    printf '%s\n' "$resolved"
}
