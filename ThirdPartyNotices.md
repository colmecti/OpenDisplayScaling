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

## Platform frameworks

The app links to macOS-provided Cocoa, CoreGraphics, ColorSync and
ServiceManagement frameworks. They are provided by Apple and are not
redistributed by this project. Private API compatibility is not guaranteed by
Apple. This project is not affiliated with Apple, BetterDisplay, or a monitor
manufacturer.

There are no bundled third-party runtime libraries, fonts, or downloaded icons.
