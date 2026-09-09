#!/bin/sh
# scripts/package-release.sh
#
# Release packaging pipeline for ICCery v2 macOS.
#
# Steps:
#   1. Fetch and ad-hoc sign Argyll sidecars (scripts/fetch-argyll.sh).
#   2. Generate the Xcode project from project.yml.
#   3. Build a universal Release ICCery.app.
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

echo "==> Fetching Argyll sidecars"
scripts/fetch-argyll.sh

echo "==> Generating Xcode project"
xcodegen generate --project .

CONFIG="Release"
DEST="platform=macOS"

# Default to ad-hoc signing. A real Developer ID can be injected via env.
IDENTITY="${CODESIGN_IDENTITY:--}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"

echo "==> Building universal Release app"
BUILD_EXTRA=""
if [ -n "$DEVELOPMENT_TEAM" ]; then
    BUILD_EXTRA="DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
fi

# shellcheck disable=SC2086
xcodebuild \
    -scheme ICCery \
    -destination "$DEST" \
    -configuration "$CONFIG" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    $BUILD_EXTRA \
    build

echo "==> Locating built app"
BUILT_PRODUCTS_DIR="$(xcodebuild \
    -scheme ICCery \
    -destination "$DEST" \
    -configuration "$CONFIG" \
    -showBuildSettings \
    | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' \
    | head -n 1)"

APP="$BUILT_PRODUCTS_DIR/ICCery.app"
if [ ! -d "$APP" ]; then
    echo "error: built app not found at $APP" >&2
    exit 1
fi
echo "App: $APP"

# If a Developer ID identity was supplied, re-sign the .app bundle. Sidecars
# live in Resources/Argyll and remain ad-hoc signed by fetch-argyll.sh.
if [ -n "${CODESIGN_IDENTITY:-}" ] && [ "$CODESIGN_IDENTITY" != "-" ]; then
    echo "==> Signing $APP with '$CODESIGN_IDENTITY'"
    codesign --force --sign "$CODESIGN_IDENTITY" \
        --entitlements Resources/ICCery.entitlements \
        --options runtime \
        "$APP"
else
    echo "==> App ad-hoc signed by xcodebuild; not re-signing"
fi

echo "==> Verifying sidecar signatures"
scripts/verify-sidecar-signatures.sh "$APP"

echo "==> Building DMG"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null || echo '2.0.0')"
BUILD_NUM="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist" 2>/dev/null || echo '1')"
DMG="ICCery-${VERSION}-${BUILD_NUM}.dmg"
VOLUME_NAME="ICCery ${VERSION}"

if ! command -v dmgbuild >/dev/null 2>&1; then
    echo "==> Installing dmgbuild"
    pip3 install dmgbuild
fi

DMG_FILENAME="$DMG" \
DMG_VOLUME_NAME="$VOLUME_NAME" \
dmgbuild -s scripts/dmgbuild-settings.py "$VOLUME_NAME" "$DMG"

echo "DMG: $PWD/$DMG"

# Optional notarization/stapling when credentials are present.
if [ -n "${NOTARIZE_APPLE_ID:-}" ] && \
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
else
    echo "==> Notarization credentials not set; skipping"
fi
