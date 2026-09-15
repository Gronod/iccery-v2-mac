#!/bin/sh
# scripts/version.sh
#
# Resolve the ICCery version triple and print KEY=value lines for eval:
#
#   ICCERY_RELEASE_TAG      release tag / describe string stamped into the
#                           bundle's ICCeryReleaseTag Info.plist key and shown
#                           in the About dialog.
#   MARKETING_VERSION       CFBundleShortVersionString — strict X.Y.Z only
#                           (Apple forbids suffixes; tag payload never lands here).
#   CURRENT_PROJECT_VERSION CFBundleVersion — monotonically increasing integer.
#                           macOS/App-Store convention: never reset per version.
#
# Resolution:
#   RELEASE_TAG env matching 'v[0-9]*' wins (CI tag builds; branch pushes pass
#   the branch name and are ignored). Otherwise `git describe` on the worktree.
#   Marketing version = first three numeric components of the tag core; a tag
#   with no numeric core falls back to project.yml's MARKETING_VERSION.
#   Build number = BUILD_NUMBER env override, else `git rev-list --count HEAD`.
#
# Hard fails (release-tag builds only): tag core not 1-3 numeric components,
# or parsed X.Y.Z != project.yml MARKETING_VERSION — bump project.yml or fix
# the tag before packaging.
#
# Usage: eval "$(scripts/version.sh)"

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

YML_MARKETING="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -n 1)"

TAG="${RELEASE_TAG:-}"
case "$TAG" in
    v[0-9]*) ;;           # real release tag
    *) TAG="" ;;          # branch name (develop, feat/...) or empty
esac
IS_RELEASE_TAG=0
[ -n "$TAG" ] && IS_RELEASE_TAG=1

if [ -z "$TAG" ]; then
    TAG="$(git describe --tags --always --dirty --match 'v[0-9]*' 2>/dev/null || true)"
fi
[ -n "$TAG" ] || TAG="dev"

# Marketing version: strip leading v, cut at first '-', keep first 3 dot
# components. "v2.0.0-pre2" -> "2.0.0"; "v2.0.0.0-x" -> "2.0.0";
# "v2.0.0-5-gsha" -> "2.0.0"; bare sha/"dev" -> no numeric core -> fallback.
CORE="${TAG#v}"
CORE="${CORE%%-*}"
MV=""
case "$CORE" in
    *[!0-9.]*|'') ;;               # non-numeric core — not a version tag
    *)
        MV="$(printf '%s' "$CORE" | cut -d. -f1-3)"
        # Every kept component must be non-empty digits.
        case "$MV" in
            *[!0-9.]*|''|*..*|.*|*.) MV="" ;;
        esac
        ;;
esac

if [ "$IS_RELEASE_TAG" -eq 1 ]; then
    if [ -z "$MV" ]; then
        echo "error: release tag '$TAG' has no X.Y.Z numeric core" >&2
        exit 1
    fi
    if [ -n "$YML_MARKETING" ] && [ "$MV" != "$YML_MARKETING" ]; then
        echo "error: tag '$TAG' resolves to $MV but project.yml MARKETING_VERSION=$YML_MARKETING; bump project.yml or fix the tag" >&2
        exit 1
    fi
fi
[ -n "$MV" ] || MV="$YML_MARKETING"
[ -n "$MV" ] || MV="0.0.0"

BUILD="${BUILD_NUMBER:-}"
if [ -z "$BUILD" ]; then
    BUILD="$(git rev-list --count HEAD 2>/dev/null || true)"
fi
case "$BUILD" in
    ''|*[!0-9]*) BUILD="1" ;;
esac
[ "$BUILD" -gt 0 ] 2>/dev/null || BUILD="1"

printf 'ICCERY_RELEASE_TAG=%s\n' "$TAG"
printf 'MARKETING_VERSION=%s\n' "$MV"
printf 'CURRENT_PROJECT_VERSION=%s\n' "$BUILD"
