---
name: run-app
description: 'How to run the Race Mate app. Use when asked to run, launch, start, or restart the app — either on a real device/emulator or in the desktop simulator. Covers flutter run, hot reload, hot restart, and the dev simulator entry point.'
argument-hint: 'device or simulator'
---

# Running Race Mate

## On a Device or Emulator (Production App)

```sh
flutter run
```

Flutter auto-selects the only connected device. To target a specific one:

```sh
flutter devices                                    # list available targets
flutter run -d <device-id>                         # e.g. -d iPhone -d chrome -d macos
```

Entry point: `lib/main.dart` (GPS-enabled, no simulator UI).

## Dev Simulator (Desktop, No GPS Required)

```sh
flutter run -t lib/dev/sim_main.dart -d chrome     # browser (recommended)
flutter run -t lib/dev/sim_main.dart -d macos      # native macOS window
```

The simulator opens a top-down map with a controllable boat. It drives the
same `RaceScreen` widget as the production app via `SimulatedPositionSource`,
so all metrics (VMG, distance, bearing, ETA) behave identically.

Interactive controls:
- **Drag** the boat to teleport it
- **Long-press** the map to add a mark at that position
- **Heading / Speed sliders** in the controls panel

## Picking Up Asset Changes

| Change | What to do |
|---|---|
| Edited an existing course JSON | `R` (hot restart) in the terminal |
| Added a new `.json` to `assets/courses/` | Full stop + `flutter run` (asset manifest rebuilds) |

Assets directory is declared as `assets/courses/` in `pubspec.yaml`, so new
files are picked up automatically on the next full run — no `pubspec.yaml`
edit required.

## Hot Reload vs Hot Restart

| Key | What changes | State |
|---|---|---|
| `r` | Dart code only | Preserved |
| `R` | Dart code + reinit | Reset |
| `q` | Quit | — |

Hot reload is enough for UI tweaks. Hot restart is needed when `initState`
logic or service initialization must re-run (e.g. CourseStore, PositionSource).
