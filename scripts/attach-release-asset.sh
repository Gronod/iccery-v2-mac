#!/bin/sh
# scripts/attach-release-asset.sh
#
# Attach ICCery-*.dmg to the Gitea release for the current tag.
# actions/upload-artifact only stores a workflow artifact; it does not
# publish a release asset (run 29714 left v2.0.0-pre2-grok with no files).

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

TOKEN="${GITEA_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
    echo "error: GITEA_TOKEN or GITHUB_TOKEN is required to attach release assets" >&2
    exit 1
fi

SERVER="${GITEA_SERVER_URL:-${GITHUB_SERVER_URL:-https://git.i3omb.com}}"
SERVER="${SERVER%/}"
API="$SERVER/api/v1"

REPO="${GITHUB_REPOSITORY:-gronod/iccery-v2-mac}"
TAG="${RELEASE_TAG:-${GITHUB_REF_NAME:-}}"
if [ -z "$TAG" ] && [ -n "${GITHUB_REF:-}" ]; then
    TAG="${GITHUB_REF#refs/tags/}"
fi
if [ -z "$TAG" ] || [ "$TAG" = "${GITHUB_REF:-}" ]; then
    echo "error: no release tag (set RELEASE_TAG or GITHUB_REF_NAME)" >&2
    exit 1
fi

case "$TAG" in
    *prerelease*) PRERELEASE=true ;;
    *)            PRERELEASE=false ;;
esac

DMG="${1:-}"
if [ -z "$DMG" ]; then
    DMG="$(ls -1 ICCery-*.dmg 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$DMG" ] || [ ! -f "$DMG" ]; then
    echo "error: no ICCery-*.dmg to attach" >&2
    exit 1
fi
NAME="$(basename "$DMG")"

echo "==> Resolving release $TAG"
HTTP="$(mktemp)"
BODY="$(mktemp)"
STATUS="$(curl -sS -o "$BODY" -w '%{http_code}' \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/json" \
    "$API/repos/$REPO/releases/tags/$TAG" || true)"

if [ "$STATUS" = "404" ]; then
    echo "==> Creating release $TAG (prerelease=$PRERELEASE)"
    STATUS="$(curl -sS -o "$BODY" -w '%{http_code}' \
        -H "Authorization: token $TOKEN" \
        -H "Content-Type: application/json" \
        -X POST "$API/repos/$REPO/releases" \
        -d "{\"tag_name\":\"$TAG\",\"name\":\"$TAG\",\"prerelease\":$PRERELEASE,\"target_commitish\":\"${GITHUB_SHA:-}\"}")"
fi
if [ "$STATUS" != "200" ] && [ "$STATUS" != "201" ]; then
    echo "error: could not load/create release $TAG (HTTP $STATUS)" >&2
    cat "$BODY" >&2
    exit 1
fi

RELEASE_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$BODY")"
if [ -z "$RELEASE_ID" ]; then
    echo "error: release JSON missing id" >&2
    cat "$BODY" >&2
    exit 1
fi

# Replace a same-named asset so retags stay idempotent.
python3 - "$BODY" "$NAME" > "$HTTP" <<'PY'
import json, sys
rel = json.load(open(sys.argv[1]))
want = sys.argv[2]
for a in rel.get("assets") or []:
    if a.get("name") == want:
        print(a.get("id", ""))
        break
PY
EXISTING="$(cat "$HTTP")"
if [ -n "$EXISTING" ]; then
    echo "==> Replacing existing asset $NAME ($EXISTING)"
    curl -sS -o /dev/null -w '%{http_code}\n' \
        -H "Authorization: token $TOKEN" \
        -X DELETE "$API/repos/$REPO/releases/$RELEASE_ID/assets/$EXISTING" >/dev/null || true
fi

echo "==> Uploading $NAME to release $RELEASE_ID"
STATUS="$(curl -sS -o "$BODY" -w '%{http_code}' \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/json" \
    -F "attachment=@$DMG;filename=$NAME" \
    "$API/repos/$REPO/releases/$RELEASE_ID/assets?name=$NAME")"

if [ "$STATUS" != "201" ]; then
    echo "error: asset upload failed (HTTP $STATUS)" >&2
    cat "$BODY" >&2
    exit 1
fi
echo "Attached $NAME to $SERVER/$REPO/releases/tag/$TAG"
rm -f "$HTTP" "$BODY"
