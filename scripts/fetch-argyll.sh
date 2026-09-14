#!/bin/sh
# scripts/fetch-argyll.sh
#
# Downloads the Gronod ArgyllCMS fork release (macOS universal binaries)
# into Vendor/Argyll/. POSIX sh + curl + tar — no Node dependency.
#
# Env overrides (parity with v1 fetch-argyll.mjs):
#   ARGYLL_SERVER_URL   default https://git.i3omb.com
#   ARGYLL_REPO         default gronod/argyllcms
#   ARGYLL_RELEASE_TAG   default: latest release
#   GITEA_TOKEN         optional, for private repos
#
# Layout produced (docs/04 §0.6, docs/02 §Sidecar layout):
#   Vendor/Argyll/macos-universal/<tools>   # marker binary: instlist
# Mocks and reference_gamuts are tracked under Resources/Argyll/ —
# they ship in git, not in the release tarball.

set -eu

SERVER="${ARGYLL_SERVER_URL:-https://git.i3omb.com}"
REPO="${ARGYLL_REPO:-gronod/argyllcms}"
TAG="${ARGYLL_RELEASE_TAG:-}"
SUFFIX="_macOS_universal_bin.tgz"
PLATFORM_DIR="macos-universal"
MARKER="instlist"

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
DEST="$ROOT/Vendor/Argyll/$PLATFORM_DIR"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        *) echo "usage: $0 [--force]" >&2; exit 2 ;;
    esac
done

if [ "$FORCE" -eq 0 ] && [ -x "$DEST/$MARKER" ]; then
    echo "ArgyllCMS binaries already present at $DEST (use --force to re-download)"
    exit 0
fi

AUTH_HEADER=""
if [ -n "${GITEA_TOKEN:-}" ]; then
    AUTH_HEADER="Authorization: token $GITEA_TOKEN"
fi

api_get() {
    if [ -n "$AUTH_HEADER" ]; then
        curl -fsSL -H 'Accept: application/json' -H "$AUTH_HEADER" "$1"
    else
        curl -fsSL -H 'Accept: application/json' "$1"
    fi
}

if [ -n "$TAG" ]; then
    API_URL="$SERVER/api/v1/repos/$REPO/releases/tags/$TAG"
else
    API_URL="$SERVER/api/v1/repos/$REPO/releases/latest"
fi

echo "Fetching release info from $API_URL"
RELEASE_JSON="$(api_get "$API_URL")" || {
    echo "error: failed to fetch release info (set GITEA_TOKEN if the repo is private)" >&2
    exit 1
}

# Find the macOS universal asset's browser_download_url without jq.
ASSET_URL="$(printf '%s' "$RELEASE_JSON" \
    | tr ',' '\n' \
    | grep '"browser_download_url"' \
    | grep "$SUFFIX" \
    | sed -E 's/.*"browser_download_url"[^"]*"([^"]+)".*/\1/' \
    | head -n 1)"

if [ -z "$ASSET_URL" ]; then
    echo "error: no release asset matching '*$SUFFIX' on $API_URL" >&2
    echo "looked-for pattern: Argyll_<tag>_<sha>$SUFFIX" >&2
    exit 1
fi

echo "Downloading $ASSET_URL"
TMPDIR_FETCH="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_FETCH"' EXIT
ARCHIVE="$TMPDIR_FETCH/argyll.tgz"

if [ -n "$AUTH_HEADER" ]; then
    curl -fSL -o "$ARCHIVE" -H "$AUTH_HEADER" "$ASSET_URL"
else
    curl -fSL -o "$ARCHIVE" "$ASSET_URL"
fi

EXTRACT="$TMPDIR_FETCH/extract"
mkdir -p "$EXTRACT"
tar -xzf "$ARCHIVE" -C "$EXTRACT"

# Archive contains Argyll_V*/bin/ (or a bare bin/).
BIN_DIR=""
for d in "$EXTRACT"/Argyll_V*/bin "$EXTRACT"/bin; do
    if [ -d "$d" ]; then BIN_DIR="$d"; break; fi
done
if [ -z "$BIN_DIR" ]; then
    echo "error: archive has no Argyll_V*/bin or bin/ directory" >&2
    exit 1
fi

mkdir -p "$DEST"
cp -R "$BIN_DIR"/. "$DEST"/
# Copy License.txt from archive root (same level as bin/) to Vendor/Argyll/ root
VENDOR_ROOT="$ROOT/Vendor/Argyll"
for license_src in "$EXTRACT"/Argyll_V*/License.txt "$EXTRACT"/License.txt; do
    if [ -f "$license_src" ]; then
        cp "$license_src" "$VENDOR_ROOT/License.txt"
        break
    fi
done
find "$DEST" -type f -exec chmod 0755 {} +
# Downloads carry com.apple.quarantine; the app cannot spawn quarantined tools.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
# Also remove quarantine from Vendor/Argyll root if License.txt was copied
xattr -dr com.apple.quarantine "$VENDOR_ROOT" 2>/dev/null || true

# Ad-hoc sign every Mach-O (#165: unsigned arm64 → "Killed: 9"), then
# verify — an unsigned sidecar fails the script. The tree may nest
# (e.g. platform subdirs), so scan recursively.
find "$DEST" -type f -exec sh -c \
    'for p do file -b "$p" | grep -q "Mach-O" && codesign -f -s - "$p"; done' \
    _ {} + 2>/dev/null || true

UNSIGNED=""
while IFS= read -r f; do
    [ -f "$f" ] || continue
    if ! codesign -dvv "$f" >/dev/null 2>&1; then
        UNSIGNED="$UNSIGNED $f"
    fi
done <<EOF
$(find "$DEST" -type f -exec sh -c \
    'for p do file -b "$p" | grep -q "Mach-O" && printf "%s\n" "$p"; done' \
    _ {} +)
EOF
if [ -n "$UNSIGNED" ]; then
    echo "error: unsigned binaries remain:$UNSIGNED" >&2
    exit 1
fi

if [ ! -x "$DEST/$MARKER" ]; then
    echo "error: marker binary $MARKER missing after extraction" >&2
    exit 1
fi

echo "OK: $(ls "$DEST" | wc -l | tr -d ' ') tools installed to $DEST"
