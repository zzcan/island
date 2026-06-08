#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# This machine's default toolchains don't work for this package (see
# docs/superpowers/ENVIRONMENT.md). Use Homebrew Swift; allow override via $SWIFT.
SWIFT="${SWIFT:-/opt/homebrew/opt/swift/bin/swift}"

"$SWIFT" build -c release

BINDIR="$("$SWIFT" build -c release --show-bin-path)"

APP="build/island.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BINDIR/island" "$APP/Contents/MacOS/island"
cp "$BINDIR/vibe-hook" "$APP/Contents/MacOS/vibe-hook"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>island</string>
  <key>CFBundleIdentifier</key><string>app.island.local</string>
  <key>CFBundleExecutable</key><string>island</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "vibe-hook path: $(pwd)/$APP/Contents/MacOS/vibe-hook"
