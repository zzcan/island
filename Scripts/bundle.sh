#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# This machine's default toolchains don't work for this package (see
# docs/superpowers/ENVIRONMENT.md). Use Homebrew Swift; allow override via $SWIFT.
SWIFT="${SWIFT:-/opt/homebrew/opt/swift/bin/swift}"

# Version comes from git: release builds (checked out at a vX.Y.Z tag) get a
# clean "X.Y.Z"; dev builds get "X.Y.Z-N-gHASH[-dirty]". No tags yet -> 0.0.0.
VERSION="$(git describe --tags --match 'v*' --dirty 2>/dev/null | sed 's/^v//' || true)"
VERSION="${VERSION:-0.0.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

"$SWIFT" build -c release

BINDIR="$("$SWIFT" build -c release --show-bin-path)"

APP="build/island.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BINDIR/island" "$APP/Contents/MacOS/island"
cp "$BINDIR/vibe-hook" "$APP/Contents/MacOS/vibe-hook"

mkdir -p "$APP/Contents/Resources"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>island</string>
  <key>CFBundleIdentifier</key><string>app.island.local</string>
  <key>CFBundleExecutable</key><string>island</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>island controls terminal apps (iTerm2, Terminal) to jump to the right window and tab when you click a session.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "vibe-hook path: $(pwd)/$APP/Contents/MacOS/vibe-hook"
