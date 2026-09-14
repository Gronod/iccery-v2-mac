#!/bin/sh
# scripts/ensure-host-tools.sh
#
# Bootstrap host tools needed by CI on the macOS 12 runner:
#   - xcodegen: always. Pinned prebuilt release from GitHub (Homebrew's
#     current formula requires Xcode 15.3, which cannot be installed on
#     macOS 12).
#   - dmgbuild: only when INSTALL_DMGBUILD=1 or --dmgbuild. Isolated in
#     build/.venv-dmgbuild so the test job never pip-installs it.
#     Monterey ships Python 3.9; dmgbuild 1.6.6+ requires Python >= 3.10,
#     so the newest installable wheel on this runner is 1.6.5 (#95).
#
# Safe to run repeatedly: existing tools are left alone.

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
XCODEGEN_VERSION="2.38.0"
INSTALL_ROOT="${XCODEGEN_HOME:-$HOME/.local/xcodegen/$XCODEGEN_VERSION}"
VENV="$ROOT/build/.venv-dmgbuild"

INSTALL_DMGBUILD="${INSTALL_DMGBUILD:-0}"
for arg in "$@"; do
    case "$arg" in
        --dmgbuild) INSTALL_DMGBUILD=1 ;;
    esac
done

if [ "$INSTALL_DMGBUILD" = "1" ]; then
    echo "==> Ensuring dmgbuild in $VENV"
    mkdir -p "$ROOT/build"
    if [ ! -x "$VENV/bin/python" ]; then
        python3 -m venv "$VENV"
    fi
    "$VENV/bin/pip" install --upgrade pip
    "$VENV/bin/pip" install --upgrade 'dmgbuild>=1.6.5'
    "$VENV/bin/python" -c 'from importlib.metadata import version; print("dmgbuild", version("dmgbuild"))'
    if [ -n "${GITHUB_PATH:-}" ]; then
        echo "$VENV/bin" >> "$GITHUB_PATH"
    fi
    PATH="$VENV/bin:$PATH"
    export PATH
else
    echo "==> Skipping dmgbuild (set INSTALL_DMGBUILD=1 for the package job)"
fi

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
