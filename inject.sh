#!/bin/bash
# DouyinBypass IPA Injection Script
# Usage: ./inject.sh <input.ipa> [output.ipa] [identity]
#
# This script injects DouyinBypass.dylib into a Douyin IPA
# and re-signs it for sideloading.

set -e

INPUT_IPA="${1:-}"
OUTPUT_IPA="${2:-${INPUT_IPA%.ipa}_patched.ipa}"
IDENTITY="${3:--}"  # default: ad-hoc sign
DYLIB="$(dirname "$0")/packages/DouyinBypass.dylib"

if [ -z "$INPUT_IPA" ]; then
    echo "Usage: $0 <input.ipa> [output.ipa] [codesign-identity]"
    echo ""
    echo "Examples:"
    echo "  $0 douyin.ipa                          # ad-hoc sign"
    echo "  $0 douyin.ipa patched.ipa              # custom output"
    echo "  $0 douyin.ipa out.ipa 'iPhone Developer'  # with identity"
    exit 1
fi

if [ ! -f "$DYLIB" ]; then
    echo "[ERROR] Dylib not found: $DYLIB"
    echo "Run make package-dylib first, or download from GitHub Actions artifacts."
    exit 1
fi

WORKDIR="$(mktemp -d)"
trap "rm -rf $WORKDIR" EXIT

echo "[1/5] Extracting IPA..."
unzip -q "$INPUT_IPA" -d "$WORKDIR"

APP="$(find $WORKDIR/Payload -name '*.app' -maxdepth 1 | head -1)"
if [ -z "$APP" ]; then
    echo "[ERROR] No .app found in IPA"
    exit 1
fi
echo "  App: $APP"

BINARY="$(defaults read $APP/Info.plist CFBundleExecutable)"
echo "  Binary: $BINARY"

echo "[2/5] Injecting dylib..."
cp "$DYLIB" "$APP/Frameworks/DouyinBypass.dylib"

echo "[3/5] Adding LC_LOAD_DYLIB..."
# Use insert_dylib if available, otherwise use optool or python
if command -v insert_dylib &> /dev/null; then
    insert_dylib --strip-codesig --all-yes "@executable_path/Frameworks/DouyinBypass.dylib" "$APP/$BINARY"
elif command -v optool &> /dev/null; then
    optool install -c load -p "@executable_path/Frameworks/DouyinBypass.dylib" -t "$APP/$BINARY"
else
    echo "  [WARN] Neither insert_dylib nor optool found."
    echo "  Install via: brew install insert_dylib"
    echo "  Trying python fallback..."
    python3 -c ""import sys; sys.exit(1)" 2>/dev/null && python3 "$(dirname "$0")/patch_binary.py" "$APP/$BINARY" || echo "  [ERROR] Manual injection needed"
fi

echo "[4/5] Re-signing..."
if [ "$IDENTITY" = "-" ]; then
    find "$APP" -name '*.dylib' -o -name '*.framework' | while read f; do
        codesign -fs "-" "$f" 2>/dev/null || true
    done
    codesign -fs "-" "$APP"
else
    find "$APP" -name '*.dylib' -o -name '*.framework' | while read f; do
        codesign -fs "$IDENTITY" "$f" 2>/dev/null || true
    done
    codesign -fs "$IDENTITY" "$APP"
fi

echo "[5/5] Repackaging IPA..."
cd "$WORKDIR"
zip -qr "$OLDPWD/$OUTPUT_IPA" Payload/

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_IPA"
echo "Install with AltStore, Sideloadly, or TrollStore."
