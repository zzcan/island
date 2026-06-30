#!/usr/bin/env bash
# Rebuild island.app and restart it under launchd.
#
# Use this instead of `pkill` once the LaunchAgent (KeepAlive) is installed:
# a plain kill just gets relaunched on the OLD binary. `kickstart -k` kills the
# running job and restarts it on the freshly-built binary.
#
# If the LaunchAgent isn't loaded yet, falls back to a plain `open`.
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="app.island.local"
DOMAIN="gui/$(id -u)"

./Scripts/bundle.sh

if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  echo "Restarting via launchd ($DOMAIN/$LABEL)…"
  launchctl kickstart -k "$DOMAIN/$LABEL"
else
  echo "LaunchAgent not loaded; launching with open…"
  pkill -f "island.app/Contents/MacOS/island" || true
  sleep 1
  open build/island.app
fi

sleep 1
echo "Running version: $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/island.app/Contents/Info.plist)"
ps aux | grep "island.app/Contents/MacOS/island" | grep -v grep || echo "(not running yet)"
