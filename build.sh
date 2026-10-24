#!/bin/zsh
set -euo pipefail
SOURCE_DIR="${0:A:h}"
DEST_DIR="${1:-$SOURCE_DIR/build}"
APP_PATH="$DEST_DIR/窗口记忆.app"
APP_VERSION="$(<"$SOURCE_DIR/VERSION")"
BUILD_ARCHS="${ARCHS:-arm64 x86_64}"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$DEST_DIR/intermediates"
SOURCES=("$SOURCE_DIR"/*.swift(N))
BINARIES=()
for BUILD_ARCH in ${=BUILD_ARCHS}; do
  [[ "$BUILD_ARCH" == arm64 || "$BUILD_ARCH" == x86_64 ]] || { echo "Unsupported architecture: $BUILD_ARCH" >&2; exit 1; }
  BINARY="$DEST_DIR/intermediates/WindowMemory-$BUILD_ARCH"
  xcrun swiftc -swift-version 5 -O -whole-module-optimization -target "$BUILD_ARCH-apple-macosx14.0" \
    "${SOURCES[@]}" -o "$BINARY" -framework AppKit -framework SwiftUI \
    -framework ApplicationServices -framework ServiceManagement -framework Carbon
  BINARIES+=("$BINARY")
done
xcrun lipo -create "${BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/WindowMemory"
cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.vic.windowmemory</string>
<key>CFBundleName</key><string>窗口记忆</string>
<key>CFBundleDisplayName</key><string>窗口记忆</string>
<key>CFBundleExecutable</key><string>WindowMemory</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 LZQVicLi. MIT License.</string>
</dict></plist>
PLIST
cp "$SOURCE_DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.vic.windowmemory "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
"$APP_PATH/Contents/MacOS/WindowMemory" --self-test
echo "Built $APP_VERSION: $APP_PATH"
