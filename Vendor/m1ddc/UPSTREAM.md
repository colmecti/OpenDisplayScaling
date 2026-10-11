# Upstream

Source: https://github.com/waydabber/m1ddc
Commit: 04d949794102eb8df01ad3681afff6464a3eede2
License: MIT, Copyright (c) 2021 waydabber.

Source and headers with local fixes in `i2c.m` and `m1ddc.m`: fixed packet lengths (including zero checksums), bounded two-byte VCP decoding, and reply status/range/feature validation. These changes are covered by the root MIT license; upstream notices are retained. Built as an app-bundled, unprivileged command-line
helper. OpenDisplayScaling always selects a monitor by UUID and only exposes
luminance, contrast, color gain and volume. No default-display fallback is used.
