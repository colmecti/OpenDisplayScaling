#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent build/OpenDisplayScaling.app "dist/OpenDisplayScaling-${VERSION}-arm64.zip"
(cd dist && shasum -a 256 "OpenDisplayScaling-${VERSION}-arm64.zip" > SHA256SUMS.txt)
echo "Packaged dist/OpenDisplayScaling-${VERSION}-arm64.zip"
