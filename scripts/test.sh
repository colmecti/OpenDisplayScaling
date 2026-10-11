#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -I Sources \
    Tests/ConfigurationTests.m Sources/ScalingConfiguration.m -o build/configuration-tests
./build/configuration-tests
plutil -lint Resources/Info.plist
