#!/bin/sh
# scripts/ensure-host-tools.sh
#
# Bootstrap host tools needed by CI on the macOS 12 runner:
#   - xcodegen: pinned prebuilt release from GitHub (Homebrew's current
#     formula requires Xcode 15.3, which cannot be installed on macOS 12).
#   - dmgbuild >= 1.6.7: via pip (bookmark-based DMG background, #95).
#
# Safe to run repeatedly: existing tools are left alone.

set -eu

XCODEGEN_VERSION="2.38.0"
INSTALL_ROOT="${XCODEGEN_HOME:-$HOME/.local/xcodegen/$XCODEGEN_VERSION}"

echo "==> Ensuring dmgbuild >= 1.6.7"
python3 -m pip install --upgrade 'dmgbuild>=1.6.7'

if command -v xcodegen >/dev/null 2>&1; then
    echo "==> xcodegen already on PATH: $(xcodegen --version)"
else
    echo "==> Installing xcodegen $XCODEGEN_VERSION (prebuilt)"
    TMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
    ZIP="$TMP/xcodegen-$XCODEGEN_VERSION.zip"
    curl -fL --retry 3 \
        "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip" \
        -o "$ZIP"
    rm -rf "$INSTALL_ROOT"
    mkdir -p "$INSTALL_ROOT"
    # Zip contains xcodegen/{bin/xcodegen,share/xcodegen/SettingPresets};
    # XcodeGen resolves its presets relative to the binary, so keep the tree.
    unzip -q "$ZIP" -d "$INSTALL_ROOT"
    BIN_DIR="$INSTALL_ROOT/xcodegen/bin"
    chmod +x "$BIN_DIR/xcodegen"
    if [ -n "${GITHUB_PATH:-}" ]; then
        echo "$BIN_DIR" >> "$GITHUB_PATH"
    fi
    PATH="$BIN_DIR:$PATH"
    echo "==> Installed: $("$BIN_DIR/xcodegen" --version)"
fi
