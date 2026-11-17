#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Furcenzo
#
# Builds the release version and packages it as build/Brew GUI.app (ad-hoc signed).
#   VERSION=1.2.3  version written to Info.plist (default 0.1.0)
#   UNIVERSAL=1    build for both Apple silicon and Intel (used for public releases)
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/BrewGUI"

APP="build/Brew GUI.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f "$BIN" "$APP/Contents/MacOS/BrewGUI"

# Translations (English is the development language, see CLAUDE.md)
LOCALIZATIONS=()
for lproj in Sources/BrewGUI/Resources/*.lproj; do
    cp -R "$lproj" "$APP/Contents/Resources/"
    LOCALIZATIONS+=("<string>$(basename "$lproj" .lproj)</string>")
done

VERSION="${VERSION:-0.1.0}"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Brew GUI</string>
    <key>CFBundleDisplayName</key><string>Brew GUI</string>
    <key>CFBundleIdentifier</key><string>io.github.furcenzo.brewgui</string>
    <key>CFBundleExecutable</key><string>BrewGUI</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array>${(j::)LOCALIZATIONS}</array>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>Copyright (C) 2026 Furcenzo. GPL-3.0-or-later.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint -s "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Done: $PWD/$APP"
