# Sourceable runtime indirection. ableton_runtime_link <runtime-root> prints a
# stable, user-owned path that resolves to that runtime, creating or re-pointing
# it as needed, and returns 1 when it cannot provide one.
#
# User configuration must never record the runtime root itself. On Nix that root
# is a /nix/store path: it is content-addressed, so every upgrade produces a new
# one, and `nix run` leaves no GC root, so nix-collect-garbage may delete it. A
# .desktop file or a systemd unit that copied such a path in then launches an
# old package, or nothing at all. Naming this link instead survives both, and
# every launcher re-points it, so an upgrade needs no re-run of any setup step.
#
# On a store runtime the link doubles as an indirect garbage-collector root -
# the same mechanism `nix build`'s result symlink uses. It goes through the nix
# daemon, so it needs no privileges, and it keeps an otherwise unrooted `nix
# run` closure alive for as long as the link exists; deleting the link releases
# it. A .run install already has a stable root under ~/.local/opt, so there the
# link is a plain symlink and the callers' path rewrites are no-ops.

ableton_runtime_link() {   # <runtime-root> -> stable path naming that runtime
    local root="${1:-}" link target dir
    [ -n "$root" ] && [ -d "$root" ] || return 1
    # Beside the rest of the runtime's user-side staging, which every script in
    # this kit addresses as $HOME/.local/share/ableton-wine, and which
    # uninstall.sh removes wholesale - releasing the GC root with it.
    link="$HOME/.local/share/ableton-wine/runtime"
    target="$(cd -- "$root" && pwd -P)" || return 1
    # Already current: skip the daemon round trip every launch would otherwise
    # pay. -e follows the link, so a dangling one is rebuilt (and re-rooted)
    # instead of being reported as good.
    if [ "$(readlink "$link" 2>/dev/null)" = "$target" ] && [ -e "$link" ]; then
        printf '%s\n' "$link"
        return 0
    fi
    dir="${link%/*}"
    mkdir -p "$dir" 2>/dev/null || return 1
    # nix-store below refuses to overwrite a link that does not already point
    # into the store, so clear the stale one first. Only ever a symlink: a real
    # file or directory at that name belongs to someone else and is left alone.
    if [ -e "$link" ] || [ -L "$link" ]; then
        [ -L "$link" ] || return 1
        rm -f "$link" || return 1
    fi
    case "$target" in
        /nix/store/*)
            # --add-root both writes the symlink and registers it; --realise is
            # a no-op on a path already in the store (this one is: we are
            # running from it).
            if command -v nix-store >/dev/null 2>&1 \
               && nix-store --realise "$target" --indirect --add-root "$link" \
                    >/dev/null 2>&1; then
                printf '%s\n' "$link"
                return 0
            fi
            # No daemon, or a store that refuses roots: an unrooted symlink is
            # still better in user configuration than the store path itself.
            ;;
    esac
    ln -sfn "$target" "$link" 2>/dev/null || return 1
    printf '%s\n' "$link"
}
