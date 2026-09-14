#!/bin/sh
# scripts/package-release.sh
#
# Release packaging pipeline for ICCery v2 macOS.
#
# Steps:
#   1. Fetch and ad-hoc sign Argyll sidecars (scripts/fetch-argyll.sh).
#   2. Generate the Xcode project from project.yml.
#   3. Build a universal Release ICCery.app with a fixed derived data path.
#   4. Sign the .app (Developer ID if CODESIGN_IDENTITY is set, else ad-hoc).
#   5. Hard-fail verify every bundled Mach-O sidecar with codesign -dvv.
#   6. Build a DMG with dmgbuild.
#   7. Optionally notarize and staple the DMG when notarization secrets exist.
#
# Required secrets (optional):
#   CODESIGN_IDENTITY    Developer ID Application identity name
#   DEVELOPMENT_TEAM     Apple development team ID (for xcodebuild signing)
#   NOTARIZE_APPLE_ID    Apple ID for notarytool
#   NOTARIZE_PASSWORD    App-specific password for notarytool
#   APPLE_TEAM_ID        Team ID for notarytool

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f project.yml ]; then
    echo "error: project.yml not found in $ROOT" >&2
    exit 1
fi

DERIVED="$ROOT/build/DerivedData"
mkdir -p "$DERIVED"

# Fetch sidecars first because the Xcode project copies them into the bundle.
echo "==> Fetching Argyll sidecars"
scripts/fetch-argyll.sh

echo "==> Generating Xcode project"
xcodegen generate --spec project.yml

CONFIG="Release"
DEST="platform=macOS"

IDENTITY="${CODESIGN_IDENTITY:--}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"

echo "==> Building universal Release app"
BUILD_EXTRA=""
if [ -n "$DEVELOPMENT_TEAM" ]; then
    BUILD_EXTRA="DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
fi

xcodebuild \
    -scheme ICCery \
    -destination "$DEST" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    $BUILD_EXTRA \
    build

APP="$DERIVED/Build/Products/$CONFIG/ICCery.app"
if [ ! -d "$APP" ]; then
    echo "error: built app not found at $APP" >&2
    exit 1
fi
echo "App: $APP"

# Sidecars are copied into the bundle by the build phase. Re-signing the .app
# with --force should keep them intact, but verify after and repair any that
# got stripped. Do not codesign --deep the bundle with Developer ID — sidecars
# stay ad-hoc.
if [ -n "${CODESIGN_IDENTITY:-}" ] && [ "$CODESIGN_IDENTITY" != "-" ]; then
    echo "==> Signing $APP with '$CODESIGN_IDENTITY'"
    codesign --force --sign "$CODESIGN_IDENTITY" \
        --entitlements Resources/ICCery.entitlements \
        --options runtime \
        --timestamp \
        --verbose \
        "$APP"

    echo "==> Verifying app signature"
    codesign --verify --deep --strict --verbose=2 "$APP"
fi

echo "==> Verifying sidecar signatures"
if ! scripts/verify-sidecar-signatures.sh "$APP"; then
    echo "==> Re-applying ad-hoc signature to sidecars"
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        codesign -f -s - --options runtime "$f" 2>/dev/null || true
    done <<EOF
$(find "$APP/Contents/Resources/Argyll" -type f -exec sh -c \
    'for p do file -b "$p" | grep -q "Mach-O" && printf "%s\n" "$p"; done' \
    _ {} +)
EOF

    echo "==> Re-verifying sidecar signatures"
    scripts/verify-sidecar-signatures.sh "$APP"
fi

echo "==> Installing / locating dmgbuild"
# Monterey CI Python is 3.9. dmgbuild 1.6.6+ declares Requires-Python
# >=3.10, so pip only offers 1.6.5 on this runner. Install the newest
# wheel this interpreter accepts; do not fail the job for 1.6.7.
VENV="$ROOT/build/.venv-dmgbuild"
if [ ! -d "$VENV/bin" ]; then
    python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --upgrade pip
"$VENV/bin/pip" install --upgrade dmgbuild
PATH="$VENV/bin:$PATH"
export PATH
if ! command -v dmgbuild >/dev/null 2>&1; then
    echo "error: dmgbuild not available after venv install" >&2
    exit 1
fi
DMGBUILD_VER="$("$VENV/bin/python" -c 'from importlib.metadata import version; print(version("dmgbuild"))')"
echo "dmgbuild $DMGBUILD_VER"
"$VENV/bin/python" -c 'import sys; print("venv python", sys.version)'

PNG1X="$ROOT/Resources/dmg-background.png"
PNG2X="$ROOT/Resources/dmg-background@2x.png"
if [ ! -f "$PNG1X" ] || [ ! -f "$PNG2X" ]; then
    echo "error: missing $PNG1X or $PNG2X" >&2
    exit 1
fi
mkdir -p "$ROOT/build"
DMG_BACKGROUND="$ROOT/build/dmg-background.tiff"
echo "==> Building HiDPI DMG background TIFF"
tiffutil -cathidpicheck "$PNG1X" "$PNG2X" -out "$DMG_BACKGROUND"
if [ ! -f "$DMG_BACKGROUND" ]; then
    echo "error: tiffutil did not write $DMG_BACKGROUND" >&2
    exit 1
fi

echo "==> Building DMG"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null || printf '2.0.0')"
BUILD_NUM="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist" 2>/dev/null || printf '1')"
DMG="ICCery-${VERSION}-${BUILD_NUM}.dmg"
VOLUME_NAME="ICCery ${VERSION}"

DMG_APP="$APP" \
DMG_FILENAME="$DMG" \
DMG_VOLUME_NAME="$VOLUME_NAME" \
DMG_BACKGROUND="$DMG_BACKGROUND" \
dmgbuild -s scripts/dmgbuild-settings.py "$VOLUME_NAME" "$DMG"

echo "DMG: $PWD/$DMG"

# Notarization requires a Developer ID signature. If the app was ad-hoc
# signed or any notarization secret is missing, skip silently — the DMG is
# still usable for local/testing installs.
if [ -n "${CODESIGN_IDENTITY:-}" ] && [ "$CODESIGN_IDENTITY" != "-" ] && \
   [ -n "${NOTARIZE_APPLE_ID:-}" ] && \
   [ -n "${NOTARIZE_PASSWORD:-}" ] && \
   [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "==> Submitting $DMG for notarization"
    xcrun notarytool submit "$DMG" \
        --apple-id "$NOTARIZE_APPLE_ID" \
        --password "$NOTARIZE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
    xcrun stapler staple "$DMG"
    echo "==> Stapled $DMG"
fi
