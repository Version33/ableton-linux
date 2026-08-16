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

# The prefix and runtime default to the configured pair, but every walker below
# takes them, so a caller working on a prefix that is not the configured one -
# setup-prefix.sh, inside its staging window - inspects the prefix it named
# rather than the user's.
ableton_pid_uses_prefix()
{
    ableton_pid_has_env "$1" "WINEPREFIX=${2:-$ABLETON_WINEPREFIX}"
}

ableton_prefix_pids()
{
    local root="${1:-$ABLETON_WINE_ROOT}" prefix="${2:-$ABLETON_WINEPREFIX}" proc pid
    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"
        ableton_pid_uses_runtime "$pid" "$root" || continue
        ableton_pid_uses_prefix "$pid" "$prefix" || continue
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
    pid="$(ableton_prefix_pids "${1:-}" "${2:-}" | head -n 1)"
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

# Windowless agents Live and Max leave behind, ended by exact name so no
# application is touched.  A name that is not running is a no-op.
ableton_stop_leftover_agents()
{
    local runtime="${1:-$ABLETON_WINE_ROOT}" prefix="${2:-$ABLETON_WINEPREFIX}"
    # wine builds a prefix at any path it is handed; a refusal must not create one.
    [ -x "$runtime/bin/wine" ] || return 0
    [ -f "$prefix/system.reg" ] || return 0
    # One invocation: taskkill takes a list, and each wine start costs exit latency.
    ableton_run_bounded 15 env WINEPREFIX="$prefix" "$runtime/bin/wine" taskkill /f \
        /im AbletonPushCpl.exe /im tusbaudiocplapp.exe /im MicrosoftEdgeUpdate.exe \
        >/dev/null 2>&1 || true
    return 0
}

# Wine's own processes, alive only while a client is.  Naming them in a report
# buries the one process that is actually holding the prefix.
ableton_wine_own_image()
{
    case "$1" in
        services.exe|winedevice.exe|plugplay.exe|svchost.exe|rpcss.exe|explorer.exe|\
        winemenubuilder.exe|start.exe|conhost.exe|wineboot.exe|rundll32.exe|wineserver)
            return 0 ;;
    esac
    return 1
}

# The prefix's processes worth reporting: everything Wine did not start itself.
ableton_prefix_holders()
{
    local pid image
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        image="$(ableton_pid_image "$pid")"
        ableton_wine_own_image "$image" && continue
        printf '%s\t%s\n' "$pid" "$image"
    done < <(ableton_prefix_pids "${1:-}" "${2:-}")
    return 0
}

# A helper this project installed and started, asked by the data home rather than
# by name so it stays right as helpers come and go.  Each carries its own exit
# contract - learnheal.exe outlives Live deliberately, to heal the Learn View
# pane - so one still running does not mean the session is unfinished.
ableton_vendored_helper_image()
{
    [ -n "${ABLETON_DATA_HOME:-}" ] || return 1
    [ -f "$ABLETON_DATA_HOME/$1" ]
}

# Holders that are somebody else's: a Max, a second Live, a program the user
# started.  These are the ones worth naming.  Reads a holder list so a caller
# that already walked /proc need not walk it again.
ableton_unknown_holders()
{
    local pid image
    while IFS="$(printf '\t')" read -r pid image; do
        [ -n "$pid" ] || continue
        ableton_vendored_helper_image "$image" && continue
        printf '%s\t%s\n' "$pid" "$image"
    done
    return 0
}

ableton_prefix_unknown_holders()
{
    ableton_prefix_holders "${1:-}" "${2:-}" | ableton_unknown_holders
}

# Windows image name.  comm truncates at 15 characters, and argv[0] must be read
# on its NUL boundary: split on whitespace and every C:\Program Files path is "Program".
ableton_pid_image()
{
    local image
    # 2>/dev/null first: redirections are applied left to right, so with the input
    # last the open failure is reported before stderr has been silenced.
    image="$(tr '\0' '\n' 2>/dev/null < "/proc/$1/cmdline" | head -n 1)"
    image="${image##*\\}"
    image="${image##*/}"
    # A process that exits while it is being reported leaves nothing to read.
    [ -n "$image" ] || image="$(cat "/proc/$1/comm" 2>/dev/null || true)"
    printf '%s\n' "${image:-unknown}"
}

# End a session's agents, then confirm the prefix came down.  Whatever still holds
# it is a Max, a second Live or the user's own program - reported, never ended,
# since none of them is distinguishable from a leftover here.  Non-zero if held.
# Callers name themselves through ABLETON_SESSION_LABEL, which each launcher sets
# on the call; unset reads as "the session".
ableton_session_teardown()
{
    local runtime="${1:-$ABLETON_WINE_ROOT}" prefix="${2:-$ABLETON_WINEPREFIX}"
    local seconds="${3:-1}" pid image holders unknown=""
    seconds="$(ableton_timeout_value "$seconds" teardown-settle 1 60)" || return 2
    # First: taskkill is itself a wine process, so on an empty prefix it would start
    # a server and services that outlive the grace period and be reported as holders.
    ableton_prefix_busy "$runtime" "$prefix" || return 0
    ableton_stop_leftover_agents "$runtime" "$prefix" || true
    # One beat for the agents just ended to go, then one look.  Not a poll: each
    # look walks every pid on the machine, and there is nothing to wait for -
    # Wine's own processes are already filtered out, and whatever else is here is
    # an application, which will not leave within a grace period.
    sleep "$seconds"
    holders="$(ableton_prefix_holders "$runtime" "$prefix")"
    [ -n "$holders" ] || return 0
    unknown="$(printf '%s\n' "$holders" | ableton_unknown_holders)"
    # Ours alone: the session is over, the helper finishes on its own, and the
    # server goes with it.  Said out loud because a wineserver outliving the
    # window looks like the bug this teardown exists to prevent.
    if [ -z "$unknown" ]; then
        printf -- '-- %s closed; a background helper is still finishing and will quit on its own\n' \
            "${ABLETON_SESSION_LABEL:-the session}" >&2
        return 0
    fi
    printf -- '-- %s closed. Other unknown processes were left running:\n' \
        "${ABLETON_SESSION_LABEL:-the session}" >&2
    # Here-string, not a pipe from printf '%s': command substitution stripped the
    # trailing newline above, and read drops an unterminated final line.
    while IFS="$(printf '\t')" read -r pid image; do
        [ -n "$pid" ] || continue
        printf '   %s (pid %s)\n' "$image" "$pid" >&2
    done <<< "$unknown"
    # Naming them is half an answer: someone who wants them gone needs the means,
    # and the paths are the ones this session actually used.  Printed rather than
    # run, because whether they should go is the user's call.
    printf -- '-- Ableton-Linux helpers close themselves once the prefix is free. To kill the prefix forcefully instead:\n' >&2
    printf -- '   WINEPREFIX=%s %s/bin/wineserver -k\n' "$prefix" "$runtime" >&2
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

# The same wait, naming what it waits on every 15s: a silent minute in front of an
# installer reads as a hang.  Same bounded wait, same exit code.  Ticks go to
# stdout, where the rest of the install narrative goes; the teardown's messages
# go to stderr, being diagnostics after an application has closed.
ableton_prefix_wait_progress()
{
    local runtime="${1:-$ABLETON_WINE_ROOT}" prefix="${2:-$ABLETON_WINEPREFIX}"
    local waiter rc=0 elapsed=0 names
    ableton_run_bounded 60 env WINEPREFIX="$prefix" \
        "$runtime/bin/wineserver" -w >/dev/null 2>&1 &
    waiter=$!
    while kill -0 "$waiter" 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed + 1))
        [ "$((elapsed % 15))" -eq 0 ] || continue
        names="$(ableton_prefix_unknown_holders "$runtime" "$prefix" \
            | cut -f2 | sort -u | tr '\n' ' ')"
        [ -z "${names// /}" ] \
            || printf -- '   still waiting for the prefix to settle (%ss): %s\n' \
                "$elapsed" "$names"
    done
    wait "$waiter" || rc=$?
    return "$rc"
}

# Wait, and on timeout end every process in the prefix and wait again.  The stop is
# indiscriminate: only for a prefix the caller owns outright, never one a user can
# reach.  Returns 1 if a straggler survived, else the wait's own exit code.
ableton_prefix_quiesce()
{
    local runtime="${1:-$ABLETON_WINE_ROOT}" prefix="${2:-$ABLETON_WINEPREFIX}" rc=0
    ableton_prefix_wait_progress "$runtime" "$prefix" || rc=$?
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
