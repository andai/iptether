#!/bin/bash
#
# build-app.sh — build IPTether.app (universal: Apple silicon + Intel) into build/.
#
#   scripts/build-app.sh
#
# Environment:
#   VERSION         app version (default 0.1.0)
#   BUNDLE_ID       bundle identifier (default app.iptether.IPTether; placeholder until the
#                   org domain is settled)
#   SIGN_IDENTITY   codesign identity; "-" (default) signs ad hoc. A Developer ID
#                   identity is needed for notarization.
#   SDKROOT         macOS SDK to build against. Defaults to the 26 SDK when it exists:
#                   the macOS 27 SDK's SwiftUI needs macro plugins that ship only with
#                   full Xcode, not the Command Line Tools.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-app.iptether.IPTether}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ -z "${SDKROOT:-}" ]; then
  for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk \
             "$(xcrun --sdk macosx26 --show-sdk-path 2>/dev/null || true)"; do
    # use the real versioned path (MacOSX26.5.sdk), so the log names the exact SDK
    [ -n "$sdk" ] && [ -d "$sdk" ] && { SDKROOT="$(cd "$sdk" && pwd -P)"; export SDKROOT; break; }
  done
fi

cd "$ROOT"
echo "==> building (SDK: ${SDKROOT:-default})"
swift build -c release --arch arm64 --arch x86_64 --product IPTether
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="$ROOT/build/IPTether.app"
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/IPTether" "$APP/Contents/MacOS/IPTether"
cp "$ROOT/engine/iptether-sync.sh" "$APP/Contents/Resources/iptether-sync.sh"
chmod 755 "$APP/Contents/Resources/iptether-sync.sh"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>IPTether</string>
  <key>CFBundleDisplayName</key><string>IPTether</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>IPTether</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 And AI Platforms. Licensed under the Apache License 2.0.</string>
</dict>
</plist>
EOF

echo "==> signing (${SIGN_IDENTITY})"
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "==> done"
file "$APP/Contents/MacOS/IPTether"
