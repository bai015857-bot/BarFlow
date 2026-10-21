#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:?TMPDIR is required}/barflow-menu-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
shopt -s nullglob
SOURCES=("$ROOT/Tests/MenuCoreTests.swift" "$ROOT"/Sources/Core/Menu*.swift "$ROOT"/Sources/App/Menu*.swift)
swiftc -parse-as-library -swift-version 5 -warnings-as-errors "${SOURCES[@]}" \
  -framework AppKit -framework Carbon \
  -o "$BUILD_DIR/menu-tests"
"$BUILD_DIR/menu-tests"
