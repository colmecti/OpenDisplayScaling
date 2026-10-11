#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -I Sources \
    Tests/ConfigurationTests.m Sources/ScalingConfiguration.m -o build/configuration-tests
./build/configuration-tests
plutil -lint Resources/Info.plist
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -framework Cocoa -framework CoreGraphics -framework ColorSync -I Sources \
    Tests/DisplayManagerTests.m Sources/DisplayManager.m Sources/ScalingConfiguration.m \
    -o build/display-manager-tests
./build/display-manager-tests
xcrun clang -fmodules -Wall -Wextra -Werror -Wno-unused-parameter \
    -I Vendor/m1ddc/headers Tests/DDCTests.m Vendor/m1ddc/sources/i2c.m \
    -o build/ddc-tests
./build/ddc-tests
