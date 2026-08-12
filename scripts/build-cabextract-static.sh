#!/usr/bin/env bash
# Build the pinned cabextract source as one static installer helper.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
cd "$root"

ENGINE="${ENGINE:-podman}"
IMAGE="${IMAGE:-ableton-wine-build:22.04}"
output="${1:-$root/dist/cabextract-static}"
case "$output" in
    /*) ;;
    *) output="$root/$output" ;;
esac

command -v "$ENGINE" >/dev/null || { echo "!! need $ENGINE to build cabextract" >&2; exit 1; }
( cd vendor && sha256sum -c cabextract.sha256 )
"$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1 || {
    echo "!! build image $IMAGE is missing: run ./build.sh first" >&2
    exit 1
}

output_dir="$(dirname "$output")"
mkdir -p "$output_dir"
work="$(mktemp -d "$output_dir/.cabextract-static.build.XXXXXX")"
candidate=""
cleanup()
{
    case "$work" in
        "$output_dir"/.cabextract-static.build.*) rm -rf -- "${work:?}" ;;
        *) echo "!! refusing to remove unexpected cabextract build path" >&2; return 1 ;;
    esac
    [ -z "$candidate" ] || rm -f -- "$candidate"
}
trap cleanup EXIT

relabel=""
if [ -f /sys/fs/selinux/enforce ]; then relabel=",Z"; fi
"$ENGINE" run --rm \
    -v "$root:/src:ro$relabel" \
    -v "$work:/out:rw$relabel" \
    "$IMAGE" bash -ec '
        mkdir -p /work/cab && cd /work/cab
        tar xzf /src/vendor/cabextract-1.11.tar.gz --strip-components=1
        ./configure LDFLAGS="-static" >/dev/null
        make -s
        ldd cabextract 2>&1 | grep -q "not a dynamic executable" || {
            echo "!! cabextract did not link statically" >&2; exit 1; }
        ./cabextract --version
        strip cabextract
        install -m755 cabextract /out/cabextract-static'

[ -x "$work/cabextract-static" ] || {
    echo "!! cabextract build did not produce an executable" >&2
    exit 1
}
"$work/cabextract-static" --version >/dev/null 2>&1 || {
    echo "!! rebuilt cabextract-static does not run on this host" >&2
    exit 1
}
candidate="$(mktemp "$output_dir/.cabextract-static.install.XXXXXX")"
install -m755 "$work/cabextract-static" "$candidate"
mv -fT -- "$candidate" "$output"
candidate=""
echo "built $output"
