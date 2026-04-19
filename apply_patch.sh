#!/bin/bash
# Run this from inside your cloned ish-app/ish directory
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[1/4] Copying MotionDevice files..."
cp "$SCRIPT_DIR/MotionDevice.h" app/
cp "$SCRIPT_DIR/MotionDevice.m" app/

echo "[2/4] Applying source patches..."
git apply "$SCRIPT_DIR/full_source.patch"

echo "[3/4] Done! Now in Xcode:"
echo "  - Add MotionDevice.m to Compile Sources"
echo "  - Link CoreMotion.framework"
echo "  - Change ROOT_BUNDLE_IDENTIFIER in iSH.xcconfig"
echo "  - Set your Development Team"
echo "  - Hit Run"
echo ""
echo "[4/4] After install, test with: cat /dev/motion"
