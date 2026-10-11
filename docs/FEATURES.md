# Display-manager feature coverage

The 0.2 source preview expands OpenDisplayScaling from a single scaling window
into a native display manager. It is independently implemented and is not a
complete reproduction of BetterDisplay. No functionality is behind a paid tier.

| Reference feature | OpenDisplayScaling 0.2 implementation |
| --- | --- |
| Displays overview and per-display settings | Native sidebar, actual connected display inventory and detail pages |
| Offline displays | Optional list of previously connected display names; offline editing is not supported |
| Groups | Named native mode, refresh, origin and mirror snapshots; exact display identities required |
| Application | Login registration and separate saved-HiDPI reapply preference |
| Menu | Per-display menus, software-dimming sliders, mode selection and display shortcuts |
| Keyboard | App shortcuts plus optional Control–Option D/Up/Down/R global shortcuts |
| Pro | No paid tier; Features page states implementation limits |
| About | Version, license, source and release links |
| Virtual screens | Up to three temporary 2× 60 Hz screens; create/remove; no automatic recreation |
| Display connect/disconnect | **Not implemented**; the app does not blank or disable physical displays |
| Custom controls | Named DDC/native brightness, contrast, RGB gain and volume values; no arbitrary CLI/network actions |
| Brightness | Native Apple brightness or DDC brightness after explicit range read; separate software dimming |
| Nits | **Not measured or reported** |
| Resolution / display mode / refresh rate | Modes reported by CoreGraphics, plus the existing custom external HiDPI engine |
| Color mode / HDR | macOS Displays shortcut; **no direct HDR control** |
| Mirror display | Select a source or return to extended desktop, with timed revert |
| Stream / picture in picture | One local floating ScreenCaptureKit preview, 15 fps target, no audio or network |
| Move display | Left/right/above/below another extended display; primary display is protected |
| Rotation | macOS Displays shortcut; **no direct rotation control** |
| Image adjustments | Software dimming and warm-tint overlays; DDC RGB gains when supported |
| Color profile | Choose a validated ICC profile or restore the display's factory profile |
| Apple display preset | macOS Displays shortcut; **no direct preset control** |
| Configuration protection | Mandatory 20-second revert for native layout changes; blocks conflicts with the HiDPI controller. No continuous enforcement against other apps |
| Manage display | Inventory, native mode metadata, arrangement and main-display selection |
| High resolution (HiDPI) | Native HiDPI modes and existing external virtual-display scaling |
| Display notch | **No dedicated notch toggle** |
| Main display | Translate all display origins around the selected extended display |
| Brightness upscaling / XDR | **Not implemented** |
| Auto brightness | Optional software dimming following the built-in screen's brightness. No external ambient-light sensor or DDC brightness synchronization |
| Check for updates | Opens GitHub Releases; no silent download/install |

## Change lifetime

- Native mode, mirror and origin changes use `kCGConfigureForAppOnly` and remain
  for the process lifetime. macOS restores the login-session configuration on
  exit. **Restore layout** explicitly requests the saved pre-change layout.
- New native changes have Keep/Revert controls and a 20-second timer. Sleep and
  orderly exit cancel a pending trial. Hardware failures can still prevent exact
  restoration; check Displays settings when an error is reported.
- Custom virtual HiDPI retains its existing session/recovery implementation.
  Restore it before changing the native layout, and restore native changes before
  applying custom HiDPI. A mirror owned by another ODS process is not taken over.
- Standalone virtual screens disappear on exit. They use private macOS APIs.
- Hardware brightness, contrast, RGB gains, volume and ICC profiles are ordinary
  persistent device/user preferences. They are **not** part of the layout revert
  timer, and quitting does not undo them.
- Image overlays disappear on exit. Auto dimming is opt-in, remembers target
  display identities, and recreates only those overlays. Reset image adjustments
  or Control–Option–R disables auto dimming and clears overlays.

## Verification boundary

The control paths compile, the original configuration suite passes, and the new
transaction and DDC tests use deterministic fixtures with every display/I2C write
replaced by a stub. These do not establish physical hardware compatibility.
The overview was inspected in a read-only native app. Final expanded-page visual
checks were blocked when the development Mac locked. Hardware changes, capture
permission/streaming, global shortcut registration, and new startup settings need
manual validation. Existing v0.1 hardware observations do not validate v0.2.
