#!/usr/bin/env bash
# Publish the current VERSION as a GitHub release.
#
#   env GH_TOKEN=<fine-grained-PAT> ./scripts/release.sh
#   env GH_TOKEN=... ./scripts/release.sh --notes-file notes.md
#
# --notes-file takes a hand-written markdown summary of the release and puts
# it at the top of the release body, above the install instructions and build
# provenance the workflow generates. The file is read at publish time and is
# not committed anywhere; keep it outside this checkout. Without the flag
# the body is exactly what the workflow drafted, as before.
#
# Verifies the locally built dist/ artifacts, pushes the v<VERSION> tag (the
# release workflow then drafts the release with notes from BUILD-INFO),
# uploads the assets, and publishes. Alongside the versioned installer it
# uploads a stable-named copy, install-ableton-latest.run, so
#   https://github.com/<repo>/releases/latest/download/install-ableton-latest.run
# always serves the newest build. CI never rebuilds Wine; the bits released
# are the bits verified here.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
cd "$root"

notes=""
while [ $# -gt 0 ]; do
    case "$1" in
        --notes-file)
            [ $# -ge 2 ] || { echo "!! --notes-file needs a path" >&2; exit 1; }
            notes="$2"; shift 2 ;;
        *) echo "!! unknown argument: $1 (see the header of $0)" >&2; exit 1 ;;
    esac
done

NAME="wine-d2d1-nspa-11.13"
VERSION="$(cat VERSION)"
TAG="v$VERSION"
run="dist/ableton-wine-setup-${VERSION}.run"
tarball="dist/${NAME}-${VERSION}.tar.zst"
info="dist/BUILD-INFO-${VERSION}.txt"

command -v jq >/dev/null || { echo "!! jq is required" >&2; exit 1; }
token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[ -n "$token" ] || { echo "!! set GH_TOKEN (fine-grained PAT with contents read/write)" >&2; exit 1; }
repo="$(git remote get-url origin | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
api="https://api.github.com/repos/$repo"
gh_api() { curl -fsS -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "$@"; }
release_commit="$(git rev-parse --verify HEAD)"

verify_checksum_record()
{
    local record="$1" artifact="$2" hash name extra
    [ -f "$record" ] && [ ! -L "$record" ] || {
        echo "!! missing checksum record: $record" >&2; return 1; }
    [ "$(wc -l < "$record")" -eq 1 ] || {
        echo "!! checksum record must contain one line: $record" >&2; return 1; }
    read -r hash name extra < "$record"
    name="${name#\*}"
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] && [ -z "$extra" ] \
        && [ "$name" = "$(basename "$artifact")" ] \
        && [ "$hash" = "$(sha256sum "$artifact" | awk '{print $1}')" ] || {
        echo "!! checksum record does not bind $(basename "$artifact"): $record" >&2
        return 1
    }
}

echo "== [0/4] verify the $VERSION artifacts =="
# fail on a bad --notes-file now, not after the tag is pushed and 112M uploaded
if [ -n "$notes" ]; then
    [ -f "$notes" ] || { echo "!! no such notes file: $notes" >&2; exit 1; }
    grep -q '[^[:space:]]' "$notes" || { echo "!! notes file is empty: $notes" >&2; exit 1; }
fi
for f in "$tarball" "$tarball.sha256" "$info"; do
    [ -f "$f" ] || { echo "!! missing $f: run ./build.sh first" >&2; exit 1; }
done
git ls-files --error-unmatch "$info" "$tarball.sha256" >/dev/null 2>&1 \
    || { echo "!! BUILD-INFO and the runtime checksum must be committed at the tag" >&2; exit 1; }
git diff --quiet HEAD -- VERSION "$info" "$tarball.sha256" \
    || { echo "!! VERSION or a release record has uncommitted changes: commit them first" >&2; exit 1; }
source_changes="$(git status --porcelain --untracked-files=all -- . ':(exclude)dist')"
[ -z "$source_changes" ] || {
    echo "!! source tree has changes outside generated dist/; commit or remove them before release" >&2
    printf '%s\n' "$source_changes" >&2
    exit 1
}
bash scripts/build-audit.sh "$tarball"
verify_checksum_record "$tarball.sha256" "$tarball"

# Always seal a new wrapper from this clean source candidate. This binds every
# packaged script, document, helper, and vendored input to the commit that will
# receive the tag instead of trusting an older ignored dist/ wrapper.
./scripts/make-installer.sh
for f in "$run" "$run.sha256"; do
    [ -f "$f" ] || { echo "!! installer packaging did not produce $f" >&2; exit 1; }
done
bash scripts/check-release-build-info.sh "$info" \
    --version "$VERSION" --runtime "$tarball" --installer "$run"
verify_checksum_record "$run.sha256" "$run"

# Copy the verified artifacts once and use only these sealed copies after the
# tag is pushed. A background change to ignored dist/ output cannot alter the
# bytes uploaded later in this run.
stage="$(mktemp -d /tmp/ableton-release-upload.XXXXXX)"
cleanup_release_stage()
{
    case "$stage" in
        /tmp/ableton-release-upload.*) rm -rf -- "${stage:?}" ;;
        *) echo "!! refusing to remove unexpected release stage" >&2; return 1 ;;
    esac
}
trap cleanup_release_stage EXIT
for artifact in "$run" "$run.sha256" "$tarball" "$tarball.sha256" "$info"; do
    install -m644 "$artifact" "$stage/$(basename "$artifact")"
done
sealed_run="$stage/$(basename "$run")"
sealed_tarball="$stage/$(basename "$tarball")"
sealed_info="$stage/$(basename "$info")"
verify_checksum_record "$sealed_run.sha256" "$sealed_run"
verify_checksum_record "$sealed_tarball.sha256" "$sealed_tarball"
bash scripts/check-release-build-info.sh "$sealed_info" \
    --version "$VERSION" --runtime "$sealed_tarball" --installer "$sealed_run"
cp "$sealed_run" "$stage/install-ableton-latest.run"
( cd "$stage" && sha256sum install-ableton-latest.run > install-ableton-latest.run.sha256 )
verify_checksum_record "$stage/install-ableton-latest.run.sha256" \
    "$stage/install-ableton-latest.run"

echo "== [1/4] push tag $TAG =="
[ "$(git rev-parse --verify HEAD)" = "$release_commit" ] || {
    echo "!! HEAD changed during release preflight; refusing to tag different source" >&2
    exit 1
}
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
    || git tag -a "$TAG" -m "$VERSION" "$release_commit"
[ "$release_commit" = "$(git rev-list -n 1 "$TAG")" ] || {
    echo "!! $TAG does not point to the verified commit; refusing to replace its release" >&2
    exit 1
}
git push origin "$TAG"

echo "== [2/4] wait for the draft release (created by the release workflow) =="
release_record=""
for _ in $(seq 1 30); do
    release_record="$(gh_api "$api/releases?per_page=30" \
        | jq -c --arg t "$TAG" 'first(.[] | select(.tag_name == $t)) // empty')"
    [ -n "$release_record" ] && break
    sleep 5
done
[ -n "$release_record" ] || {
    echo "!! no release for $TAG after 150s: check the repo's Actions tab, then rerun" >&2
    exit 1
}
rid="$(jq -r '.id' <<< "$release_record")"
require_draft_release()
{
    local record
    record="$(gh_api "$api/releases/$rid")"
    [ "$(jq -r '.tag_name' <<< "$record")" = "$TAG" ] \
        && [ "$(jq -r '.draft' <<< "$record")" = true ] || {
        echo "!! release $rid is not the unpublished draft for $TAG; refusing to replace assets" >&2
        exit 1
    }
}
require_draft_release

expected_assets="$({
    printf '%s\n' \
        "$(basename "$info")" \
        "$(basename "$run")" \
        "$(basename "$run").sha256" \
        "$(basename "$tarball")" \
        "$(basename "$tarball").sha256" \
        install-ableton-latest.run \
        install-ableton-latest.run.sha256
} | LC_ALL=C sort)"
release_asset_names()
{
    gh_api "$api/releases/$rid/assets?per_page=100" | jq -r '.[].name' | LC_ALL=C sort
}
reject_unexpected_assets()
{
    local existing name
    existing="$(release_asset_names)"
    while IFS= read -r name; do
        [ -z "$name" ] || grep -qxF -- "$name" <<< "$expected_assets" || {
            echo "!! draft release contains an unexpected asset: $name" >&2
            exit 1
        }
    done <<< "$existing"
}
require_exact_assets()
{
    local actual
    actual="$(release_asset_names)"
    [ "$actual" = "$expected_assets" ] || {
        echo "!! draft release asset set is incomplete or unexpected" >&2
        diff -u <(printf '%s\n' "$expected_assets") <(printf '%s\n' "$actual") >&2 || true
        exit 1
    }
}
reject_unexpected_assets

echo "== [3/4] upload assets =="
upload() {
    local f="$1" name old
    name="$(basename "$f")"
    # replace a leftover asset of the same name from an earlier attempt
    old="$(gh_api "$api/releases/$rid/assets?per_page=100" \
        | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)"
    [ -z "$old" ] || gh_api -X DELETE "$api/releases/assets/$old"
    echo "   $name"
    gh_api -X POST -H "Content-Type: application/octet-stream" --data-binary "@$f" \
        "https://uploads.github.com/repos/$repo/releases/$rid/assets?name=$name" >/dev/null
}
for f in "$sealed_run" "$sealed_run.sha256" \
         "$sealed_tarball" "$sealed_tarball.sha256" "$sealed_info" \
         "$stage/install-ableton-latest.run" "$stage/install-ableton-latest.run.sha256"; do
    upload "$f"
done
require_exact_assets

remote="$stage/downloaded"
mkdir -p "$remote"
download_asset()
{
    local name="$1" id
    id="$(gh_api "$api/releases/$rid/assets?per_page=100" \
        | jq -r --arg n "$name" 'first(.[] | select(.name == $n) | .id) // empty')"
    [ -n "$id" ] || { echo "!! uploaded asset is missing: $name" >&2; exit 1; }
    curl -fsSL -H "Authorization: Bearer $token" \
        -H "Accept: application/octet-stream" \
        "$api/releases/assets/$id" -o "$remote/$name"
}
for local_asset in \
    "$sealed_run" "$sealed_run.sha256" \
    "$sealed_tarball" "$sealed_tarball.sha256" "$sealed_info" \
    "$stage/install-ableton-latest.run" "$stage/install-ableton-latest.run.sha256"; do
    asset_name="$(basename "$local_asset")"
    download_asset "$asset_name"
    cmp -s -- "$local_asset" "$remote/$asset_name" || {
        echo "!! uploaded asset differs from its sealed local file: $asset_name" >&2
        exit 1
    }
done

echo "== [4/4] publish =="
require_draft_release
if [ -n "$notes" ]; then
    # The summary replaces the workflow's generated prose entirely and keeps
    # only its tail: the stable-installer link and the build provenance block.
    # The first sed drops any block an earlier run left, so re-running after a
    # failed upload replaces the summary rather than stacking a second copy,
    # and keeps a notes file that happens to contain the tail's first line from
    # confusing the second sed, which selects the tail itself.
    body="$(gh_api "$api/releases/$rid" | jq -r '.body // ""' \
        | sed '/<!-- release-notes:start -->/,/<!-- release-notes:end -->/d' \
        | sed -n '/^The newest installer is always at:/,$p')"
    [ -n "$body" ] || { echo "!! the drafted body has no installer/provenance tail:" \
        "check .github/workflows/release.yml against this script" >&2; exit 1; }
    jq -n --rawfile n "$notes" --arg b "$body" \
        '{body: ("<!-- release-notes:start -->\n" + $n
                 + "\n<!-- release-notes:end -->\n\n---\n\n" + $b), draft: false}' \
        | gh_api -X PATCH "$api/releases/$rid" -d @- >/dev/null
else
    gh_api -X PATCH "$api/releases/$rid" -d '{"draft": false}' >/dev/null
fi
echo
echo "OK: https://github.com/$repo/releases/tag/$TAG"
echo "Latest installer: https://github.com/$repo/releases/latest/download/install-ableton-latest.run"
