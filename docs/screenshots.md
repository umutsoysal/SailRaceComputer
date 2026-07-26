# Retaking the screenshots

The images in [`screenshots/`](../screenshots) are captured from a real build
running on an iOS Simulator, driven by the simulated boat so no GPS fix, boat,
or Lake Michigan is required.

The harness is [`lib/dev/screenshot_main.dart`](../lib/dev/screenshot_main.dart).
It mounts the production `AppShell` with a `SimulatedPositionSource`, on the
Chicago beer-can course, with the boat approaching the start line from the south
at 6.2 knots. Nothing in `lib/dev/` ships in the release app.

## iOS Simulator (what the committed images use)

```bash
xcrun simctl boot "iPhone 15 Pro Max"
open -a Simulator
```

Give the screenshots a clean status bar:

```bash
xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3
```

Run the harness:

```bash
make screenshots
```

`SIMULATOR` overrides the target device, e.g. `make screenshots SIMULATOR="iPhone 16 Pro"`.

Drive the app to the screen you want, then write the PNG:

```bash
xcrun simctl io booted screenshot --type=png screenshots/race.png
```

The **Race** shot is taken a couple of minutes after tapping *Start race*, so
the clock is running, VMG is positive, and auto-advance has stepped to the
second mark.

Committed images are downscaled to half of the device's native resolution to
keep the repository small:

```bash
sips -Z 1398 screenshots/*.png
```

## Web (quick look, no simulator)

```bash
./tool/flutterw.sh run -t lib/dev/screenshot_main.dart -d chrome
```

On web the starting tab comes from a query parameter — `?tab=0` courses,
`1` map, `2` race, `3` recordings, `4` settings — which makes each screen
reachable from a stable URL.
