#!/usr/bin/env bash
# Stops UsageBar and removes the app and its LaunchAgent.
set -euo pipefail

LABEL="io.github.pwntastickev.usagebar"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x UsageBar 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "/Applications/UsageBar.app" "$HOME/Applications/UsageBar.app"
defaults delete "$LABEL" 2>/dev/null || true
echo "UsageBar removed."
