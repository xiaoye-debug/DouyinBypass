#!/bin/bash
# DouyinBypass - Build DEB + Dylib
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
echo "[DouyinBypass] Building..."
make clean || true
make package-all FINALPACKAGE=1
echo ""
echo "=== Build Complete ==="
echo "  DEB:   packages/*.deb"
echo "  Dylib: packages/DouyinBypass.dylib"
ls -la packages/ 2>/dev/null || true
