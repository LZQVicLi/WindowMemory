#!/bin/zsh
set -euo pipefail
SOURCE_DIR="${0:A:h}"
DEST_DIR="${1:-$SOURCE_DIR/build}"
APP_PATH="$DEST_DIR/窗口记忆.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macosx14.0 \
  "$SOURCE_DIR/Core.swift" "$SOURCE_DIR/Accessibility.swift" "$SOURCE_DIR/Controller.swift" "$SOURCE_DIR/main.swift" \
  -o "$APP_PATH/Contents/MacOS/WindowMemory" \
  -framework AppKit -framework SwiftUI -framework ApplicationServices -framework ServiceManagement
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.vic.windowmemory</string>
<key>CFBundleName</key><string>窗口记忆</string>
<key>CFBundleDisplayName</key><string>窗口记忆</string>
<key>CFBundleExecutable</key><string>WindowMemory</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Made locally for Vic. 2026.</string>
</dict></plist>
PLIST
if [[ -f "$SOURCE_DIR/AppIcon.icns" ]]; then
  cp "$SOURCE_DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - --identifier local.vic.windowmemory "$APP_PATH"
"$APP_PATH/Contents/MacOS/WindowMemory" --self-test
echo "Built: $APP_PATH"
