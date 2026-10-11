# Architecture

## Components

- `ScalingConfiguration`: parses and bounds user dimensions, builds the 2× backing
  mode ladder, serializes saved configurations, and matches original display modes.
- `DisplayController`: discovers displays, records mode/layout snapshots, creates
  a virtual display, applies mirroring, verifies the mode, and restores the setup.
- `App`: AppKit settings window, menu-bar controls, confirmation presentation,
  user preferences, and native login registration.
- `VirtualDisplayAPI.h`: declarations for private platform classes, instantiated
  dynamically. A missing class results in an error before changing displays.

## State transitions

```text
Idle → Applying → Confirming → Active
          ↓           ↓          ↓
          └──────── Restoring ←───┘ → Idle
```

A manually applied mode enters Confirming after its logical size, 2× pixel size,
render refresh rate, and mirror relationship have been verified. Keep records the
profile and moves to Active. Timeout, Restore, Quit, setup failure, or a broken
mirror relationship remove the temporary display and request the prior state.

An explicitly enabled, previously confirmed startup profile can go from Applying
directly to Active. Only one attempt is made per launch once the matching display
appears. A recovery record from an unexpected exit suppresses this automatic path.

Asynchronous mode-publication polls carry a generation number so callbacks from
a cancelled operation cannot reapply an old setup. Timers use the common run-loop
modes so the confirmation countdown also runs while a menu is open. Display IPC
is still synchronous and can delay UI response if WindowServer stalls.

## Display identity and restoration

macOS UUIDs identify physical displays within this installation; transient numeric
display IDs are resolved again for operations. The recovery record stores the
selected UUID, original mode properties, and layout origins. It is local only.

The restore routine changes only the selected display's mode. It restores origins
only if the original set of displays is present. When a mode no longer exists,
it reports a best-effort stop rather than inventing a replacement mode. A virtual
display is temporary; quitting its owning process removes it.

## Why a rich mode list?

A single virtual mode may be exposed only as low resolution. The app supplies
an ordered ladder of backing modes and puts the exact preferred mode first.
This follows the findings documented by `hidpi-mirror`; its license and source
revision are preserved in the notices. A mode is never called HiDPI merely
because the virtual display was created successfully.

## Startup and privacy

`SMAppService.mainAppService` manages login registration. The UI reads system
status, including pending approval. There is no custom launch daemon or helper.

The app stores a last-confirmed profile, an automatic-reapply preference, and a
temporary recovery journal in its user preferences. It sends none of this data
over the network. Source/support links open the user's browser only when selected.

## Distribution

The build targets Apple silicon and macOS 13+. The included CI template can compile and exercise pure
configuration logic without manipulating a display. Native display tests remain
manual. The preview uses ad-hoc code signing; it is not Developer ID signed or
notarized. No signing key is included in source or release assets.
