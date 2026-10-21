#!/bin/bash
# 独立外观预览，不替换正式应用、不注册系统权限或输入监听。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/preview-obsidian/轻栏曜石精密预览.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -warnings-as-errors \
  "$ROOT/Sources/Core/Preferences.swift" \
  "$ROOT/Sources/Core/LoginItemState.swift" \
  "$ROOT/Sources/App/SettingsWindowController.swift" \
  "$ROOT/Tests/SettingsPreview.swift" \
  -framework AppKit -o "$APP/Contents/MacOS/SettingsPreview"
python3 - "$APP" "$ROOT" <<'PY'
import plistlib
import sys
from pathlib import Path
app, root = map(Path, sys.argv[1:])
info = {
    "CFBundleIdentifier": "local.longkaixin.barflow.visualpreview.obsidian",
    "CFBundleExecutable": "SettingsPreview",
    "CFBundleName": "轻栏曜石精密预览",
    "CFBundleDisplayName": "轻栏曜石精密预览",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "0.1",
    "CFBundleVersion": "1",
    "CFBundleDevelopmentRegion": "zh-Hans",
    "CFBundleLocalizations": ["zh-Hans"],
    "LSMinimumSystemVersion": "13.5",
    "LSUIElement": True,
    "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication",
    "CFBundleIconFile": "AppIcon",
}
(app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
PY
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.longkaixin.barflow.visualpreview.obsidian "$APP"
codesign --verify --deep --strict "$APP"
if [ "${1:-}" = "--build-only" ]; then
  printf '已生成独立预览：%s\n' "$APP"
else
  "$APP/Contents/MacOS/SettingsPreview" "$@"
fi
