#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/tests"
xcrun swiftc -swift-version 5 -warnings-as-errors "$ROOT/Sources/Core/Preferences.swift" "$ROOT/Sources/Core/LoginItemState.swift" "$ROOT/Sources/App/SettingsWindowController.swift" "$ROOT/Tests/SettingsUITests.swift" -framework AppKit -o "$ROOT/.build/tests/settings-ui-tests"
"$ROOT/.build/tests/settings-ui-tests"
