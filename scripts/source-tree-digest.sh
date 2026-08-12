#!/usr/bin/env bash
# Hash a source candidate, including new files and excluding generated dist
# output. Deleted tracked paths are absent from the digest. build.sh supplies
# the frozen path list when hashing its immutable build snapshot.
set -euo pipefail
export LC_ALL=C

root="$(cd "$(dirname "$0")/.." && pwd)"
paths_from=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --root)
            [ "$#" -ge 2 ] || { echo "!! --root needs a directory" >&2; exit 2; }
            root="$2"
            shift 2
            ;;
        --paths-from)
            [ "$#" -ge 2 ] || { echo "!! --paths-from needs a NUL-delimited file" >&2; exit 2; }
            paths_from="$2"
            shift 2
            ;;
        *)
            echo "usage: $0 [--root DIR --paths-from NUL_FILE]" >&2
            exit 2
            ;;
    esac
done

[ -d "$root" ] && [ ! -L "$root" ] || {
    echo "!! source-tree root must be a real directory: $root" >&2
    exit 1
}
root="$(cd "$root" && pwd)"
if [ -n "$paths_from" ]; then
    [ -f "$paths_from" ] && [ ! -L "$paths_from" ] || {
        echo "!! source-tree path list must be a regular file: $paths_from" >&2
        exit 1
    }
    paths_from="$(cd "$(dirname "$paths_from")" && pwd)/$(basename "$paths_from")"
fi
cd "$root"

source_paths()
{
    if [ -n "$paths_from" ]; then
        sort -z -- "$paths_from"
    else
        git ls-files -z --cached --others --exclude-standard -- . ':(exclude)dist' \
            | sort -z
    fi
}

source_paths \
    | while IFS= read -r -d '' path; do
        case "$path" in
            ''|.|/*|../*|*/../*|*/..)
                echo "!! unsafe source-tree path: $path" >&2
                exit 1
                ;;
        esac
        [ -e "$path" ] || [ -L "$path" ] || continue
        printf '%s\0' "$path"
        if [ -L "$path" ]; then
            printf 'link\0'
            readlink -- "$path"
            printf '\0'
        elif [ -f "$path" ]; then
            if [ -x "$path" ]; then printf 'executable\0'; else printf 'file\0'; fi
            sha256sum -z -- "$path" | dd bs=1 count=64 status=none
            printf '\0'
        else
            echo "!! unsupported source-tree file type: $path" >&2
            exit 1
        fi
    done \
    | sha256sum \
    | awk '{print $1}'
