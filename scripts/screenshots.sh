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
cp -R "build/Brew GUI Dev.app" "$APP"
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
    # 2× pixels are more than the README needs; keep the files small (narrow images stay as they are).
    if (( $(sips -g pixelWidth "$WORK/$file" | awk '/pixelWidth/ { print $2 }') > 1920 )); then
        sips --resampleWidth 1920 "$WORK/$file" --out "$OUT/$file" >/dev/null
    else
        cp "$WORK/$file" "$OUT/$file"
    fi
    echo "$OUT/$file"
}

shot brewfile-light.png light en BREWGUI_SELECT=ripgrep
shot brewfile-dark.png dark en BREWGUI_SELECT=ripgrep
shot sync-dark.png dark en BREWGUI_PAGE=sync
shot search-light.png light en BREWGUI_SEARCH=iina
shot brewfile-sk-light.png light sk BREWGUI_SELECT=neovim
shot stashed-light.png light en BREWGUI_PAGE=stashed

# Unused Apps: sample apps instead of this Mac's Applications (name:last opened:added days ago:source).
SAMPLE_UNUSED="Firefox:210:400:cask=firefox,IINA:160:300:cask=iina,Keynote:130:500:mas=409183694,DockDoor:-:240:cask=dockdoor,Old Tool:300:700:other,Rectangle:95:380:cask=rectangle"
shot unused-dark.png dark en BREWGUI_PAGE=unused BREWGUI_SAMPLE_UNUSED="$SAMPLE_UNUSED"

# Menu bar panel: sample updates and only the apps from the sample Brewfile.
SAMPLE_OUTDATED="brew:gh:2.103.0:2.104.0,brew:neovim:0.12.5:0.12.6,cask:visual-studio-code:1.145.0:1.146.0"
shot menubar-light.png light en BREWGUI_PAGE=menubar BREWGUI_APPS_FROM_BREWFILE=1 BREWGUI_SAMPLE_OUTDATED="$SAMPLE_OUTDATED"
shot menubar-search-dark.png dark en BREWGUI_PAGE=menubar BREWGUI_APPS_FROM_BREWFILE=1 BREWGUI_MENUBAR_QUERY=code
