#!/usr/bin/env bash
# Collect a focused Nouveau/Mesa/Wine/Ableton crash report.

set -u
ORIGINAL_UMASK=$(umask)
umask 077

PROGRAM=${0##*/}
COLLECTOR_VERSION=2026-08-18.1
RUN_LIVE=0
USE_SUDO=0
PROBES=1
LIVE_ARGS=()

usage() {
    cat <<EOF
Collect logs about graphics crashes and freezes in Ableton Live.

The script saves the logs as a .tar.gz file in the folder you run it from.

Usage:

  bash $PROGRAM [--sudo] [--no-probes]

      Run this after a crash, a freeze or after an unexpected reboot. It
      reads existing logs from the current and previous session.

  bash $PROGRAM [--sudo] [--no-probes] --run [-- your-set.als]

      Run this if you can make the problem happen on demand. Live starts
      with extra logging, so you can reproduce the problem, then close
      Live. The script writes the report when Live closes.

Options:
  --sudo       Grant the script permission to read your full kernel logs.
               The script asks for your password and uses it for the log
               commands only. Do not run the entire script with sudo.
  --no-probes  Skip the graphics driver checks. Use this only if the script
               stops and never finishes.
  --run        Start Ableton Live, then wait for it to close. To open the
               Live Set that crashes, write -- and then the path to it:
               --run -- ~/Music/my-project.als
  -h           Show this help.
EOF
}

while (($#)); do
    case $1 in
        --sudo) USE_SUDO=1; shift ;;
        --no-probes) PROBES=0; shift ;;
        --run) RUN_LIVE=1; shift ;;
        --) shift; LIVE_ARGS=("$@"); break ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if (( ! RUN_LIVE )) && (( ${#LIVE_ARGS[@]} )); then
    printf -- '-- needs --run. Use: bash %s --run -- your-set.als\n' "$PROGRAM" >&2
    exit 2
fi

if (( EUID == 0 )); then
    printf 'Do not run this whole script with sudo. Use: bash %s --sudo\n' "$PROGRAM" >&2
    exit 2
fi

if (( USE_SUDO )); then
    if ! command -v sudo >/dev/null 2>&1; then
        printf 'sudo is not installed; rerun without --sudo.\n' >&2
        exit 2
    fi
    printf 'Requesting sudo for read-only kernel and system log access...\n'
    sudo -v || exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
OUT_DIR=$PWD
WORK_DIR=$(mktemp -d "$OUT_DIR/nouveau-ableton-report-$STAMP.work.XXXXXX") || exit 1
REPORT_NAME="nouveau-ableton-report-$STAMP"
REPORT_DIR="$WORK_DIR/$REPORT_NAME"
mkdir -p "$REPORT_DIR"/{system,gpu,logs,ableton}

cleanup() {
    local rc=$?
    if (( rc != 0 )); then
        printf 'Collection stopped. Partial files remain in: %s\n' "$WORK_DIR" >&2
    fi
}
trap cleanup EXIT

have() { command -v "$1" >/dev/null 2>&1; }

as_root() {
    if (( USE_SUDO )); then
        sudo -- "$@"
    else
        "$@"
    fi
}

with_timeout() {
    local seconds=$1
    shift
    if have timeout; then
        timeout -k 5 "$seconds" "$@"
    else
        "$@"
    fi
}

capture() {
    local file=$1 title=$2
    shift 2
    {
        printf '# %s\n' "$title"
        printf '# command:'
        printf ' %q' "$@"
        printf '\n\n'
        "$@"
        local rc=$?
        printf '\n# exit status: %d\n' "$rc"
    } >"$file" 2>&1
}

copy_tail() {
    local source=$1 destination=$2 lines=${3:-6000}
    if [[ -r $source ]]; then
        {
            printf '# Source: %s\n' "$source"
            printf '# Last %s lines\n\n' "$lines"
            tail -n "$lines" -- "$source"
        } >"$destination" 2>&1
    fi
}

# Cap a file the --run session wrote without a bound. Keeps the start, where
# Mesa logs its driver selection, and the end, where the crash evidence is.
trim_log() {
    local file=$1 total
    [[ -f $file ]] || return 0
    total=$(wc -l <"$file")
    (( total <= 20000 )) && return 0
    {
        head -n 2000 -- "$file"
        printf '\n# %d middle lines removed to keep the report small\n\n' "$((total - 20000))"
        tail -n 18000 -- "$file"
    } >"$file.trim" && mv -- "$file.trim" "$file"
}

filter_journal() {
    local boot=$1 journal_rc
    as_root journalctl --no-pager --no-hostname -b "$boot" -o short-precise |
        grep -Eai 'nouveau|\bnvk\b|zink|drm|gpu|gsp|xid|fifo|mmu|pt_not_present|page_not_present|ctxsw|sched_error|runlist|channel|xwayland|kwin|gnome-shell|plasmashell|gamescope|sway|hyprland|wayfire|labwc|niri|\briver\b|weston|wlroots|wine|ableton|segfault|general protection|oom|out of memory|aer:|pcie|mce:'
    journal_rc=${PIPESTATUS[0]}
    if (( journal_rc )); then
        printf '# journalctl exit status: %d\n' "$journal_rc"
    fi
    return 0
}

package_versions() {
    if have pacman; then
        printf '## pacman\n'
        pacman -Q 2>/dev/null | grep -Eai '^(linux|mesa|lib32-mesa|vulkan|libdrm|xf86-video-nouveau|wine|wayland|xorg|kwin|mutter)' || true
    fi
    if have dpkg-query; then
        printf '\n## dpkg\n'
        dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null |
            grep -Eai '^(linux-image|linux-modules|mesa|libgl|libegl|libvulkan|vulkan|libdrm|xserver-xorg-video-nouveau|wine|wayland|xwayland|kwin|mutter)' || true
    fi
    if have rpm; then
        printf '\n## rpm\n'
        rpm -qa 2>/dev/null | sort |
            grep -Eai '^(kernel|mesa|libgl|libegl|vulkan|libdrm|xorg-x11-drv-nouveau|wine|wayland|xwayland|kwin|mutter)' || true
    fi
    if have flatpak; then
        printf '\n## Flatpak graphics runtimes\n'
        flatpak list --runtime --columns=application,version,branch 2>/dev/null |
            grep -Eai 'org\.freedesktop|mesa|nvidia' || true
    fi
}

gpu_sysfs() {
    local card device key value
    for card in /sys/class/drm/card[0-9]*; do
        [[ -e $card/device ]] || continue
        device=$card/device
        printf '## %s\n' "${card##*/}"
        printf 'path=%s\n' "$(readlink -f "$device" 2>/dev/null || true)"
        printf 'driver=%s\n' "$(basename "$(readlink -f "$device/driver" 2>/dev/null)" 2>/dev/null || true)"
        for key in vendor device subsystem_vendor subsystem_device revision class modalias \
                   current_link_speed current_link_width max_link_speed max_link_width \
                   power/runtime_status power/runtime_suspended_time power/control; do
            if [[ -r $device/$key ]]; then
                value=$(<"$device/$key")
                printf '%s=%s\n' "$key" "$value"
            fi
        done
        printf '\n'
    done
}

module_parameters() {
    local file
    if [[ ! -d /sys/module/nouveau/parameters ]]; then
        printf 'nouveau module parameters are unavailable (module may not be loaded).\n'
        return
    fi
    for file in /sys/module/nouveau/parameters/*; do
        [[ -e $file ]] || continue
        printf '%s=' "${file##*/}"
        cat "$file" 2>&1 || true
    done
}

relevant_environment() {
    local key
    for key in DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP DESKTOP_SESSION \
        ABLETON_WINEPREFIX ABLETON_WINE_ROOT ABLETON_VDESK ABLETON_DPI_MODE ABLETON_DCOMP \
        WINEPREFIX WINEDEBUG WINE_D3D_CONFIG WINED3D_DCOMP_FORCE_FULL_REDRAW \
        WINE_D3D_FORCE_GPU_RENDERING WINE_DISABLE_GL_PRESENT WINE_X11_FORCE_OFFSCREEN_CLASS \
        WINE_WIN32_FULLSCREEN_CLASS WINE_WIN32_RESIZABLE_CLASS \
        MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER DRI_PRIME LIBGL_ALWAYS_SOFTWARE \
        VK_DRIVER_FILES VK_ICD_FILENAMES NVK_DEBUG NAK_DEBUG ZINK_DEBUG; do
        if [[ -v $key ]]; then
            printf '%s=%q\n' "$key" "${!key}"
        else
            printf '%s=<unset>\n' "$key"
        fi
    done
}

vulkan_files() {
    local dir file
    for dir in /etc/vulkan/icd.d /usr/local/share/vulkan/icd.d /usr/share/vulkan/icd.d; do
        [[ -d $dir ]] || continue
        for file in "$dir"/*.json; do
            [[ -r $file ]] || continue
            printf '## %s\n' "$file"
            cat "$file"
            printf '\n'
        done
    done
}

# Read one key from the launcher config, the way the launcher itself does:
# skip blank and comment lines, split at the first '=', exact key match,
# value taken verbatim, first match wins.
config_value() {
    local config=$1 wanted=$2 line key
    while IFS= read -r line || [[ -n $line ]]; do
        case $line in ''|'#'*) continue ;; esac
        key=${line%%=*}
        [[ $key == "$wanted" ]] || continue
        printf '%s\n' "${line#*=}"
        return 0
    done <"$config"
    return 1
}

ableton_paths() {
    local config_home state_dir data_dir config prefix runtime_root
    config_home=${XDG_CONFIG_HOME:-$HOME/.config}
    state_dir=${ABLETON_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/ableton-wine}
    data_dir=${ABLETON_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ableton-wine}
    config="$config_home/ableton-wine/config"

    # Match the launcher's resolution order: environment override first, then
    # the config file, then the default. The launcher ignores a generic
    # WINEPREFIX, so this script ignores it too.
    prefix=${ABLETON_WINEPREFIX:-}
    runtime_root=${ABLETON_WINE_ROOT:-}
    if [[ -r $config ]]; then
        cp -L -- "$config" "$REPORT_DIR/ableton/ableton-wine-config.txt" 2>/dev/null || true
        [[ -n $prefix ]] || prefix=$(config_value "$config" prefix) || prefix=''
        [[ -n $runtime_root ]] || runtime_root=$(config_value "$config" runtime_root) || runtime_root=''
    fi
    prefix=${prefix:-$HOME/.wine-ableton}
    runtime_root=${runtime_root:-$HOME/.local/opt/wine-d2d1-nspa-11.13}

    {
        printf 'ableton-live command: %s\n' "${LIVE_CMD:-<not found>}"
        printf 'ableton-live-beta command: '
        command -v ableton-live-beta 2>/dev/null || printf '<not found>\n'
        printf 'prefix=%s\n' "$prefix"
        printf 'runtime_root=%s\n' "$runtime_root"
        printf 'state_dir=%s\n' "$state_dir"
        if have wine; then wine --version 2>&1; fi
        if [[ -x $runtime_root/bin/wine ]]; then "$runtime_root/bin/wine" --version 2>&1; fi
        if [[ -r $data_dir/VERSION ]]; then
            printf 'ableton-wine release: '; cat "$data_dir/VERSION"
        fi
        if [[ -r $runtime_root/ABLETON-WINE-BUILD-INFO.txt ]]; then
            printf 'runtime build info:\n'; cat "$runtime_root/ABLETON-WINE-BUILD-INFO.txt"
        fi
    } >"$REPORT_DIR/ableton/runtime.txt" 2>&1

    copy_tail "$state_dir/logs/live.log" "$REPORT_DIR/ableton/launcher-live.log" 10000
    copy_tail "$state_dir/logs/live.log.1" "$REPORT_DIR/ableton/launcher-live.log.1" 10000
    copy_tail "$HOME/.log/ableton-wine/live-beta.log" "$REPORT_DIR/ableton/launcher-live-beta.log" 10000
    copy_tail "$HOME/.log/ableton-wine/live-beta.log.1" "$REPORT_DIR/ableton/launcher-live-beta.log.1" 10000

    local beta_prefix=${ABLETON_BETA_WINEPREFIX:-$HOME/.wine-ableton-beta}
    local -a prefixes=("$prefix")
    [[ $beta_prefix != "$prefix" ]] && prefixes+=("$beta_prefix")

    local users_root log count=0 p
    printf '# Ableton crash-report files (names and sizes only; contents not copied)\n' \
        >"$REPORT_DIR/ableton/live-report-files.txt"
    for p in "${prefixes[@]}"; do
        users_root=$p/drive_c/users
        [[ -d $users_root ]] || continue
        while IFS= read -r -d '' log; do
            count=$((count + 1))
            copy_tail "$log" "$REPORT_DIR/ableton/live-preferences-log-$count.txt" 8000
        done < <(find "$users_root" -type f -path '*/AppData/Roaming/Ableton/Live */Preferences/Log.txt' -print0 2>/dev/null)

        {
            printf '\n## %s\n' "$users_root"
            find "$users_root" -type f -path '*/AppData/Roaming/Ableton/Live Reports/*' \
                -printf '%TY-%Tm-%Td %TH:%TM:%TS  %10s  %p\n' 2>/dev/null | sort -r | head -n 100
        } >>"$REPORT_DIR/ableton/live-report-files.txt"
    done
}

# Escape a literal string for use inside a basic-regex sed pattern with the
# '/' delimiter.
escape_pattern() {
    printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g'
}

# A name is only worth masking on its own if it is longer than three
# characters and is not a word this report needs intact. Replacing a name
# like "wine" or "arch" would corrupt the very lines the report exists to
# capture, and such a name reveals nothing anyway.
redact_token_ok() {
    local word=${1,,}
    ((${#word} > 3)) || return 1
    case $word in
        arch|linux|debian|ubuntu|fedora|mint|suse|steam|deck|wine|live|ableton| \
        mesa|zink|nouveau|intel|nvidia|amdgpu|radeon|audio|alsa|pipewire|jack| \
        gnome|plasma|xorg|wayland|host|home|root|user|admin|localhost) return 1 ;;
    esac
    return 0
}

REDACT_EXPRS=()
build_redaction() {
    local host user token_re
    host=$(hostname 2>/dev/null || true)
    user=$(id -un 2>/dev/null || printf '%s' "${USER:-}")
    REDACT_EXPRS=()
    if [[ -n ${HOME:-} ]]; then
        REDACT_EXPRS+=(-e "s/$(escape_pattern "$HOME")/<HOME>/g")
    fi
    if [[ -n $user ]]; then
        token_re=$(escape_pattern "$user")
        REDACT_EXPRS+=(-e "s/users\/$token_re/users\/<USER>/g")
        REDACT_EXPRS+=(-e "s/Users\\\\$token_re/Users\\\\<USER>/g")
        REDACT_EXPRS+=(-e "s/($token_re)/(<USER>)/g")
        if redact_token_ok "$user"; then
            REDACT_EXPRS+=(-e "s/\b$token_re\b/<USER>/g")
        fi
    fi
    if redact_token_ok "$host"; then
        REDACT_EXPRS+=(-e "s/\b$(escape_pattern "$host")\b/<HOST>/g")
    fi
}

redact_file() {
    local file=$1 tmp=$1.redacting
    ((${#REDACT_EXPRS[@]})) || return 0
    if sed "${REDACT_EXPRS[@]}" -- "$file" >"$tmp"; then
        mv -- "$tmp" "$file"
    else
        rm -f -- "$tmp"
    fi
}

printf 'Collecting report in %s\n' "$WORK_DIR"

# The installer puts the launcher in ~/.local/bin, which is not on PATH in
# every shell.
LIVE_CMD=$(command -v ableton-live 2>/dev/null || true)
if [[ -z $LIVE_CMD && -x $HOME/.local/bin/ableton-live ]]; then
    LIVE_CMD=$HOME/.local/bin/ableton-live
fi

if (( RUN_LIVE )); then
    if [[ -z $LIVE_CMD ]]; then
        printf 'The ableton-live launcher is not installed; collecting a snapshot instead.\n' >&2
    else
        if have pgrep && pgrep -f 'Ableton Live.*\.exe' >/dev/null 2>&1; then
            printf 'Ableton Live appears to be running already. The extra logging cannot reach it.\n' >&2
            printf 'Close Live first, then run this script again with --run.\n' >&2
        fi
        {
            printf 'start=%s\n' "$(date --iso-8601=seconds)"
            printf 'command=%q' "$LIVE_CMD"
            ((${#LIVE_ARGS[@]})) && printf ' %q' "${LIVE_ARGS[@]}"
            printf '\n'
        } >"$REPORT_DIR/ableton/live-session.txt"
        printf 'Starting Ableton Live. Reproduce the problem, then close Live if it remains open.\n'
        printf 'If Live freezes, press Ctrl-C here; the script still collects the report.\n'
        LIVE_INTERRUPTED=0
        trap 'LIVE_INTERRUPTED=1' INT
        (
            umask "$ORIGINAL_UMASK"
            export LIBGL_DEBUG=verbose
            export MESA_DEBUG=1
            export MESA_LOG_FILE="$REPORT_DIR/ableton/mesa-live.log"
            export WINEDEBUG=-all,+winediag,+seh
            exec "$LIVE_CMD" "${LIVE_ARGS[@]}"
        ) >"$REPORT_DIR/ableton/live-session-output.txt" 2>&1
        live_rc=$?
        trap - INT
        if (( LIVE_INTERRUPTED )); then
            printf '\nInterrupted. Collecting the logs gathered so far. Live may still be running.\n'
        fi
        {
            printf 'end=%s\n' "$(date --iso-8601=seconds)"
            printf 'exit_status=%d\n' "$live_rc"
            if (( LIVE_INTERRUPTED )); then printf 'interrupted=yes\n'; fi
        } >>"$REPORT_DIR/ableton/live-session.txt"
        trim_log "$REPORT_DIR/ableton/live-session-output.txt"
        trim_log "$REPORT_DIR/ableton/mesa-live.log"
    fi
fi

capture "$REPORT_DIR/system/basic.txt" 'Kernel, distribution, session and taint' bash -c '
    printf "collector_version=%s\n" "$1"
    date --iso-8601=seconds
    printf "kernel="; uname -srvmo
    printf "kernel_taint="; cat /proc/sys/kernel/tainted 2>/dev/null || true
    printf "dmesg_restrict="; cat /proc/sys/kernel/dmesg_restrict 2>/dev/null || true
    printf "os-release:\n"; cat /etc/os-release 2>/dev/null || true
    printf "kernel-command-line:\n"; cat /proc/cmdline 2>/dev/null || true
' _ "$COLLECTOR_VERSION"
capture "$REPORT_DIR/system/environment.txt" 'Relevant graphics/session environment only' relevant_environment
capture "$REPORT_DIR/system/packages.txt" 'Graphics, kernel, desktop and Wine package versions' package_versions
capture "$REPORT_DIR/system/modules.txt" 'Loaded kernel modules' lsmod
if have modinfo; then capture "$REPORT_DIR/system/nouveau-modinfo.txt" 'Nouveau module build and firmware information' modinfo nouveau; fi
capture "$REPORT_DIR/system/nouveau-parameters.txt" 'Active Nouveau module parameters' module_parameters

if have lspci; then
    capture "$REPORT_DIR/gpu/lspci-nnk.txt" 'PCI IDs and bound kernel drivers' lspci -Dnnk
    capture "$REPORT_DIR/gpu/lspci-verbose-nvidia.txt" 'Verbose NVIDIA PCI state, including link and power state' lspci -Dvvnnk -d 10de:
fi
capture "$REPORT_DIR/gpu/sysfs.txt" 'DRM PCI IDs, driver, link and runtime-power state' gpu_sysfs
capture "$REPORT_DIR/gpu/dev-dri.txt" 'DRM device nodes' ls -la /dev/dri
if (( PROBES )); then
    if have glxinfo; then capture "$REPORT_DIR/gpu/glxinfo.txt" 'OpenGL renderer' with_timeout 25s glxinfo -B; fi
    if have eglinfo; then capture "$REPORT_DIR/gpu/eglinfo.txt" 'EGL platforms and drivers' with_timeout 25s eglinfo -B; fi
    if have vulkaninfo; then capture "$REPORT_DIR/gpu/vulkaninfo.txt" 'Vulkan summary' with_timeout 40s vulkaninfo --summary; fi
    if have drm_info; then capture "$REPORT_DIR/gpu/drm-info.txt" 'DRM driver and connector information' with_timeout 25s drm_info; fi
    if have inxi; then capture "$REPORT_DIR/gpu/inxi.txt" 'Graphics overview' with_timeout 25s inxi -Gazy; fi
else
    printf 'Graphics API probes skipped with --no-probes.\n' >"$REPORT_DIR/gpu/probes-skipped.txt"
fi
capture "$REPORT_DIR/gpu/vulkan-icds.txt" 'Installed Vulkan ICD manifests' vulkan_files

capture "$REPORT_DIR/logs/boot-list.txt" 'Available journal boots' as_root journalctl --no-pager --no-hostname --list-boots
capture "$REPORT_DIR/logs/kernel-current.txt" 'Complete, unfiltered kernel journal for current boot' as_root journalctl --no-pager --no-hostname -k -b 0 -o short-monotonic
capture "$REPORT_DIR/logs/kernel-previous.txt" 'Complete, unfiltered kernel journal for previous boot' as_root journalctl --no-pager --no-hostname -k -b -1 -o short-monotonic
capture "$REPORT_DIR/logs/dmesg-current.txt" 'Current kernel ring buffer fallback' as_root dmesg --color=never --ctime
capture "$REPORT_DIR/logs/relevant-current.txt" 'Relevant system journal lines, current boot' filter_journal 0
capture "$REPORT_DIR/logs/relevant-previous.txt" 'Relevant system journal lines, previous boot' filter_journal -1

if have coredumpctl; then
    capture "$REPORT_DIR/logs/coredumps-list.txt" 'Coredumps from the past seven days' coredumpctl --no-pager --since '7 days ago' list
    capture "$REPORT_DIR/logs/coredumps-info-24h.txt" 'Coredump metadata and stored backtraces from the past 24 hours (no core files)' coredumpctl --no-pager --since '24 hours ago' info
fi

if [[ -d /sys/fs/pstore ]]; then
    {
        printf '# Persistent crash records left by the previous kernel, if readable\n'
        found_pstore=0
        while IFS= read -r pstore_file; do
            [[ -n $pstore_file ]] || continue
            found_pstore=1
            printf '\n## %s\n' "${pstore_file##*/}"
            as_root cat -- "$pstore_file" 2>&1
        done < <(as_root find /sys/fs/pstore -maxdepth 1 -type f 2>/dev/null | sort)
        if (( ! found_pstore )); then
            printf 'No readable records. /sys/fs/pstore is usually root-only; rerun with --sudo to include it.\n'
        fi
    } >"$REPORT_DIR/logs/pstore.txt" 2>&1
fi

# Both the current log and the rotated .old, which holds the session that
# crashed. User-session and system logs share a basename, so each source gets
# its own destination name.
copy_tail "$HOME/.local/share/xorg/Xorg.0.log" "$REPORT_DIR/logs/xorg-user-Xorg.0.log" 10000
copy_tail "$HOME/.local/share/xorg/Xorg.0.log.old" "$REPORT_DIR/logs/xorg-user-Xorg.0.log.old" 10000
copy_tail /var/log/Xorg.0.log "$REPORT_DIR/logs/xorg-system-Xorg.0.log" 10000
copy_tail /var/log/Xorg.0.log.old "$REPORT_DIR/logs/xorg-system-Xorg.0.log.old" 10000

ableton_paths

{
    cat <<'EOF'
This file contains the log lines that match potential graphics faults.

We will use this to look at:
- fifo and mmu faults
- DATA_ERROR, ILLEGAL_MTHD, ILLEGAL_CLASS and SCHED_ERROR
- CTXSW_TIMEOUT, runlist errors and killed channels
- GSP and RPC timeouts
- GPU resets and Xid numbers
- PCIe AER messages
- segfaults in Ableton, Wine, Mesa, Xwayland or the compositor
- the words nouveau, zink and nvk, which name the graphics drivers

Some lines repeat. That is normal.
EOF
    grep -RniE 'nouveau|\bnvk\b|zink|fifo.*fault|mmu.*fault|PT_NOT_PRESENT|PAGE_NOT_PRESENT|DATA_ERROR|ILLEGAL_(MTHD|CLASS)|INVALID_VALUE|SCHED_ERROR|CTXSW_TIMEOUT|runlist|channel.*(killed|fault|timeout)|rc scheduled|errored - disabling channel|gsp.*(timeout|error|rpc)|\bxid\b|gpu.*(reset|fault|hang)|Refused to change power state|pcie.*aer|segfault|general protection|out of memory|oom-kill|mce:' \
        "$REPORT_DIR/logs" "$REPORT_DIR/gpu" "$REPORT_DIR/ableton" 2>/dev/null | head -n 2500 || true
} >"$REPORT_DIR/HIGHLIGHTS.txt"

cat >"$REPORT_DIR/README.txt" <<'EOF'
Ableton Live graphics report

Read the files in this report before you share it. They can contain the names
of your files, your projects and your plug-ins. The script masks your home
folder path, your user name and your computer name where it can, but some
personal details can still slip through.

The report contains
- your hardware and software versions
- your graphics driver settings and graphics card power information
- records of any program that crashed
- the last part of the Ableton and launcher logs

The report does not contain core files, Live Sets, plug-in files, or the
contents of Ableton's own crash reports.

If your computer froze or restarted, run the script again when your system
is back.

Attach the .tar.gz file to your bug report. If Ableton wrote a crash file,
share it alongside this report. Redact personal information from that file
yourself before you share it.
EOF

printf 'Redacting home directory, user and host names from text files...\n'
build_redaction
while IFS= read -r -d '' report_file; do
    redact_file "$report_file"
done < <(find "$REPORT_DIR" -type f -print0)

ARCHIVE="$OUT_DIR/$REPORT_NAME.tar.gz"
# --owner/--group keep the user name out of the archive's own metadata.
tar --owner=0 --group=0 --numeric-owner -czf "$ARCHIVE" -C "$WORK_DIR" "$REPORT_NAME" || exit 1
chmod 600 "$ARCHIVE"

case $WORK_DIR in
    "$OUT_DIR"/nouveau-ableton-report-*.work.*) rm -rf -- "$WORK_DIR" ;;
    *) printf 'Refusing to remove unexpected work directory: %s\n' "$WORK_DIR" >&2; exit 1 ;;
esac
trap - EXIT

printf '\nCreated: %s\n' "$ARCHIVE"
printf 'Review the archive before sharing it. If the crash rebooted the machine, run this again now.\n'
