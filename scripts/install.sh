#!/usr/bin/env bash
# Installs UsageBar.app to /Applications and registers a LaunchAgent so it starts at login.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="io.github.pwntastickev.usagebar"
DEST="/Applications/UsageBar.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

"$ROOT/scripts/build.sh"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x UsageBar 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents"
rm -rf "$DEST"
cp -R "$ROOT/build/UsageBar.app" "$DEST"

cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>${DEST}/Contents/MacOS/UsageBar</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "Installed $DEST and started at login via $AGENT"
