#!/usr/bin/env bash
# scripts/audio-report.sh — one-shot snapshot of everything that decides audio
# behaviour under this stack: PipeWire settings and forced quanta, default
# devices, realtime threads, ntsync, the PipeASIO configuration, the tail of
# the launcher session log, and a follower-resync check for two-device setups.
# Read-only: the script reports and changes nothing. Paste the output into an
# issue report; home paths are shortened to ~ before printing.
set -u

redact() { sed "s|$HOME|~|g"; }
sec() { printf '\n== %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

WINE_ROOT="${ABLETON_WINE_ROOT:-$HOME/.local/opt/wine-d2d1-nspa-11.13}"

sec "versions"
echo "kernel: $(uname -r)"
have pw-cli && pw-cli --version 2>/dev/null | sed -n 's/^Linked with /pipewire client: /p'
have pw-cli && timeout 5 pw-cli info 0 2>/dev/null \
    | sed -n 's/.*version: "\([0-9][0-9.]*\)".*/pipewire daemon: \1/p' | head -n 1
[ -r "$WINE_ROOT/ABLETON-WINE-BUILD-INFO.txt" ] \
    && sed -n 's/^dist-version: /runtime: /p' "$WINE_ROOT/ABLETON-WINE-BUILD-INFO.txt"

sec "ntsync"
ls -l /dev/ntsync 2>/dev/null || echo "no /dev/ntsync"

sec "realtime limits"
echo "ulimit -r: $(ulimit -r 2>/dev/null)"

sec "PipeWire settings metadata"
have pw-metadata && timeout 5 pw-metadata -n settings 2>/dev/null | sed 's/^update: //'

sec "default devices"
have pw-metadata && timeout 5 pw-metadata -n default 2>/dev/null \
    | sed 's/^update: //' | grep -E "default\." | redact

sec "forced quanta per node"
if have pw-dump; then
    forced="$(timeout 5 pw-dump 2>/dev/null | awk -F'"' '
        /"node\.name"/ { name = $4 }
        /"node\.force-quantum"/ {
            v = $0; gsub(/[^0-9]/, "", v)
            printf "  %s: node.force-quantum %s\n", name, v
        }')"
    if [ -n "$forced" ]; then printf '%s\n' "$forced" | redact; else echo "  none: no node forces a quantum"; fi
fi

sec "graph, 3 s"
have pw-top && LC_ALL=C timeout 3 pw-top -b 2>/dev/null | tail -n 25 | redact

sec "realtime threads"
ps -eLo pid,tid,cls,rtprio,comm 2>/dev/null | awk '$3 == "RR" || $3 == "FF"' | head -n 20 | redact

sec "PipeASIO configuration"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/pipeasio/config.ini"
[ -r "$cfg" ] && redact < "$cfg" || echo "no config.ini (driver defaults apply)"
env | grep -E '^(PIPEASIO|ABLETON)_' | redact

sec "launcher session log tail"
slog="${XDG_STATE_HOME:-$HOME/.local/state}/ableton-wine/session.log"
[ -r "$slog" ] && tail -n 40 "$slog" | redact || echo "no session log yet (launch Live once)"

sec "follower resync (two-device setups)"
# When input and output live on different devices, one device follows the
# other's clock, and a follower short on buffer room resyncs audibly. This
# section only detects and reports; extra buffer room for a device is user
# configuration (api.alsa.headroom, a WirePlumber rule), not driver state.
resync_lines=""
[ -r "$slog" ] && resync_lines="$(grep -iE 'resync|xrun' "$slog" 2>/dev/null | tail -n 8)"
if [ -n "$resync_lines" ]; then
    echo "resync/xrun lines in the session log:"
    printf '%s\n' "$resync_lines" | sed 's/^/  /' | redact
else
    echo "no resync or xrun lines in the session log"
fi

# Graph shape from a short pw-top sample: two iterations, keep the last one.
# Follower rows carry a "+" before the node name; ALSA device nodes are the
# ones named alsa_output.* / alsa_input.*.
top_sample=""
have pw-top && top_sample="$(LC_ALL=C timeout 10 pw-top -b -n 2 2>/dev/null | awk '
    /^S +ID/ { buf = "" ; next }
    { buf = buf $0 "\n" }
    END { printf "%s", buf }')"
driver_nodes=""
follower_nodes=""
if [ -n "$top_sample" ]; then
    driver_nodes="$(printf '%s\n' "$top_sample" | awk '
        $0 !~ /\+/ && / alsa_(output|input)\./ { print $NF }' | sort -u)"
    follower_nodes="$(printf '%s\n' "$top_sample" | awk '
        /\+ +alsa_(output|input)\./ { print $NF }' | sort -u)"
fi
if [ -n "$follower_nodes" ]; then
    echo "graph driver device(s): $(printf '%s' "${driver_nodes:-none visible}" | tr '\n' ' ')" | redact
    echo "follower device(s):     $(printf '%s' "$follower_nodes" | tr '\n' ' ')" | redact
else
    echo "no follower audio device in the graph right now (single-clock setup, or Live not running)"
fi

# Map an ALSA path named in a resync line (e.g. hw:M2p) to its node.name.
node_for_alsa_path() {
    have pw-dump || return 0
    timeout 5 pw-dump 2>/dev/null | awk -v want="$1" -F'"' '
        /^  \{/ { name = "" ; path = "" }
        $2 == "node.name"     { name = $4 }
        $2 == "api.alsa.path" { path = $4 }
        /^  \},?$/ { if (path == want && name != "") { print name; exit } }'
}

target_node=""
if [ -n "$resync_lines" ]; then
    for dev in $(printf '%s\n' "$resync_lines" | grep -oE '(plug)?hw:[A-Za-z0-9_,+-]+' | sort -u); do
        n="$(node_for_alsa_path "$dev")"
        [ -n "$n" ] && { target_node="$n"; break; }
    done
    # Fall back to the graph shape when the log names no mappable device.
    [ -z "$target_node" ] && target_node="$(printf '%s\n' "$follower_nodes" | head -n 1)"
fi

if [ -n "$target_node" ]; then
    echo
    echo "device $target_node follows another device's clock and shows resyncs." | redact
    echo "Extra buffer room for a follower device is user configuration:"
    echo "api.alsa.headroom, set by a WirePlumber rule (WirePlumber 0.5 or newer)."
    echo "Copy this block to a file in ~/.config/wireplumber/wireplumber.conf.d/,"
    echo "then log out and back in, or run: systemctl --user restart wireplumber"
    echo
    cat <<EOF
# ~/.config/wireplumber/wireplumber.conf.d/99-ableton-follower-headroom.conf
monitor.alsa.rules = [
  {
    matches = [
      { node.name = "$target_node" }
    ]
    actions = {
      update-props = {
        api.alsa.headroom = 512
      }
    }
  }
]
EOF
    echo
    echo "Remove the file again if it does not help."
elif [ -n "$resync_lines" ]; then
    echo "resyncs recorded, but no follower device identified: attach this report to an issue"
fi
