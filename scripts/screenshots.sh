#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Furcenzo
#
# Regenerates the README screenshots in docs/screenshots/ from the sample Brewfile there.
# The app runs as a copy with its own bundle ID, so your settings (last Brewfile, window size…) stay untouched.
# Statuses (installed / missing) come from this Mac's Homebrew. Each shot briefly brings the app to the front.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh >/dev/null
WORK="$(mktemp -d)"
SHOT_ID="io.github.furcenzo.brewgui.screenshots"
trap 'rm -rf "$WORK"; defaults delete "$SHOT_ID" >/dev/null 2>&1; rm -f ~/Library/Preferences/"$SHOT_ID".plist' EXIT

APP="$WORK/Brew GUI.app"
cp -R "build/Brew GUI.app" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $SHOT_ID" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1

OUT="docs/screenshots"
SAMPLE="$PWD/$OUT/Brewfile"

# shot <file> <appearance> <language> [ENV=value…]
shot() {
    local file="$1" appearance="$2" language="$3"
    shift 3
    env BREWGUI_SNAPSHOT="$WORK/$file" BREWGUI_FILE="$SAMPLE" BREWGUI_APPEARANCE="$appearance" \
        BREWGUI_WINDOW_SIZE=1280x800 BREWGUI_DISPLAY_PATH="~/Brewfile" BREWGUI_DELAY=8 "$@" \
        "$APP/Contents/MacOS/BrewGUI" -AppleLanguages "($language)" -autoUpdateEnabled NO >/dev/null 2>&1
    # 2× pixels are more than the README needs; keep the files small.
    sips --resampleWidth 1920 "$WORK/$file" --out "$OUT/$file" >/dev/null
    echo "$OUT/$file"
}

shot brewfile-light.png light en BREWGUI_SELECT=ripgrep
shot brewfile-dark.png dark en BREWGUI_SELECT=ripgrep
shot sync-dark.png dark en BREWGUI_PAGE=sync
shot search-light.png light en BREWGUI_SEARCH=iina
shot brewfile-sk-light.png light sk BREWGUI_SELECT=neovim
