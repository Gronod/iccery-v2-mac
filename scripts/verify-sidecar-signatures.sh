#!/bin/sh
# scripts/verify-sidecar-signatures.sh
#
# Hard-fail check that every Mach-O Argyll sidecar shipped inside the built
# ICCery.app bundle is signed (ad-hoc or Developer ID). Run this in CI after
# xcodebuild and before packaging.
#
# Usage: scripts/verify-sidecar-signatures.sh <path/to/ICCery.app>

set -eu

APP="${1:-}"
if [ -z "$APP" ]; then
    echo "usage: $0 <path/to/ICCery.app>" >&2
    exit 2
fi

if [ ! -d "$APP" ]; then
    echo "error: app bundle not found: $APP" >&2
    exit 1
fi

SIDECAR_DIR="$APP/Contents/Resources/Argyll"
if [ ! -d "$SIDECAR_DIR" ]; then
    echo "error: Argyll sidecar directory not found: $SIDECAR_DIR" >&2
    exit 1
fi

UNSIGNED=""
for f in "$SIDECAR_DIR"/*; do
    [ -f "$f" ] || continue
    if file -b "$f" | grep -q 'Mach-O'; then
        if ! codesign -dvv "$f" >/dev/null 2>&1; then
            echo "error: unsigned Mach-O sidecar: $f" >&2
            UNSIGNED="$UNSIGNED $f"
        fi
    fi
done

if [ -n "$UNSIGNED" ]; then
    echo "error: unsigned Argyll sidecars remain:$UNSIGNED" >&2
    exit 1
fi

echo "OK: all Mach-O sidecars in $SIDECAR_DIR are signed"
