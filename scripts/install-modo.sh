#!/usr/bin/env bash
# Downloads the mlange-42/modo doc-generator binary for the current
# platform into .tools/modo (gitignored, cached between runs -- see
# pixi.toml's own `docs`/`docs-install` tasks). modo isn't published
# to any conda/PyPI channel this workspace already trusts, so this
# mirrors the plain "grab the precompiled release binary" install path
# https://github.com/mlange-42/modo's own README documents, rather
# than adding an unrelated Go toolchain as a pixi dependency just to
# `go install` it.
set -euo pipefail

MODO_VERSION="0.11.13"
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.tools"
MODO_BIN="$TOOLS_DIR/modo"

if [ -x "$MODO_BIN" ] && "$MODO_BIN" --version 2>/dev/null | grep -q "$MODO_VERSION"; then
    exit 0
fi

case "$(uname -s)" in
    Linux) OS="linux" ;;
    Darwin) OS="macos" ;;
    *) echo "Unsupported OS for modo install: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture for modo install: $(uname -m)" >&2; exit 1 ;;
esac

if [ "$OS" = "linux" ]; then
    ASSET="modo-v${MODO_VERSION}-${OS}-${ARCH}.tar.gz"
else
    ASSET="modo-v${MODO_VERSION}-${OS}-${ARCH}.zip"
fi

URL="https://github.com/mlange-42/modo/releases/download/v${MODO_VERSION}/${ASSET}"

mkdir -p "$TOOLS_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading modo v${MODO_VERSION} for ${OS}-${ARCH}..."
curl -sSL -o "$TMP/$ASSET" "$URL"

if [ "$OS" = "linux" ]; then
    tar xzf "$TMP/$ASSET" -C "$TMP"
else
    unzip -q "$TMP/$ASSET" -d "$TMP"
fi

mv "$TMP/modo" "$MODO_BIN"
chmod +x "$MODO_BIN"
echo "Installed $MODO_BIN"
