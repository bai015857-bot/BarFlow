#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/tests"
xcrun swiftc -swift-version 5 -warnings-as-errors "$ROOT/Sources/Core/Preferences.swift" "$ROOT/Sources/Core/LaunchPolicy.swift" "$ROOT/Tests/LaunchPolicyTests.swift" -o "$ROOT/.build/tests/launch-tests"
"$ROOT/.build/tests/launch-tests"
