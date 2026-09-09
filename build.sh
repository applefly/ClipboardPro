#!/bin/bash
# build.sh - 一键构建 ClipBoard Pro
set -e

APP_NAME="ClipboardManager"
APP_BUNDLE="${APP_NAME}.app"
SOURCE="${APP_NAME}.swift"
EXECUTABLE="${APP_NAME}"
INFO_PLIST="Info.plist"

# 切到脚本所在目录,保证任意位置可执行
cd "$(dirname "$0")"

if [ ! -f "$SOURCE" ]; then
    echo "Error: $SOURCE not found in $(pwd)"
    exit 1
fi

if [ ! -f "$INFO_PLIST" ]; then
    echo "Error: $INFO_PLIST not found in $(pwd)"
    exit 1
fi

echo "==> Compiling $SOURCE ..."
swiftc -O \
    -framework Cocoa \
    -framework Carbon \
    -framework ApplicationServices \
    -framework CoreGraphics \
    "$SOURCE" \
    -o "$EXECUTABLE"

echo "==> Assembling $APP_BUNDLE ..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

# 清理中间可执行文件
rm -f "$EXECUTABLE"

# macOS 12+ 需要签名才能正常运行(自签足够)
echo "==> Ad-hoc signing ..."
codesign --force --sign - "$APP_BUNDLE"

echo ""
echo "Done. Built: $APP_BUNDLE"
echo "Run with:    open '$APP_BUNDLE'"
