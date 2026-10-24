#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
VERSION="$(<"$ROOT/VERSION")"
APP="$ROOT/build/窗口记忆.app"
DIST="$ROOT/dist"
[[ -d "$APP" ]] || { echo 'Run zsh build.sh first.' >&2; exit 1; }
ACTUAL=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$ACTUAL" == "$VERSION" ]] || { echo 'App version does not match VERSION.' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
xcrun lipo "$APP/Contents/MacOS/WindowMemory" -verify_arch arm64
xcrun lipo "$APP/Contents/MacOS/WindowMemory" -verify_arch x86_64
mkdir -p "$DIST" "$ROOT/build/dmg-stage"
NAME="WindowMemory-v$VERSION-universal"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"
ditto "$APP" "$ROOT/build/dmg-stage/窗口记忆.app"
ln -sfn /Applications "$ROOT/build/dmg-stage/Applications"
hdiutil create -volname "WindowMemory $VERSION" -srcfolder "$ROOT/build/dmg-stage" -ov -format UDZO "$DIST/$NAME.dmg"
python3 - "$DIST" "$NAME" <<'PY'
import hashlib,pathlib,sys
root=pathlib.Path(sys.argv[1]);name=sys.argv[2]
lines=[]
for ext in ['zip','dmg']:
 p=root/(name+'.'+ext)
 lines.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name)
(root/'SHA256SUMS.txt').write_text('\n'.join(lines)+'\n')
PY
echo "Packaged $VERSION in $DIST"
