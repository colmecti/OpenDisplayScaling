# Troubleshooting

## Text is still small

Choose a smaller **looks-like** width and height. These are desktop dimensions,
not the physical panel's pixels. Keep proportions on, and start with a preset.

## A mode is rejected or returns to the original setup

Try a smaller desktop or 60 Hz. GPU, connection, and macOS limits vary. The app
must observe the exact requested logical dimensions and a 2× framebuffer before
it accepts a mode; it does not silently substitute LoDPI.

## Blank screen or unreadable desktop

For a new manual change, leave it unconfirmed: the app requests the previous setup
after 20 seconds once confirmation starts. If the app or WindowServer is stuck,
that timer may not execute on time.

Use another display if available. Quit OpenDisplayScaling from its menu or from
Activity Monitor; the temporary virtual display belongs to the app and disappears
when the process exits. A normal quit also requests the recorded original mode.
If needed, disconnect and reconnect the monitor and select its default mode in
System Settings → Displays. On the next launch after an unexpected exit, the
app attempts recovery and suppresses automatic reapplication for that launch.

## The app says the monitor is already mirrored

Stop the other display-scaling app or disable existing mirroring first. This app
does not take over another program's mirror group. It scales one monitor at a time.

## Login checkbox does not stay checked

Move the app to `/Applications` or your user's `Applications` directory and reopen
it. Use the checkbox there. If approval is pending, use the in-app button to open
System Settings → General → Login Items & Extensions. The app must be code signed;
the build script supplies an ad-hoc signature. Managed Macs may restrict login items.
After replacing an ad-hoc-signed build with a newer one, recheck registration and
toggle the option off and on if needed.

Launch at login opens the app. **Apply saved size when the app opens** separately
controls whether it reapplies the last size you confirmed.

## After reconnecting or waking

The preview does not promise seamless sleep/wake or cable-switch recovery. If the
monitor disconnects, scaling stops. Refresh the display list and apply again.
If the app was closed, reopen it. Automatic reapply waits for the saved monitor
but attempts it only once per app launch.

## Uninstall

1. Uncheck **Launch at login** while the app is installed.
2. Choose **Restore original**, then **Quit OpenDisplayScaling**.
3. Move the app to the Trash.

The small preference record can remain harmlessly. To remove it as well, after
quitting the app run `defaults delete io.github.colmecti.OpenDisplayScaling`.
Do not delete preferences before restoring an active setup: they contain recovery
information. If the app was already removed, manage its startup entry in Login Items.
