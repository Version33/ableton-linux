#!/usr/bin/env bash
# Prefix- and runtime-scoped Wine lifecycle inspection.  No process is selected
# by a global image-name match: both /proc/PID/exe and WINEPREFIX must match.

_ableton_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F ableton_config_init >/dev/null 2>&1; then
    . "$_ableton_lib_dir/config.sh"
fi
ableton_config_init

ableton_pid_has_env()
{
    local pid="$1" expected="$2"
    [ -r "/proc/$pid/environ" ] || return 1
    tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -Fx -- "$expected" >/dev/null 2>&1
}

ableton_pid_uses_runtime()
{
    local pid="$1" root="${2:-$ABLETON_WINE_ROOT}" exe
    exe="$(readlink -f -- "/proc/$pid/exe" 2>/dev/null || true)"
    root="$(readlink -f -- "$root" 2>/dev/null || printf '%s' "$root")"
    case "$root" in
        /usr|/usr/local)
            case "$exe" in
                "$root"/bin/wine*|"$root"/bin/wineserver|"$root"/lib*/wine/*) return 0 ;;
                *) return 1 ;;
            esac ;;
        *) case "$exe" in "$root"/*) return 0 ;; *) return 1 ;; esac ;;
    esac
}

ableton_pid_uses_prefix()
{
    ableton_pid_has_env "$1" "WINEPREFIX=$ABLETON_WINEPREFIX"
}

ableton_prefix_pids()
{
    local proc pid
    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"
        ableton_pid_uses_runtime "$pid" || continue
        ableton_pid_uses_prefix "$pid" || continue
        printf '%s\n' "$pid"
    done
    return 0
}

ableton_runtime_pids()
{
    local root="${1:-$ABLETON_WINE_ROOT}" proc pid
    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"
        ableton_pid_uses_runtime "$pid" "$root" || continue
        printf '%s\n' "$pid"
    done
    return 0
}

ableton_runtime_busy()
{
    local root="${1:-$ABLETON_WINE_ROOT}" pid
    pid="$(ableton_runtime_pids "$root" | head -n 1)"
    [ -n "$pid" ]
}

ableton_pid_cmdline()
{
    tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null || true
}

ableton_live_pids()
{
    local pid cmd
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        cmd="$(ableton_pid_cmdline "$pid")"
        case "$cmd" in *"Ableton Live"*.exe*) printf '%s\n' "$pid" ;; esac
    done < <(ableton_prefix_pids)
    return 0
}

ableton_max_pids()
{
    local pid cmd
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        cmd="$(ableton_pid_cmdline "$pid")"
        case "$cmd" in *"Max 9"*Max.exe*|*"Cycling '74"*Max.exe*) printf '%s\n' "$pid" ;; esac
    done < <(ableton_prefix_pids)
    return 0
}

ableton_live_running()
{
    local pid
    pid="$(ableton_live_pids | head -n 1)"
    [ -n "$pid" ]
}

ableton_prefix_busy()
{
    local pid
    pid="$(ableton_prefix_pids | head -n 1)"
    [ -n "$pid" ]
}

ableton_lifecycle_runtime_dir()
{
    local base="${XDG_RUNTIME_DIR:-$ABLETON_STATE_HOME/run}" key
    key="$(printf '%s\0%s' "$ABLETON_WINE_ROOT" "$ABLETON_WINEPREFIX" | sha256sum | awk '{print substr($1,1,16)}')"
    printf '%s/ableton-wine/%s\n' "$base" "$key"
}

ableton_wait_for_live()
{
    local seconds="${1:-60}" i
    seconds="$(ableton_timeout_value "$seconds" ABLETON_LAUNCH_TIMEOUT 1 600)" || return 2
    for ((i=0; i<seconds*10; i++)); do
        ableton_live_running && return 0
        sleep 0.1
    done
    return 1
}

ableton_wait_for_pid_exit()
{
    local pid="$1" seconds="${2:-10}" i
    seconds="$(ableton_timeout_value "$seconds" process-timeout 1 120)" || return 2
    for ((i=0; i<seconds*10; i++)); do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.1
    done
    return 1
}

ableton_stop_prefix()
{
    local pid pids
    pids="$(ableton_prefix_pids)"
    [ -n "$pids" ] || return 0
    ableton_run_bounded 15 env WINEPREFIX="$ABLETON_WINEPREFIX" \
        "$ABLETON_WINE_ROOT/bin/wineserver" -k >/dev/null 2>&1 || true
    for pid in $pids; do
        kill -0 "$pid" 2>/dev/null || continue
        kill "$pid" 2>/dev/null || true
    done
    for pid in $pids; do
        ableton_wait_for_pid_exit "$pid" 5 || {
            ableton_pid_uses_runtime "$pid" && ableton_pid_uses_prefix "$pid" && kill -KILL "$pid" 2>/dev/null || true
        }
    done
    ! ableton_prefix_busy
}
