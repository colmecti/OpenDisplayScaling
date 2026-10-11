# Validation record and test plan

This file separates source checks from actual monitor behavior. A successful
build, reported refresh rate, or sample screenshot is not proof of every
display, connection, or lifecycle path.

## 0.1.0 preview — 11 October 2026

### Non-display checks

| Check | Result |
| --- | --- |
| Apple silicon app build on macOS 26.3.1, minimum deployment target 13.0 | Passed |
| Configuration parser: malformed, negative, fractional, odd, excessive and non-finite input | Passed |
| Framebuffer limits, mode-ladder bounds and uniqueness across a size grid | Passed |
| Saved-profile parsing and HiDPI/LoDPI/refresh-rate restoration matching | Passed |
| Combined configuration suite | 950 assertions passed; these are not 950 hardware tests |
| Clang static analyzer | No diagnostics on the reviewed source |
| App bundle signature verification | Passed, ad-hoc signature only |
| Version and read-only JSON diagnostics commands | Passed |
| Native settings layout and accessible control labels | Visually inspected |

Run `make test` for the non-display suite. `make package` also builds and packages
the app. The ready-to-enable workflow in `docs/github-actions-ci.yml` performs these checks without applying a monitor configuration. Hosted CI is not active in this release: the publishing credential lacks GitHub’s `workflow` scope.

### Physical observations

Development hardware: Apple M5, macOS 26.3.1 (a), CRUA CR340D ultrawide and
Acer VG270 P. The CRUA began at 3440 × 1440 / 165 Hz; the Acer at 1920 × 1080 / 144 Hz.

- The configurable app was observed presenting a 2580 × 1080 logical desktop
  with a 5160 × 2160 framebuffer. macOS reported 165 Hz for the virtual and
  CRUA mirror entries. The Acer remained separate at 1920 × 1080 / 144 Hz.
- The settings window showed the confirmed active mode and enabled native
  login registration. A full logout/login was **not** performed.
- An earlier, monitor-specific prototype was verified at 2560 × 1080 HiDPI /
  165 Hz, and its quit/restore path returned the CRUA to 3440 × 1440 / 165 Hz.
  That prototype test is **not** a substitute for testing the configurable
  app's complete restoration and timeout paths.

The monitor's owner needed to continue using it, so disruptive testing stopped.
The final package was rebuilt after non-display and lifecycle fixes; a fresh
hardware regression of that final package remains pending. This is why the
release is a public **preview**, not a broad compatibility or stability claim.

### Still pending

- A full, untouched 20-second timeout on the final package.
- Keep → Restore and Quit restoration across multiple monitor arrangements.
- Cancellation during mode publication or a failing WindowServer transaction.
- Forced termination followed by recovery-journal handling.
- Cable unplug/replug, dock changes, sleep/wake, and login after reboot.
- Hardware testing on other Mac chips, macOS releases, monitors, and refresh rates.
- HDR, VRR, protected video, games, capture tools, latency, and frame pacing.

## Manual regression checklist

Use a machine and monitor available for deliberate testing. Save work first;
have another screen or a way to disconnect the external display available.

1. Record every monitor's mode, layout, and main-display status.
2. Check that an invalid input does not create a virtual display or change modes.
3. Apply a valid size. Inspect the logical dimensions, 2× pixel dimensions,
   rendering refresh rate, and mirror source using independent system tools.
4. Leave it unconfirmed; confirm it restores after the countdown. Also try an
   open menu during the countdown and Escape to revert.
5. Apply and Keep. Verify the saved profile and that no timer later reverts it.
6. Restore; compare modes and layout with the initial record, including the
   untouched second monitor. Repeat with the target as a non-main display.
7. Quit while active; confirm the virtual display disappears and the app process
   exits. Repeat with forced termination and inspect the next-launch recovery path.
8. Test disconnect/reconnect and sleep/wake. Do not count the absence of a crash
   as successful recovery; verify the actual resulting modes and layout.
9. In Applications, toggle Launch at login off and on. Check the corresponding
   system registration. Log out/in separately to verify actual startup.
10. Test saved-profile startup with the monitor present and initially absent.
    An unexpected previous exit should suppress automatic reapply for one launch.

Report the exact source commit, app version, OS, chip, monitor model, connection,
requested size, observed rendering size, and pass/fail outcome. Do not publish
display UUIDs, serial numbers, or unrelated screen contents.
