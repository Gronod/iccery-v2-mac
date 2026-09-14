#!/bin/sh
# scripts/ensure-host-tools.sh
#
# Bootstrap host tools needed by CI on the macOS 12 runner:
#   - xcodegen: always. Pinned prebuilt release from GitHub (Homebrew's
#     current formula requires Xcode 15.3, which cannot be installed on
#     macOS 12).
#   - dmgbuild: only when INSTALL_DMGBUILD=1 or --dmgbuild. Isolated in
#     build/.venv-dmgbuild so the test job never pip-installs it.
#
# dmgbuild 1.6.6+, ds_store 1.3.2+ and mac_alias 2.2.3 declare
# Requires-Python >= 3.10. The wheels are py3-none-any and run on the
# runner's 3.9; PIP_IGNORE_REQUIRES_PYTHON is required or pip will only
# offer 1.6.5 and keep a cached venv on that version (#95).
# pip itself is capped at <26.1: 26.1+ needs Python 3.10.
#
# Safe to run repeatedly: existing tools are left alone unless the
# dmgbuild pin is not met.

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
XCODEGEN_VERSION="2.38.0"
INSTALL_ROOT="${XCODEGEN_HOME:-$HOME/.local/xcodegen/$XCODEGEN_VERSION}"
VENV="$ROOT/build/.venv-dmgbuild"
DMGBUILD_PIN="1.6.7"

INSTALL_DMGBUILD="${INSTALL_DMGBUILD:-0}"
for arg in "$@"; do
    case "$arg" in
        --dmgbuild) INSTALL_DMGBUILD=1 ;;
    esac
done

if [ "$INSTALL_DMGBUILD" = "1" ]; then
    echo "==> Ensuring dmgbuild==$DMGBUILD_PIN in $VENV"
    mkdir -p "$ROOT/build"
    # pip 26.1+ requires Python 3.10 (dataclass slots). A leftover
    # `pip install --upgrade pip` on this 3.9 venv installed 26.2.1 and
    # the next pip invocation crashed. Recreate if pip is already dead.
    if [ -x "$VENV/bin/python" ] \
        && ! "$VENV/bin/python" -m pip --version >/dev/null 2>&1; then
        echo "==> venv pip is broken; recreating $VENV"
        rm -rf "$VENV"
    fi
    if [ ! -x "$VENV/bin/python" ]; then
        python3 -m venv "$VENV"
    fi
    # Without this, pip on Python 3.9 hides 1.6.6+ and leaves 1.6.5.
    PIP_IGNORE_REQUIRES_PYTHON=1
    export PIP_IGNORE_REQUIRES_PYTHON
    "$VENV/bin/python" -m pip install --upgrade 'pip>=24.3,<26.1'
    "$VENV/bin/python" -m pip install --upgrade --force-reinstall \
        "dmgbuild==$DMGBUILD_PIN" \
        'ds_store>=1.3.3' \
        'mac_alias>=2.2.3'
    "$VENV/bin/python" -c 'from importlib.metadata import version
print("dmgbuild", version("dmgbuild"))
print("ds_store", version("ds_store"))
print("mac_alias", version("mac_alias"))
parts=[]
for p in version("dmgbuild").split("."):
    try:
        parts.append(int("".join(c for c in p if c.isdigit()) or "0"))
    except ValueError:
        parts.append(0)
parts += [0, 0, 0]
raise SystemExit(0 if tuple(parts[:3]) >= (1, 6, 7) else 1)
'
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
