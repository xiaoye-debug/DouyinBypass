#!/bin/bash
# DouyinBypass - Build and package script
# Run on macOS with Theos installed, or on Linux with theos-sdk

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[DouyinBypass] Building tweak..."
make clean
make package FINALPACKAGE=1

echo "[DouyinBypass] Build complete!"
echo "DEB package location: $SCRIPT_DIR/packages/"
ls -la packages/*.deb 2>/dev/null || echo "No .deb found in packages/"
