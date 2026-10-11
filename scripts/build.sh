#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenDisplayScaling.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE ThirdPartyNotices.md "$APP/Contents/Resources/"
cp -R licenses "$APP/Contents/Resources/"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -O2 -fobjc-arc -Wall -Wextra \
    -Wno-unused-parameter -framework Cocoa -framework CoreGraphics \
    -framework ColorSync -framework ServiceManagement \
    Sources/App.m Sources/DisplayController.m Sources/ScalingConfiguration.m \
    -o "$APP/Contents/MacOS/OpenDisplayScaling"
xcrun swift scripts/draw-icon.swift "$PWD/build"
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature only; this is NOT Developer ID signing or notarization.
codesign --force --sign "${ODS_SIGNING_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (Apple silicon, macOS 13+)"
