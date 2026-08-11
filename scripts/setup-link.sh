#!/usr/bin/env bash
# Enable, disable, or inspect the single persistent Ableton Link policy.
# Firewall and service state are recorded under XDG_STATE_HOME so uninstall can
# reverse only changes made by this project.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
for lib in "$here/lib/config.sh" "$here/config.sh" \
           "${XDG_DATA_HOME:-$HOME/.local/share}/ableton-wine/lib/config.sh"; do
    if [ -r "$lib" ]; then . "$lib"; break; fi
done
declare -F ableton_config_init >/dev/null 2>&1 || { echo "!! setup-link: config helper is missing" >&2; exit 1; }
ableton_config_init

action="${1:-enable}"
[ $# -eq 0 ] || shift
mode=session
transaction_dir=""
case "$action" in
    snapshot|rollback|commit)
        [ $# -ge 1 ] || { echo "!! setup-link.sh $action needs a transaction directory" >&2; exit 2; }
        transaction_dir="$1"
        shift ;;
esac
while [ $# -gt 0 ]; do
    case "$1" in
        --mode=session|--mode=always) mode="${1#--mode=}" ;;
        *) echo "!! unknown Link option: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$action" in enable|disable|status|snapshot|rollback|commit|plan-enable|plan-disable) ;;
    *) echo "usage: setup-link.sh enable [--mode=session|always] | disable | status" >&2; exit 2 ;;
esac

state_file="$ABLETON_STATE_HOME/link-firewall"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit_file="$unit_dir/ableton-linkd.service"
data_unit="$ABLETON_DATA_HOME/ableton-linkd.service"
linkctl="$ABLETON_DATA_HOME/ableton-linkctl"
legacy_hook=/etc/NetworkManager/dispatcher.d/50-link-multicast
link_residual=0
declare -A link_deowned=()

owned_link_pids()
{
    local want proc pid exe
    want="$(readlink -f "$ABLETON_LINKD" 2>/dev/null || true)"
    [ -n "$want" ] || return 0
    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"
        exe="$(readlink -f "$proc/exe" 2>/dev/null || true)"
        [ "$exe" = "$want" ] && printf '%s\n' "$pid"
    done
    return 0
}

legacy_unit_is_owned()
{
    local content expected
    [ ! -L "$unit_file" ] || return 1
    content="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$unit_file" 2>/dev/null)"
    expected='[Unit]
Description=Ableton Link session anchor (ableton-linkd)
After=default.target
[Service]
ExecStart=%h/.local/share/ableton-wine/ableton-linkd
Restart=on-failure
RestartSec=5
[Install]
WantedBy=default.target'
    [ "$content" = "$expected" ] && return 0
    expected='[Unit]
Description=Ableton Link session anchor (ableton-linkd)
After=default.target
[Service]
ExecStart=%h/.local/share/ableton-wine/ableton-linkd --linger 0
Restart=on-failure
RestartSec=5
[Install]
WantedBy=default.target'
    [ "$content" = "$expected" ]
}

unit_is_owned()
{
    [ -f "$unit_file" ] || return 1
    grep -qxF 'X-AbletonLinuxOwned=true' "$unit_file" 2>/dev/null && return 0
    # Adopt only the two exact unit definitions shipped before ownership
    # markers. Keep any unit with another directive or executable unchanged.
    legacy_unit_is_owned
}

loaded_unit_is_owned()
{
    command -v systemctl >/dev/null 2>&1 || return 1
    local fragment expected exec_line
    fragment="$(ableton_run_bounded 20 systemctl --user show -p FragmentPath --value ableton-linkd.service 2>/dev/null || true)"
    [ -n "$fragment" ] || return 1
    expected="$(ableton_realpath_m "$unit_file")"
    [ "$(ableton_realpath_m "$fragment")" = "$expected" ] || return 1
    if [ -e "$unit_file" ]; then
        unit_is_owned
        return
    fi
    # A service can remain loaded after its file was removed. Prove both its
    # exact executable and that executable's project ownership before stopping
    # it; the canonical unit name alone is never sufficient.
    link_binary_is_owned || return 1
    exec_line="$(ableton_run_bounded 20 systemctl --user show -p ExecStart --value ableton-linkd.service 2>/dev/null || true)"
    case "$exec_line" in *"$ABLETON_LINKD"*) return 0 ;; *) return 1 ;; esac
}

stop_owned_service()
{
    loaded_unit_is_owned || return 0
    if command -v systemctl >/dev/null 2>&1; then
        ableton_run_bounded 20 systemctl --user disable --now ableton-linkd.service >/dev/null 2>&1 || true
    fi
}

remove_owned_firewall()
{
    [ -r "$state_file" ] || return 0
    local state rc=0
    state="$(sed -n '1p' "$state_file")"
    case "$state" in
        ufw-added)
            echo "-- removing the project-owned ufw allowance for UDP 20808"
            ableton_run_bounded 120 sudo ufw delete allow 20808/udp || rc=$? ;;
        firewalld-added)
            echo "-- removing the project-owned firewalld allowance for UDP 20808"
            if command -v firewall-cmd >/dev/null 2>&1 \
               && ableton_run_bounded 20 firewall-cmd --state >/dev/null 2>&1; then
                ableton_run_bounded 120 sudo firewall-cmd --permanent --remove-port=20808/udp || rc=$?
                [ "$rc" -ne 0 ] || ableton_run_bounded 120 sudo firewall-cmd --reload || rc=$?
            elif command -v firewall-offline-cmd >/dev/null 2>&1; then
                ableton_run_bounded 120 sudo firewall-offline-cmd --remove-port=20808/udp || rc=$?
            else
                rc=127
            fi ;;
        none|'') ;;
        *) echo "!! unrecognised Link firewall ownership record: $state_file" >&2; return 1 ;;
    esac
    [ "$rc" -eq 0 ] || { echo "!! failed to remove the recorded Link firewall rule" >&2; return "$rc"; }
    rm -f -- "$state_file"
}

restore_firewall_snapshot()
{
    local snapshot="$1" prior="" current="" rc=0
    [ ! -r "$snapshot" ] || prior="$(sed -n '1p' "$snapshot")"
    [ ! -r "$state_file" ] || current="$(sed -n '1p' "$state_file")"
    if [ -r "$snapshot" ] && [ "$current" = "$prior" ]; then
        return 0
    fi
    [ ! -e "$state_file" ] || remove_owned_firewall || rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    if [ -r "$snapshot" ]; then
        restore_firewall_record "$prior"
    else
        rm -f -- "$state_file"
    fi
}

legacy_hook_is_owned()
{
    [ -f "$legacy_hook" ] \
        && grep -qxF '#!/bin/sh' "$legacy_hook" 2>/dev/null \
        && grep -qF '[ "$2" = "up" ] || exit 0' "$legacy_hook" 2>/dev/null \
        && grep -qF 'ip route replace 224.0.0.0/4' "$legacy_hook" 2>/dev/null
}

snapshot_legacy_network()
{
    local destination="$1"
    legacy_hook_is_owned || return 0
    cp -a -- "$legacy_hook" "$destination.hook"
    ip -4 route show 224.0.0.0/4 2>/dev/null | head -n 1 > "$destination.route" || true
}

restore_legacy_network()
{
    local snapshot="$1" mode route_line
    [ -e "$snapshot.hook" ] || return 0
    if [ -e "$legacy_hook" ] && ! legacy_hook_is_owned; then
        echo "!! refusing to overwrite unrecognised legacy-hook path $legacy_hook during rollback" >&2
        return 1
    fi
    mode="$(stat -c '%a' "$snapshot.hook")"
    ableton_run_bounded 120 sudo install -m "$mode" -- "$snapshot.hook" "$legacy_hook"
    route_line="$(sed -n '1p' "$snapshot.route" 2>/dev/null || true)"
    if [ -n "$route_line" ]; then
        local -a route_args=()
        read -r -a route_args <<< "$route_line"
        [ "${route_args[0]:-}" = 224.0.0.0/4 ] || {
            echo "!! refusing malformed legacy route snapshot" >&2; return 1; }
        ableton_run_bounded 120 sudo ip route replace "${route_args[@]}"
    fi
}

remove_owned_legacy_hook()
{
    [ -e "$legacy_hook" ] || return 0
    if ! legacy_hook_is_owned; then
        echo "!! keeping unrecognised legacy-hook path $legacy_hook" >&2
        return 0
    fi
    echo "-- removing the project-owned legacy multicast hook"
    ableton_run_bounded 120 sudo rm -f -- "$legacy_hook"
    ableton_run_bounded 120 sudo ip route del 224.0.0.0/4 >/dev/null 2>&1 || true
}

manifest_digest_for()
{
    local wanted="$1" kind path digest manifest="$ABLETON_STATE_HOME/install-manifest.tsv"
    [ -r "$manifest" ] || return 1
    while IFS=$'\t' read -r kind path digest; do
        [ "$kind" = file ] && [ "$path" = "$wanted" ] || continue
        printf '%s\n' "$digest"
        return 0
    done < "$manifest"
    return 1
}

legacy_link_file_is_owned()
{
    local target="$1"
    case "$target" in
        "$ABLETON_DATA_HOME/ableton-linkd")
            strings "$target" 2>/dev/null | grep -qF 'ableton-linkd: native Ableton Link session anchor and probe' ;;
        "$ABLETON_DATA_HOME/ableton-linkctl")
            grep -qF 'Project-owned Ableton Link lifecycle controller' "$target" 2>/dev/null ;;
        "$ABLETON_DATA_HOME/setup-link.sh")
            grep -qF 'Ableton Link setup' "$target" 2>/dev/null ;;
        "$ABLETON_DATA_HOME/ableton-linkd.service")
            grep -qF 'ableton-linkd' "$target" 2>/dev/null ;;
        *) return 1 ;;
    esac
}

link_binary_is_owned()
{
    local expected current
    expected="$(manifest_digest_for "$ABLETON_LINKD" 2>/dev/null || true)"
    if [ -n "$expected" ]; then
        current="$(sha256sum -- "$ABLETON_LINKD" 2>/dev/null | awk '{print $1}')"
        [ -n "$current" ] && [ "$current" = "$expected" ]
        return
    fi
    legacy_link_file_is_owned "$ABLETON_LINKD"
}

remove_owned_link_file()
{
    local target="$1" expected current
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        restore_link_prestate "$target"
        return 0
    fi
    expected="$(manifest_digest_for "$target" 2>/dev/null || true)"
    if [ -n "$expected" ]; then
        current="$(sha256sum -- "$target" 2>/dev/null | awk '{print $1}')"
        if [ "$current" != "$expected" ]; then
            echo "!! keeping modified Link file $target" >&2
            link_residual=1
            return 0
        fi
    elif ! legacy_link_file_is_owned "$target"; then
        echo "!! keeping unowned Link path $target" >&2
        link_residual=1
        return 0
    fi
    rm -f -- "$target"
    restore_link_prestate "$target"
    link_deowned["$target"]=1
}

restore_link_prestate()
{
    local target="$1" index="$ABLETON_STATE_HOME/install-prestate.tsv" backup tmp
    [ -r "$index" ] || return 0
    backup="$(awk -F '\t' -v p="$target" '$1=="present" && $2==p { print $3; exit }' "$index")"
    [ -n "$backup" ] || return 0
    if [ -e "$backup" ] || [ -L "$backup" ]; then
        mkdir -p -- "$(dirname "$target")"
        cp -a -- "$backup" "$target"
    fi
    tmp="$(mktemp "$ABLETON_STATE_HOME/.prestate-link.XXXXXX")"
    awk -F '\t' -v p="$target" '$2 != p' "$index" > "$tmp"
    chmod 600 "$tmp"
    mv -f -- "$tmp" "$index"
    rm -f -- "$backup"
    link_deowned["$target"]=1
}

prune_link_manifest()
{
    local manifest="$ABLETON_STATE_HOME/install-manifest.tsv" tmp kind path digest
    [ -r "$manifest" ] || return 0
    tmp="$(mktemp "$ABLETON_STATE_HOME/.manifest-link.XXXXXX")"
    while IFS=$'\t' read -r kind path digest; do
        case "$path" in
            "$ABLETON_LINKD"|"$data_unit"|"$linkctl"|"$ABLETON_DATA_HOME/setup-link.sh")
                [ -z "${link_deowned[$path]+x}" ] || continue
                [ -e "$path" ] || [ -L "$path" ] || continue ;;
        esac
        printf '%s\t%s\t%s\n' "$kind" "$path" "$digest" >> "$tmp"
    done < "$manifest"
    chmod 600 "$tmp"
    mv -f -- "$tmp" "$manifest"
}

disable_link()
{
    echo "== disable Ableton Link =="
    stop_owned_service
    if [ -x "$here/ableton-linkctl" ]; then "$here/ableton-linkctl" stop
    elif [ -x "$linkctl" ]; then "$linkctl" stop
    fi
    remove_owned_legacy_hook
    remove_owned_firewall
    if unit_is_owned; then rm -f -- "$unit_file"; fi
    if command -v systemctl >/dev/null 2>&1; then
        ableton_run_bounded 20 systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
    remove_owned_link_file "$ABLETON_LINKD"
    remove_owned_link_file "$data_unit"
    remove_owned_link_file "$linkctl"
    remove_owned_link_file "$ABLETON_DATA_HOME/setup-link.sh"
    prune_link_manifest
    rm -f -- "$ABLETON_DATA_HOME/link-configured"
    ABLETON_LINK_MODE=off
    export ABLETON_LINK_MODE
    ableton_write_config
    if [ "$link_residual" -eq 0 ]; then
        echo "OK: Link policy is off; no owned Link binary, service, firewall rule, or daemon remains"
    else
        echo "OK: Link policy is off; unowned or modified Link files were kept"
    fi
}

install_unit()
{
    [ -x "$ABLETON_LINKD" ] || { echo "!! ableton-linkd is missing at $ABLETON_LINKD" >&2; return 1; }
    if [ -e "$unit_file" ] && ! unit_is_owned; then
        echo "!! refusing to replace foreign systemd unit $unit_file" >&2
        return 1
    fi
    if [ ! -e "$unit_file" ] && command -v systemctl >/dev/null 2>&1; then
        loaded_fragment="$(ableton_run_bounded 20 systemctl --user show -p FragmentPath --value ableton-linkd.service 2>/dev/null || true)"
        if [ -n "$loaded_fragment" ] && [ "$(ableton_realpath_m "$loaded_fragment")" != "$(ableton_realpath_m "$unit_file")" ]; then
            echo "!! refusing to shadow foreign systemd unit $loaded_fragment" >&2
            return 1
        fi
    fi
    mkdir -p -- "$unit_dir"
    local escaped="${ABLETON_LINKD//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//%/%%}"
    cat > "$unit_file.tmp" <<EOF
[Unit]
Description=Ableton Link session anchor (ableton-linux)
After=default.target
X-AbletonLinuxOwned=true

[Service]
ExecStart="$escaped" --linger 0
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    chmod 644 "$unit_file.tmp"
    mv -f -- "$unit_file.tmp" "$unit_file"
    command -v systemctl >/dev/null 2>&1 || return 0
    ableton_run_bounded 20 systemctl --user daemon-reload
}

configure_firewall()
{
    ableton_mark_state_home
    if [ -r "$state_file" ]; then
        case "$(sed -n '1p' "$state_file")" in
            ufw-added|firewalld-added) return 0 ;;
            none) rm -f -- "$state_file" ;;
            *) echo "!! unrecognised Link firewall ownership record: $state_file" >&2; return 1 ;;
        esac
    fi
    if command -v ufw >/dev/null 2>&1 && grep -qsi '^ENABLED=yes' /etc/ufw/ufw.conf; then
        if ableton_run_bounded 20 ufw status 2>/dev/null | grep -Eq '(^|[[:space:]])20808/udp([[:space:]]|$)'; then
            printf 'none\n' > "$state_file"
            echo "   ufw already allows UDP 20808; leaving the foreign/pre-existing rule alone"
        else
            echo "   ufw is active: adding UDP 20808 (sudo, bounded to two minutes)"
            ableton_run_bounded 120 sudo ufw allow 20808/udp || return $?
            printf 'ufw-added\n' > "$state_file"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1 \
         && ableton_run_bounded 20 firewall-cmd --state >/dev/null 2>&1; then
        if ableton_run_bounded 20 firewall-cmd --permanent --query-port=20808/udp >/dev/null 2>&1; then
            printf 'none\n' > "$state_file"
            echo "   firewalld already allows UDP 20808; leaving the foreign/pre-existing rule alone"
        else
            echo "   firewalld is active: adding UDP 20808 (sudo, bounded to two minutes)"
            printf 'firewalld-added\n' > "$state_file"
            ableton_run_bounded 120 sudo firewall-cmd --permanent --add-port=20808/udp || { rm -f -- "$state_file"; return 1; }
            # Ownership is already recorded before reload. If reload fails, the
            # caller's rollback can still remove the persistent rule.
            ableton_run_bounded 120 sudo firewall-cmd --reload || return $?
        fi
    else
        printf 'none\n' > "$state_file"
        echo "   no active ufw/firewalld; no firewall mutation"
    fi
}

restore_firewall_record()
{
    local prior="$1" rc=0
    ableton_mark_state_home
    case "$prior" in
        ufw-added)
            if ! ableton_run_bounded 20 ufw status 2>/dev/null | grep -Eq '(^|[[:space:]])20808/udp([[:space:]]|$)'; then
                ableton_run_bounded 120 sudo ufw allow 20808/udp || rc=$?
            fi ;;
        firewalld-added)
            if command -v firewall-cmd >/dev/null 2>&1 \
               && ableton_run_bounded 20 firewall-cmd --state >/dev/null 2>&1; then
                if ! ableton_run_bounded 20 firewall-cmd --permanent --query-port=20808/udp >/dev/null 2>&1; then
                    ableton_run_bounded 120 sudo firewall-cmd --permanent --add-port=20808/udp || rc=$?
                    [ "$rc" -ne 0 ] || ableton_run_bounded 120 sudo firewall-cmd --reload || rc=$?
                fi
            elif command -v firewall-offline-cmd >/dev/null 2>&1; then
                ableton_run_bounded 120 sudo firewall-offline-cmd --add-port=20808/udp || rc=$?
            else
                rc=127
            fi ;;
        none|'') ;;
        *) echo "!! cannot restore unknown firewall record '$prior'" >&2; return 1 ;;
    esac
    [ "$rc" -eq 0 ] || return "$rc"
    printf '%s\n' "$prior" > "$state_file"
}

snapshot_link_transaction()
{
    local snap="$transaction_dir/link" pids asset label manifest
    [ ! -e "$snap/ready" ] || return 0
    mkdir -p -- "$snap"
    printf '%s\n' "$ABLETON_LINK_MODE" > "$snap/policy"
    if [ -e "$state_file" ]; then cp -a -- "$state_file" "$snap/firewall"
    else : > "$snap/firewall.absent"; fi
    snapshot_legacy_network "$snap/legacy"
    if [ -e "$unit_file" ]; then cp -a -- "$unit_file" "$snap/unit"
    else : > "$snap/unit.absent"; fi
    label=0
    for asset in "$ABLETON_LINKD" "$data_unit" "$linkctl" "$ABLETON_DATA_HOME/setup-link.sh"; do
        printf '%s\n' "$asset" > "$snap/asset-$label.path"
        [ ! -e "$asset" ] && [ ! -L "$asset" ] || cp -a -- "$asset" "$snap/asset-$label.file"
        label=$((label + 1))
    done
    manifest="$ABLETON_STATE_HOME/install-manifest.tsv"
    [ ! -e "$manifest" ] || cp -a -- "$manifest" "$snap/manifest"
    if [ -e "$ABLETON_STATE_HOME/install-prestate.tsv" ]; then
        cp -a -- "$ABLETON_STATE_HOME/install-prestate.tsv" "$snap/prestate.tsv"
    else
        : > "$snap/prestate.absent"
    fi
    if [ -d "$ABLETON_STATE_HOME/install-prestate" ]; then
        cp -a -- "$ABLETON_STATE_HOME/install-prestate" "$snap/prestate-dir"
    else
        : > "$snap/prestate-dir.absent"
    fi
    if unit_is_owned && command -v systemctl >/dev/null 2>&1; then
        ableton_run_bounded 20 systemctl --user is-enabled --quiet ableton-linkd.service 2>/dev/null \
            && : > "$snap/enabled" || true
        loaded_unit_is_owned \
            && ableton_run_bounded 20 systemctl --user is-active --quiet ableton-linkd.service 2>/dev/null \
            && : > "$snap/active" || true
    fi
    pids="$(owned_link_pids | head -n 1)"
    [ -z "$pids" ] || : > "$snap/detached-active"
    : > "$snap/ready"
}

rollback_link_transaction()
{
    local snap="$transaction_dir/link" prior rc=0 ctl path saved manifest
    [ -e "$snap/ready" ] || return 0
    prior="$(sed -n '1p' "$snap/policy")"
    stop_owned_service
    ctl="$here/ableton-linkctl"; [ -x "$ctl" ] || ctl="$linkctl"
    [ ! -x "$ctl" ] || "$ctl" stop || rc=$?
    restore_firewall_snapshot "$snap/firewall" || rc=$?
    restore_legacy_network "$snap/legacy" || rc=$?
    if [ -e "$snap/unit" ]; then
        mkdir -p -- "$unit_dir"
        cp -a -- "$snap/unit" "$unit_file"
    elif unit_is_owned; then
        rm -f -- "$unit_file"
    fi
    for saved in "$snap"/asset-*.path; do
        [ -f "$saved" ] || continue
        path="$(sed -n '1p' "$saved")"
        saved="${saved%.path}.file"
        if [ -e "$saved" ] || [ -L "$saved" ]; then
            mkdir -p -- "$(dirname "$path")"
            rm -f -- "$path"
            cp -a -- "$saved" "$path"
        fi
    done
    manifest="$ABLETON_STATE_HOME/install-manifest.tsv"
    if [ -e "$snap/manifest" ]; then
        ableton_mark_state_home
        cp -a -- "$snap/manifest" "$manifest"
    fi
    rm -f -- "$ABLETON_STATE_HOME/install-prestate.tsv"
    rm -rf -- "$ABLETON_STATE_HOME/install-prestate"
    if [ -e "$snap/prestate.tsv" ]; then
        cp -a -- "$snap/prestate.tsv" "$ABLETON_STATE_HOME/install-prestate.tsv"
    fi
    if [ -d "$snap/prestate-dir" ]; then
        cp -a -- "$snap/prestate-dir" "$ABLETON_STATE_HOME/install-prestate"
    fi
    if command -v systemctl >/dev/null 2>&1; then
        ableton_run_bounded 20 systemctl --user daemon-reload >/dev/null 2>&1 || rc=$?
        if [ -e "$snap/enabled" ]; then
            ableton_run_bounded 20 systemctl --user enable ableton-linkd.service >/dev/null 2>&1 || rc=$?
        elif unit_is_owned; then
            ableton_run_bounded 20 systemctl --user disable ableton-linkd.service >/dev/null 2>&1 || true
        fi
        if [ -e "$snap/active" ]; then
            ableton_run_bounded 20 systemctl --user start ableton-linkd.service >/dev/null 2>&1 || rc=$?
        fi
    fi
    if [ -e "$snap/detached-active" ] && [ "$prior" = session ] && [ -x "$ctl" ]; then
        ABLETON_LINK_MODE=session "$ctl" start || rc=$?
    fi
    [ "$rc" -eq 0 ] || { echo "!! Link pre-state could not be fully restored" >&2; return "$rc"; }
    rm -rf -- "$snap"
}

commit_link_transaction()
{
    local snap="$transaction_dir/link" ctl
    [ -e "$snap/ready" ] || return 0
    ctl="$here/ableton-linkctl"; [ -x "$ctl" ] || ctl="$linkctl"
    if [ -e "$snap/detached-active" ] && [ "$ABLETON_LINK_MODE" = session ] && [ -x "$ctl" ]; then
        "$ctl" start
    fi
    rm -rf -- "$snap"
}

plan_link()
{
    echo "PLAN: Ableton Link"
    if [ "$action" = plan-disable ]; then
        printf '  set persistent policy off: %s\n' "$ABLETON_CONFIG_FILE"
        printf '  stop only daemon PIDs whose executable is: %s\n' "$ABLETON_LINKD"
        unit_is_owned && printf '  disable/stop and remove owned unit: %s\n' "$unit_file"
        [ ! -r "$state_file" ] || printf '  reverse recorded firewall state (%s): %s\n' "$(sed -n '1p' "$state_file")" "$state_file"
        [ ! -e "$legacy_hook" ] || printf '  remove recognisable legacy hook/route: %s\n' "$legacy_hook"
        printf '  remove manifest-owned Link assets: %s, %s/{ableton-linkctl,setup-link.sh,ableton-linkd.service}\n' \
            "$ABLETON_LINKD" "$ABLETON_DATA_HOME"
        return 0
    fi
    printf '  set persistent policy %s: %s\n' "$mode" "$ABLETON_CONFIG_FILE"
    [ ! -e "$legacy_hook" ] || printf '  remove recognisable legacy hook/route: %s\n' "$legacy_hook"
    if command -v ufw >/dev/null 2>&1 && grep -qsi '^ENABLED=yes' /etc/ufw/ufw.conf; then
        if ableton_run_bounded 20 ufw status 2>/dev/null | grep -Eq '(^|[[:space:]])20808/udp([[:space:]]|$)'; then
            echo '  keep pre-existing UFW UDP 20808 rule; record no ownership'
        else
            echo '  add UFW UDP 20808 rule; record project ownership'
        fi
    elif command -v firewall-cmd >/dev/null 2>&1 \
         && ableton_run_bounded 20 firewall-cmd --state >/dev/null 2>&1; then
        if ableton_run_bounded 20 firewall-cmd --permanent --query-port=20808/udp >/dev/null 2>&1; then
            echo '  keep pre-existing firewalld UDP 20808 rule; record no ownership'
        else
            echo '  add/reload firewalld UDP 20808 rule; record project ownership'
        fi
    else
        echo '  no active UFW/firewalld mutation'
    fi
    printf '  write ownership-marked user unit with ExecStart=%s: %s\n' "$ABLETON_LINKD" "$unit_file"
    case "$mode" in
        session) echo '  disable/stop the owned always-on unit; launchers start session daemon' ;;
        always) echo '  enable/start the owned user unit' ;;
    esac
}

enable_link()
{
    [ -x "$linkctl" ] || { echo "!! ableton-linkctl is missing at $linkctl; install Link assets first" >&2; return 1; }
    echo "== enable Ableton Link ($mode) =="
    local snapshot unit_existed=0 config_existed=0 rc=0
    ableton_mark_state_home
    snapshot="$(mktemp -d "$ABLETON_STATE_HOME/.link-enable.XXXXXX")"
    if [ -e "$state_file" ]; then cp -a -- "$state_file" "$snapshot/firewall"; fi
    snapshot_legacy_network "$snapshot/legacy"
    if [ -e "$unit_file" ]; then cp -a -- "$unit_file" "$snapshot/unit"; unit_existed=1; fi
    if [ -e "$ABLETON_CONFIG_FILE" ]; then cp -a -- "$ABLETON_CONFIG_FILE" "$snapshot/config"; config_existed=1; fi
    remove_owned_legacy_hook || rc=$?
    if [ "$rc" -eq 0 ]; then configure_firewall || rc=$?; fi
    if [ "$rc" -eq 0 ]; then install_unit || rc=$?; fi
    if [ "$rc" -ne 0 ]; then
        restore_firewall_snapshot "$snapshot/firewall" || true
        restore_legacy_network "$snapshot/legacy" || true
        if [ "$unit_existed" -eq 1 ]; then cp -a -- "$snapshot/unit" "$unit_file"
        elif unit_is_owned; then rm -f -- "$unit_file"; fi
        rm -rf -- "$snapshot"
        return "$rc"
    fi
    ABLETON_LINK_MODE="$mode"
    export ABLETON_LINK_MODE
    ableton_write_config || rc=$?
    if [ "$rc" -eq 0 ]; then
        case "$mode" in
            session)
                # Registration is harmless, but session policy must never leave the
                # always-on unit enabled or running.
                ableton_run_bounded 20 systemctl --user disable --now ableton-linkd.service >/dev/null 2>&1 || true ;;
            always)
                ableton_run_bounded 20 systemctl --user enable --now ableton-linkd.service || rc=$? ;;
        esac
    fi
    if [ "$rc" -ne 0 ]; then
        stop_owned_service
        restore_firewall_snapshot "$snapshot/firewall" || true
        restore_legacy_network "$snapshot/legacy" || true
        if [ "$unit_existed" -eq 1 ]; then cp -a -- "$snapshot/unit" "$unit_file"
        elif unit_is_owned; then rm -f -- "$unit_file"; fi
        if [ "$config_existed" -eq 1 ]; then cp -a -- "$snapshot/config" "$ABLETON_CONFIG_FILE"
        else rm -f -- "$ABLETON_CONFIG_FILE"; fi
        rm -rf -- "$snapshot"
        return "$rc"
    fi
    rm -rf -- "$snapshot"
    rm -f -- "$ABLETON_DATA_HOME/link-configured"
    echo "OK: Link policy is $mode"
}

case "$action" in
    enable) enable_link ;;
    disable) disable_link ;;
    status)
        printf 'policy: %s\n' "$ABLETON_LINK_MODE"
        if [ -x "$linkctl" ]; then "$linkctl" status | sed '1d'; else echo 'state: not installed'; fi
        [ -r "$state_file" ] && printf 'firewall: %s\n' "$(sed -n '1p' "$state_file")" || echo 'firewall: unrecorded'
        ;;
    snapshot) snapshot_link_transaction ;;
    rollback) rollback_link_transaction ;;
    commit) commit_link_transaction ;;
    plan-enable|plan-disable) plan_link ;;
esac
