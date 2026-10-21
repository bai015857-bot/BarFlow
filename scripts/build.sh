#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/BarFlow.app"
mkdir -p "$ROOT/.build" "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -warnings-as-errors -O -target arm64-apple-macosx13.5 \
  "$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/App/*.swift \
  -framework AppKit -framework ApplicationServices -framework Carbon -framework ServiceManagement \
  -o "$APP/Contents/MacOS/BarFlow"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/zh-Hans.lproj"
cp "$ROOT/Resources/zh-Hans.lproj/InfoPlist.strings" "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$ROOT/vendor-notices/Scroll-Reverser-LICENSE.txt" "$APP/Contents/Resources/Scroll-Reverser-LICENSE.txt"
cp "$ROOT/vendor-notices/Scroll-Reverser-NOTICE.txt" "$APP/Contents/Resources/Scroll-Reverser-NOTICE.txt"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - --identifier local.longkaixin.barflow "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built and verified: %s\n' "$APP"
