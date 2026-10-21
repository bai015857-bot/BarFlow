#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_root="${TMPDIR:-$PWD/.build/test-tmp}"
mkdir -p "$build_root"
build_dir="$(mktemp -d "${build_root%/}/barflow-scroll-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
shopt -s nullglob
sources=(Sources/Core/Scroll*.swift Sources/App/Scroll*.swift)
swiftc -swift-version 5 -warnings-as-errors "${sources[@]}" Tests/ScrollCoreTests.swift \
  -framework AppKit -framework ApplicationServices -o "$build_dir/ScrollCoreTests"
"$build_dir/ScrollCoreTests"
