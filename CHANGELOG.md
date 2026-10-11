# Changelog

## 0.2.0 — Development preview

- Native display-manager sidebar, per-display menu controls, saved layout groups,
  offline display names and configurable menu sections.
- Native modes, mirroring, relative positioning and main display with app-scoped
  transactions and 20-second rollback; separate standalone virtual screens.
- Local ScreenCaptureKit picture-in-picture with explicit permission flow.
- Native Apple brightness, DDC controls through pinned MIT m1ddc source, validated
  ICC profile selection, software dimming/warmth and optional brightness following.
- Saved hardware controls and optional global shortcuts.
- Mocked layout/rollback and DDC packet tests; fixes to vendored DDC decoding.
- GitHub Actions enabled. Published v0.1 download remains unchanged.
- See `docs/FEATURES.md` for missing advanced features and pending hardware/UI checks.

## 0.1.0 — 2026-10-11

First public preview.

- Native menu-bar app with external-display selection and custom HiDPI desktop sizes.
- Aspect-ratio assistance, size presets, and rendering refresh-rate selection.
- Validation of logical size, pixel dimensions, and active virtual rendering mode.
- Twenty-second confirmation window for new manual configurations.
- Restore controls, temporary virtual-display cleanup, and a local recovery record.
- Opt-in Launch at login and separate saved-size reapplication using macOS APIs.
- Read-only command-line diagnostics, source build scripts, configuration tests,
  original icon and branding, and MIT licensing with upstream attribution.

Hardware evidence is limited to Apple M5 / macOS 26.3.1 / CRUA CR340D, with an
Acer VG270 P remaining separate. See `docs/TESTING.md` for the validation boundary.
