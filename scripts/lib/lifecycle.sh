#!/usr/bin/env bash
# Prefix- and runtime-scoped Wine lifecycle inspection.  No process is selected
# by a global image-name match: both /proc/PID/exe and WINEPREFIX must match.

# Definitions only: callers resolve the configuration themselves, because the
# command line reaches some of them after this file is sourced.
_ableton_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F ableton_config_init >/dev/null 2>&1; then
    . "$_ableton_lib_dir/config.sh"
fi

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

# Windowless agents an install or a session starts and never stops, ended by
# exact name so no application is touched.  MicrosoftEdgeUpdate.exe is Live 12's
# WebView2 updater: under Wine its COM registration fails to validate, so it
# cannot start an update worker and parks in Core::DoRun indefinitely, holding
# the prefix open after everything else has gone.  A Max session leaves the same
# process behind.  The Push images are the USB driver's tray applets.  An image
# that is not running is a no-op, so callers need not know which apply.
ableton_stop_leftover_agents()
{
    local runtime="${1:-$ABLETON_WINE_ROOT}" prefix="${2:-$ABLETON_WINEPREFIX}"
    # wine builds a prefix at any path it is handed, so a caller that gave up
    # because the runtime or prefix was missing must not create one on its way
    # out.  Nothing is running in a prefix that does not exist either.
    [ -x "$runtime/bin/wine" ] || return 0
    [ -f "$prefix/system.reg" ] || return 0
    # One invocation, not one per image: taskkill takes a list, and each wine
    # start costs a second of a user's exit - or fifteen against a prefix that
    # has stopped answering, three times over.
    ableton_run_bounded 15 env WINEPREFIX="$prefix" "$runtime/bin/wine" taskkill /f \
        /im AbletonPushCpl.exe /im tusbaudiocplapp.exe /im MicrosoftEdgeUpdate.exe \
        >/dev/null 2>&1 || true
    return 0
}

# Windows image name from the command line, which carries the full path where
# /proc/PID/comm is truncated at 15 characters - short of most of them.  argv[0]
# is read on its own NUL boundary: every Windows path has a space in it, so
# splitting the joined command line on whitespace yields "Program".
ableton_pid_image()
{
    local image
    image="$(tr '\0' '\n' < "/proc/$1/cmdline" 2>/dev/null | head -n 1)"
    image="${image##*\\}"
    image="${image##*/}"
    # A process that exits while it is being reported leaves nothing to read.
    [ -n "$image" ] || image="$(cat "/proc/$1/comm" 2>/dev/null || true)"
    printf '%s\n' "${image:-unknown}"
}

# End a session: stop the agents it leaves behind, then confirm the prefix
# actually came down rather than assume it.  Wine's own processes exit once the
# last client goes, so a prefix still busy after that grace period is being held
# by something real - a Max, a second Live, or a program the user started in this
# prefix themselves.  That is reported and left alone: at this point we cannot
# tell a user's program from a leftover, and ending the session would take it
# with us.  Returns non-zero when the prefix is still held.
ableton_session_teardown()
{
    local runtime="${1:-$ABLETON_WINE_ROOT}" prefix="${2:-$ABLETON_WINEPREFIX}"
    local seconds="${3:-5}" i pid
    seconds="$(ableton_timeout_value "$seconds" teardown-grace 1 60)" || return 2
    # Nothing to end, and nothing to wait for.  Checked first because taskkill is
    # itself a wine process: on an empty prefix it starts a server and a pair of
    # services that outlive the grace period below, and the teardown would then
    # report the session it started as the thing holding the prefix.
    ableton_prefix_busy || return 0
    ableton_stop_leftover_agents "$runtime" "$prefix" || true
    for ((i=0; i<seconds*10; i++)); do
        ableton_prefix_busy || return 0
        sleep 0.1
    done
    ableton_prefix_busy || return 0
    printf -- '-- the prefix is still in use, so its wineserver stays up for:\n' >&2
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        printf '   %s (pid %s)\n' "$(ableton_pid_image "$pid")" "$pid" >&2
    done < <(ableton_prefix_pids)
    return 1
}

# Wait for every process in the prefix to exit.  Bounded: a resident that outlives
# the command that started it holds the server open indefinitely.
ableton_prefix_wait()
{
    local runtime="${1:-$ABLETON_WINE_ROOT}" prefix="${2:-$ABLETON_WINEPREFIX}"
    ableton_run_bounded 60 env WINEPREFIX="$prefix" \
        "$runtime/bin/wineserver" -w >/dev/null 2>&1
}

# Wait, and on timeout end every process in the prefix and wait again.  The stop is
# indiscriminate, so this is only for a prefix the caller owns outright - a staging
# prefix it just built, or one it is about to remove.  On a prefix the user can
# reach, name the images to end instead and take ableton_prefix_wait's verdict as
# advisory.  wineserver -k shuts down through SIGINT, so the registry is saved.
# Returns 1 when a straggler survived the stop, and the wait's own exit code when
# the wait could not run at all.
ableton_prefix_quiesce()
{
    local runtime="${1:-$ABLETON_WINE_ROOT}" prefix="${2:-$ABLETON_WINEPREFIX}" rc=0
    ableton_prefix_wait "$runtime" "$prefix" || rc=$?
    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    if [ "$rc" -ne 124 ] && [ "$rc" -ne 137 ]; then
        return "$rc"
    fi
    echo "-- a leftover background program is holding the prefix open; stopping it"
    ableton_run_bounded 20 env WINEPREFIX="$prefix" \
        "$runtime/bin/wineserver" -k >/dev/null 2>&1 || true
    ableton_prefix_wait "$runtime" "$prefix" || return 1
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
