#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/build.sh"
APP="$ROOT/dist/BarFlow.app/Contents/MacOS/BarFlow"
"$APP" --diagnose > "$ROOT/.build/diagnose.json"
"$APP" --smoke-test > "$ROOT/.build/smoke.json"
python3 - "$ROOT" <<'PY'
import json,sys,pathlib,plistlib
root=pathlib.Path(sys.argv[1])
d=json.loads((root/'.build/diagnose.json').read_text())
s=json.loads((root/'.build/smoke.json').read_text())
assert d['app']=='BarFlow'
info=plistlib.loads((root/'dist/BarFlow.app/Contents/Info.plist').read_bytes())
assert d['version']==info['CFBundleShortVersionString']=='0.2.2'
assert info['CFBundleVersion']=='5'
assert info['CFBundleDisplayName']=='轻栏'
assert info['CFBundleDevelopmentRegion']=='zh-Hans'
assert info['CFBundleLocalizations']==['zh-Hans']
assert (root/'dist/BarFlow.app/Contents/Resources/zh-Hans.lproj/InfoPlist.strings').is_file()
assert (root/'dist/BarFlow.app/Contents/Resources/LICENSE').read_bytes()==(root/'LICENSE').read_bytes()
assert (root/'dist/BarFlow.app/Contents/Resources/Scroll-Reverser-LICENSE.txt').read_bytes()==(root/'vendor-notices/Scroll-Reverser-LICENSE.txt').read_bytes()
assert (root/'dist/BarFlow.app/Contents/Resources/Scroll-Reverser-NOTICE.txt').read_bytes()==(root/'vendor-notices/Scroll-Reverser-NOTICE.txt').read_bytes()
assert d['safe_defaults']['menuEnabled'] is False
assert d['safe_defaults']['scrollEnabled'] is False
assert d['safe_defaults']['sideButtonsEnabled'] is False
assert d['side_buttons']['defaultEnabled'] is False
assert s['settings_window_built'] is True
assert s['menu_collapsed'] is False
assert s['scroll_running'] is False
assert s['side_buttons_running'] is False
assert s['cleanup_complete'] is True
assert s['native_menu_enabled_expanded'] is True
assert s['preferences_unchanged'] is True
print('PASS: packaged metadata, safe launch, native window, disabled engines, graceful cleanup')
PY
codesign --verify --deep --strict "$ROOT/dist/BarFlow.app"
