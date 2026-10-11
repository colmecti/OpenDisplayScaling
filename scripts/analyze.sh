#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/analysis
for source_file in Sources/*.m; do
    xcrun clang --analyze -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc \
        -Wno-unused-parameter -I Sources "$source_file" \
        -o "build/analysis/$(basename "$source_file" .m).plist"
done
python3 - <<'PY'
from pathlib import Path
import plistlib
count = sum(len(plistlib.loads(p.read_bytes()).get('diagnostics', []))
            for p in Path('build/analysis').glob('*.plist'))
if count:
    raise SystemExit(f'Clang static analysis reported {count} diagnostics.')
print('Clang static analysis: no diagnostics.')
PY
