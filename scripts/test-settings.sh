#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/tests"
xcrun swiftc -swift-version 5 -warnings-as-errors "$ROOT/Sources/Core/Preferences.swift" "$ROOT/Tests/PreferencesTests.swift" -o "$ROOT/.build/tests/preferences-tests"
"$ROOT/.build/tests/preferences-tests"
xcrun swiftc -swift-version 5 -warnings-as-errors "$ROOT/Sources/Core/LoginItemState.swift" "$ROOT/Tests/LoginItemStateTests.swift" -o "$ROOT/.build/tests/login-item-tests"
"$ROOT/.build/tests/login-item-tests"
