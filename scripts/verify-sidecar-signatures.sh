#!/bin/sh
# scripts/verify-sidecar-signatures.sh
#
# Hard-fail check that every Mach-O Argyll sidecar shipped inside the built
# ICCery.app bundle is signed (ad-hoc or Developer ID). The Argyll tree is
# nested (Vendor/Argyll/macos-universal/… is rsynced into Resources/Argyll by
# the project.yml post-build script), so this scan is recursive — #165 applies
# to binaries at any depth, including mocks/.
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

MACHO_COUNT=0
UNSIGNED=""
while IFS= read -r f; do
    [ -f "$f" ] || continue
    MACHO_COUNT=$((MACHO_COUNT + 1))
    if ! codesign -dvv "$f" >/dev/null 2>&1; then
        echo "error: unsigned Mach-O sidecar: $f" >&2
        UNSIGNED="$UNSIGNED $f"
    fi
done <<EOF
$(find "$SIDECAR_DIR" -type f -exec sh -c \
    'for p do file -b "$p" | grep -q "Mach-O" && printf "%s\n" "$p"; done' \
    _ {} +)
EOF

if [ -n "$UNSIGNED" ]; then
    echo "error: unsigned Argyll sidecars remain:$UNSIGNED" >&2
    exit 1
fi

if [ "$MACHO_COUNT" -eq 0 ]; then
    echo "error: no Mach-O sidecars found under $SIDECAR_DIR" >&2
    exit 1
fi

echo "OK: all $MACHO_COUNT Mach-O sidecars under $SIDECAR_DIR are signed"
