#!/usr/bin/env bash
# Downloads the official Godot build (Linux x86_64) to ~/.local/bin/godot.
# Usage: tools/install_godot.sh [version]   e.g. tools/install_godot.sh 4.5.1
# Current versions: https://github.com/godotengine/godot/releases
set -euo pipefail

VERSION="${1:-4.5.1}"
NAME="Godot_v${VERSION}-stable_linux.x86_64"
URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable/${NAME}.zip"
DEST="$HOME/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $URL"
curl -fL --progress-bar -o "$TMP/godot.zip" "$URL"
unzip -q "$TMP/godot.zip" -d "$TMP"
mkdir -p "$DEST"
install -m 755 "$TMP/$NAME" "$DEST/godot"
echo "Installed: $DEST/godot ($("$DEST/godot" --version 2>/dev/null || echo '?'))"
echo "Make sure $DEST is on your PATH."
