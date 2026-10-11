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
    -framework ColorSync -framework ServiceManagement -framework ScreenCaptureKit -framework CoreMedia -framework CoreImage -framework UniformTypeIdentifiers -framework Carbon \
    Sources/App.m Sources/DisplayController.m Sources/ScalingConfiguration.m Sources/DisplayManager.m Sources/DisplayPreview.m Sources/StudioWindow.m Sources/HardwareControls.m Sources/HotKeys.m \
    -o "$APP/Contents/MacOS/OpenDisplayScaling"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -O2 -fmodules -Wall -Wextra \
    -I Vendor/m1ddc/headers Vendor/m1ddc/sources/*.m \
    -F /System/Library/PrivateFrameworks -framework CoreDisplay \
    -o "$APP/Contents/Resources/m1ddc"
codesign --force --sign "${ODS_SIGNING_IDENTITY:--}" "$APP/Contents/Resources/m1ddc"
xcrun swift scripts/draw-icon.swift "$PWD/build"
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature only; this is NOT Developer ID signing or notarization.
codesign --force --sign "${ODS_SIGNING_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (Apple silicon, macOS 13+)"
