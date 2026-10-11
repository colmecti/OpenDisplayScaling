# Third-party notices

OpenDisplayScaling is licensed under MIT. Original artwork, documentation, and
application code are covered by the root `LICENSE`.

## hidpi-mirror

- Author: Petr Baudis
- Source: https://github.com/pasky/hidpi-mirror
- Reference revision: `13acfaa0ec4b13bfce84554beebc8a09813cc2ae`
- License: MIT; complete text in [`licenses/hidpi-mirror-MIT.txt`](licenses/hidpi-mirror-MIT.txt).

`Sources/VirtualDisplayAPI.h` adapts its private API declarations. The display
implementation was informed by its preferred-mode ordering, rich mode-list,
and virtual-display mirroring approach. The copyright and permission notice
are distributed with the source and inside every packaged application.

## m1ddc

- Author: waydabber
- Source: https://github.com/waydabber/m1ddc
- Revision: `04d949794102eb8df01ad3681afff6464a3eede2`
- License: MIT; complete text in [`licenses/m1ddc-MIT.txt`](licenses/m1ddc-MIT.txt).

`Vendor/m1ddc` contains the command-line helper source. It is compiled and bundled
as an unprivileged executable. Local fixes validate DDC replies, decode two-byte
values without an oversized buffer read, preserve trailing zero checksums in
outgoing packet lengths, and reject mismatched feature replies. See
`Vendor/m1ddc/UPSTREAM.md`. The license is included in the application Resources.

API references for native brightness were checked against MonitorControl's public
bridging declarations. No MonitorControl implementation code is redistributed.

## Platform frameworks

The app links to macOS-provided Cocoa, CoreGraphics, ColorSync and
ServiceManagement, ScreenCaptureKit, CoreMedia, CoreImage, UniformTypeIdentifiers,
Carbon, IOKit and CoreDisplay frameworks. DisplayServices is loaded dynamically
for native Apple brightness. They are provided by Apple and are not
redistributed by this project. Private API compatibility is not guaranteed by
Apple. This project is not affiliated with Apple, BetterDisplay, or a monitor
manufacturer.

The m1ddc executable is the only bundled third-party helper. There are no bundled
third-party fonts or downloaded icons. Original artwork remains MIT licensed.
