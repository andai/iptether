#!/bin/bash
#
# test.sh — run every test: the Swift tests, then the offline engine suite.
#
#   scripts/test.sh
#
# With full Xcode this is plain `swift test`. With only the Command Line Tools, two
# workarounds are needed: build against the macOS 26 SDK (the 27 SDK's SwiftUI needs
# macro plugins only Xcode has), and point the compiler at Swift Testing's macro plugin,
# which SwiftPM doesn't find when SDKROOT is set.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXTRA=()
if [[ "$(xcode-select -p 2>/dev/null)" == /Library/Developer/CommandLineTools* ]]; then
  CLT=/Library/Developer/CommandLineTools
  if [ -z "${SDKROOT:-}" ] && [ -d "$CLT/SDKs/MacOSX26.sdk" ]; then
    SDKROOT="$(cd "$CLT/SDKs/MacOSX26.sdk" && pwd -P)"
    export SDKROOT
  fi
  PLUGINS="$CLT/usr/lib/swift/host/plugins/testing"
  [ -d "$PLUGINS" ] && EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi

echo "==> swift test (SDK: ${SDKROOT:-default})"
swift test ${EXTRA[@]+"${EXTRA[@]}"}

echo "==> engine tests"
/bin/bash engine/tests/run-tests.sh
