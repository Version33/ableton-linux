#!/usr/bin/env bash
# Collects a short, redacted system summary and copies it to the clipboard
# for pasting into a GitHub issue.
set -u

header() {
    printf '\n[%s]\n' "$1"
}

collect() {
    command -v "$1" >/dev/null 2>&1 || return 0
    "$@" 2>&1 || true
}

path_state() {
    local label="$1" path="$2" state=missing writable=no symlink=no filesystem=unknown
    if [ -L "$path" ]; then
        symlink=yes
        [ -e "$path" ] || state=broken
    fi
    if [ -e "$path" ]; then
        if [ -d "$path" ]; then state="directory"; else state="file"; fi
        [ -w "$path" ] && writable=yes
        filesystem="$(stat -L -f -c %T -- "$path" 2>/dev/null || true)"
        [ -n "$filesystem" ] || filesystem=unknown
    fi
    printf '%s=%s,writable=%s,symlink=%s,filesystem=%s\n' \
        "$label" "$state" "$writable" "$symlink" "$filesystem"
}

handler_state() {
    local label="$1" data_root="$2" handler="$3" mime="$4" file exec_line route=missing
    case "$handler" in ''|*/*)
        printf '%s_handler_file=missing\n' "$label"
        return ;;
    esac
    file="$data_root/applications/$handler"
    if [ -r "$file" ]; then
        exec_line="$(sed -n 's/^Exec=//p' "$file" | head -n 1)"
        case "$exec_line" in
            *ableton-live*) route=ableton-live ;;
            *WINEPREFIX=*wine*start*) route=wine-prefix ;;
            '') route=missing ;;
            *) route=other ;;
        esac
        printf '%s_handler_file=present\n' "$label"
        grep -qxF "MimeType=$mime;" "$file" \
            && printf '%s_handler_mime=present\n' "$label" \
            || printf '%s_handler_mime=missing\n' "$label"
    else
        printf '%s_handler_file=missing\n' "$label"
    fi
    printf '%s_handler_exec=%s\n' "$label" "$route"
}

escape_ere() {
    printf '%s' "$1" | sed 's/[][\\.^$*+?{}()|\/#]/\\&/g'
}

redact() {
    local home_re
    home_re="$(escape_ere "$HOME")"

    sed_args=( -E )
    case "$HOME" in
        /*) sed_args+=( -e "s#${home_re}#<HOME>#g" ) ;;
    esac
    sed_args+=(
        -e 's#(/home/)[^/[:space:]]+#\1<USER>#g'
        -e 's#(/run/user/)[0-9]+#\1<UID>#g'
        -e 's#luks-[0-9a-f-]{16,}#luks-<REDACTED>#Ig'
        -e 's#([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}#<MAC>#g'
        -e 's#[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}#<EMAIL>#g'
        -e '/^[[:space:]]*([^:=]*([Ss]erial|UUID|UDID|WWN|GUID|[Uu]nique [Ii][Dd]|[Aa]sset[ _-]?[Tt]ag|[Pp]rocessor[Ii][Dd]|[Ii]dentifying[Nn]umber|[Ii]nstance[Ii][Dd]|PNPDeviceID|[Aa]ddress|Location ID|Mount Point|Device Identifier)[^:=]*)[:=]/d'
        -e 's#(password|passwd|token|secret|api[ _-]?key|machineguid|unlock\.json|ableton[ _-]?(serial|licen[cs]e)|licen[cs]e[ _-]?key)[^[:cntrl:]]*#\1=<REDACTED>#Ig'
    )
    sed "${sed_args[@]}"
}

report="$(
    {
        printf 'ableton-linux system summary (Linux)\n'

        header SYSTEM
        sed -n -E '/^(PRETTY_NAME|VERSION_ID)=/p' /etc/os-release 2>/dev/null || true
        collect uname -srm
        if command -v lscpu >/dev/null 2>&1; then
            lscpu 2>&1 | sed -n -E '/^(Model name|CPU\(s\)):/p'
        fi
        if command -v free >/dev/null 2>&1; then
            free -h 2>&1 | sed -n '1,2p'
        fi
        for field in sys_vendor product_name; do
            path="/sys/class/dmi/id/$field"
            if [ -r "$path" ]; then
                value="$(tr -d '\000\n' < "$path")"
                [ -n "$value" ] && printf '%s=%s\n' "$field" "$value"
            fi
        done

        header GRAPHICS
        if command -v glxinfo >/dev/null 2>&1; then
            glxinfo -B 2>&1 | sed -n -E '/^OpenGL (vendor|renderer|version|core profile version)/p'
        fi
        printf 'desktop=%s\nsession=%s\n' \
            "${XDG_CURRENT_DESKTOP:-}" "${XDG_SESSION_TYPE:-}"

        header AUDIO
        if command -v systemctl >/dev/null 2>&1; then
            for unit in pipewire pipewire-pulse wireplumber; do
                state="$(systemctl --user is-active "$unit" 2>/dev/null || true)"
                printf '%s=%s\n' "$unit" "${state:-unavailable}"
            done
        fi
        collect pipewire --version
        collect wireplumber --version
        collect pw-metadata -n settings
        collect aplay -l

        header MIDI
        if command -v amidi >/dev/null 2>&1; then
            amidi -l 2>/dev/null || true
        fi

        header ABLETON
        data_root="${XDG_DATA_HOME:-$HOME/.local/share}"
        config_file="${XDG_CONFIG_HOME:-$HOME/.config}/ableton-wine/config"
        configured_prefix="$(sed -n 's/^prefix=//p' "$config_file" 2>/dev/null | head -n 1)"
        prefix="${ABLETON_WINEPREFIX:-${configured_prefix:-$HOME/.wine-ableton}}"
        if [ -r "$data_root/ableton-wine/VERSION" ]; then
            printf 'project_version=%s\n' "$(sed -n '1p' "$data_root/ableton-wine/VERSION")"
        else
            printf 'project_version=unavailable\n'
        fi
        [ -r "$config_file" ] && printf 'persistent_config=present\n' || printf 'persistent_config=missing\n'
        [ "$prefix" = "$HOME/.wine-ableton" ] && printf 'custom_prefix=no\n' || printf 'custom_prefix=yes\n'
        [ -f "$prefix/system.reg" ] && printf 'prefix_registry=present\n' || printf 'prefix_registry=missing\n'
        live_found=0
        for candidate in "$prefix"/drive_c/ProgramData/Ableton/Live*/Program/Ableton\ Live*.exe; do
            [ -f "$candidate" ] || continue
            printf 'live_installation=%s\n' "$(basename "$candidate" .exe)"
            live_found=1
        done
        [ "$live_found" -eq 1 ] || printf 'live_installation=unavailable\n'

        header BROWSER_HANDOFF
        default_browser="$(xdg-settings get default-web-browser 2>/dev/null || true)"
        printf 'default_browser=%s\n' "${default_browser:-unavailable}"
        browser_package=native-or-unknown
        browser_app="${default_browser%.desktop}"
        if [ -n "$browser_app" ] && command -v flatpak >/dev/null 2>&1 \
           && flatpak info "$browser_app" >/dev/null 2>&1; then
            browser_package=flatpak
        else
            case "$default_browser" in *_*.desktop) browser_package=snap-or-generated ;; esac
        fi
        printf 'browser_package=%s\n' "$browser_package"
        if command -v systemctl >/dev/null 2>&1; then
            for unit in xdg-desktop-portal xdg-desktop-portal-gnome \
                        xdg-desktop-portal-gtk xdg-desktop-portal-kde \
                        xdg-desktop-portal-wlr; do
                state="$(systemctl --user is-active "$unit" 2>/dev/null || true)"
                case "$state" in active|activating|failed) printf '%s=%s\n' "$unit" "$state" ;; esac
            done
        fi
        for tool in xdg-mime update-desktop-database update-mime-database; do
            command -v "$tool" >/dev/null 2>&1 \
                && printf '%s=present\n' "$tool" \
                || printf '%s=missing\n' "$tool"
        done
        protocol_handler="$(xdg-mime query default x-scheme-handler/ableton 2>/dev/null || true)"
        auz_handler="$(xdg-mime query default application/x-wine-extension-auz 2>/dev/null || true)"
        printf 'protocol_handler=%s\n' "${protocol_handler:-unavailable}"
        printf 'auz_handler=%s\n' "${auz_handler:-unavailable}"
        handler_state protocol "$data_root" "$protocol_handler" x-scheme-handler/ableton
        handler_state auz "$data_root" "$auz_handler" application/x-wine-extension-auz
        if command -v gio >/dev/null 2>&1; then
            gio mime x-scheme-handler/ableton 2>&1 || true
        fi

        header LIBRARY_PATHS
        path_state prefix "$prefix"
        path_state z_drive "$prefix/dosdevices/z:"
        wine_user=""
        for candidate in "$prefix"/drive_c/users/*; do
            [ -d "$candidate/AppData" ] || continue
            wine_user="$candidate"
            break
        done
        user_library=""
        if [ -n "$wine_user" ]; then
            for candidate in "$wine_user/Documents/Ableton/User Library" \
                             "$wine_user/My Documents/Ableton/User Library"; do
                if [ -e "$candidate" ] || [ -L "$candidate" ]; then
                    user_library="$candidate"
                    break
                fi
            done
        fi
        if [ -n "$user_library" ]; then
            path_state user_library "$user_library"
        else
            printf 'user_library=missing,writable=no,symlink=no,filesystem=unknown\n'
        fi
        if [ -n "${ABLETON_LIBRARY_PATH:-}" ]; then
            path_state requested_library_path "$ABLETON_LIBRARY_PATH"
        fi
    } 2>&1 | redact
)"

copy_to_clipboard() {
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
        wl-copy
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard
    elif command -v xsel >/dev/null 2>&1; then
        xsel --clipboard --input
    else
        return 1
    fi
}

fence='```'
printf '%s\n' "$report"
echo >&2
if printf '%s\n%s\n%s\n' "$fence" "$report" "$fence" | copy_to_clipboard 2>/dev/null; then
    printf 'Copied to your clipboard. Review the summary above, then paste it into your GitHub issue.\n' >&2
else
    printf 'No clipboard tool found (wl-copy, xclip or xsel). Copy the summary above into your GitHub issue.\n' >&2
fi
