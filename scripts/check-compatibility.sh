#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -parse-as-library \
  placard/SystemCompatibility.swift placard/Airlift/PairingRecord.swift \
  tests/CompatibilityChecks.swift -o "$test_dir/compatibility-checks"
"$test_dir/compatibility-checks"
