#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Furcenzo
#
# Renders scripts/icon/AppIcon.swift and builds Sources/BrewGUI/Resources/AppIcon.icns
# (copied into the app by scripts/build-app.sh). Run it after changing the icon drawing.
set -euo pipefail
cd "$(dirname "$0")/../.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swift scripts/icon/AppIcon.swift "$WORK/icon.png"

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns --output Sources/BrewGUI/Resources/AppIcon.icns "$SET"
cp "$WORK/icon.png" scripts/icon/AppIcon.png
echo "Done: Sources/BrewGUI/Resources/AppIcon.icns"
