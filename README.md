# Race Mate — Sailing Race Computer

A GPS-powered sailing race companion app for iOS, Android, and Web. Race Mate tracks your boat's position against a pre-defined race course and displays the real-time navigation metrics you need during a regatta.

---

## Features

### Live Race Navigation
- **Distance to next mark** — great-circle distance in nautical miles
- **Bearing to next mark** — true bearing in degrees with compass abbreviation
- **VMG (Velocity Made Good)** — speed component directly toward the mark; highlighted green when positive (closing), red when negative (opening)
- **SOG / COG** — Speed and Course Over Ground from GPS
- **ETA** — estimated time of arrival at current speed
- **Auto-advance** — automatically steps to the next mark when the boat enters the rounding radius
- **GPS status** — live fix indicator with accuracy display and error recovery

### Course Management
- Build a course from scratch by adding buoys (name, lat/lng, rounding radius)
- Drag to reorder marks
- Edit or delete individual buoys
- Rename the course
- Persist the active course across app restarts

### Course Library
- Browse bundled courses (Chicago demo, South-Side Circle S3)
- Save any course to a personal library stored on-device
- Import courses from a JSON file (file picker)
- Import by pasting JSON from the clipboard
- Export / share courses as `.srcourse.json` files via the native share sheet (Mail, Messages, AirDrop, etc.)
- View raw JSON in-app for debugging or manual sharing

### Apple Watch / Wear OS Companion
- Sends live race metrics to a paired watch via a native `MethodChannel`

---

## Screenshots

> _(Add screenshots here)_

---

## Getting Started

### Prerequisites

| Tool | Minimum version |
|------|----------------|
| Flutter | 3.x (stable) |
| Dart SDK | 3.11.0 |
| Xcode | 15+ (iOS builds) |
| Android Studio | Flamingo+ (Android builds) |

### Install dependencies

```bash
flutter pub get
```

### Run on a device or simulator

```bash
# Default (production entry point — real GPS)
flutter run

# Target a specific device
flutter run -d iphone   # iOS Simulator
flutter run -d android  # Android emulator / device
flutter run -d chrome   # Web
```

### Run the boat simulator (no GPS required)

For development and testing without a physical device or GPS signal, use the built-in boat simulator:

```bash
flutter run -t lib/dev/sim_main.dart -d chrome
```

The simulator opens a top-down course map with controls for heading, speed, and position. It feeds simulated positions into the same `PositionSource` abstraction used by the production app.

### Run tests

```bash
flutter test
```

### Generate app icons

```bash
python tool/make_icon.py          # Render 1024×1024 source PNGs
flutter pub run flutter_launcher_icons  # Slice into platform assets
```

---

## Project Structure

```
lib/
├── main.dart               # Production entry point
├── app_shell.dart          # Tab shell (Course + Race screens)
├── models/
│   ├── course.dart         # Course & Buoy data models
│   └── lat_lng.dart        # LatLng with JSON serialisation
├── screens/
│   ├── course_screen.dart  # Course builder & library UI
│   └── race_screen.dart    # Live navigation display
├── services/
│   ├── course_file.dart    # .srcourse.json encode / decode
│   ├── course_library.dart # Bundled + saved course discovery
│   ├── course_store.dart   # SharedPreferences persistence
│   ├── position_source.dart# GPS abstraction interface
│   └── watch_service.dart  # Watch companion MethodChannel
├── utils/
│   └── geo.dart            # Haversine distance, bearing, VMG, ETA
└── dev/                    # Development-only (not shipped)
    ├── sim_main.dart        # Simulator entry point
    ├── boat_simulator.dart  # Headless 5 Hz boat physics
    ├── simulator_screen.dart# Top-down map + controls
    ├── simulated_position_source.dart
    └── course_map_painter.dart  # Custom canvas painter

assets/
├── branding/
│   ├── icon.png             # 1024×1024 app icon source
│   └── icon_foreground.png  # Android adaptive icon foreground
└── courses/
    ├── demo_chicago.srcourse.json
    └── chicago_south_circle_s3.json

test/
├── course_file_test.dart    # Encode/decode, validation, slugification
└── geo_test.dart            # Distance, bearing, VMG, compass tests

tool/
└── make_icon.py             # Generates source icon PNGs with Pillow
```

---

## Course File Format

Courses are stored and shared as `.srcourse.json` files. The format is intentionally human-readable and diff-friendly.

```json
{
  "format": "sail-race-course",
  "version": 1,
  "name": "Demo Chicago",
  "createdAt": "2026-06-04T12:00:00Z",
  "notes": "Four-mark course in Lake Michigan",
  "buoys": [
    {
      "name": "Windward",
      "lat": 41.892,
      "lng": -87.6101,
      "roundingRadiusM": 25
    },
    {
      "name": "Leeward",
      "lat": 41.8855,
      "lng": -87.609
    }
  ]
}
```

**Validation rules applied on import:**
- `format` must equal `"sail-race-course"`
- `version` must equal `1`
- `lat` must be in `[-90, 90]`
- `lng` must be in `[-180, 180]`
- `roundingRadiusM` defaults to `25.0` if omitted

Filenames are auto-slugified: `"My Cool Race!!"` → `my-cool-race.srcourse.json`.

---

## Geographic Math

All calculations are in `lib/utils/geo.dart` and require no external dependencies.

| Function | Description |
|----------|-------------|
| `distanceMeters(a, b)` | Great-circle distance via the haversine formula |
| `bearingDegrees(a, b)` | Initial true bearing from `a` to `b` (0–360°) |
| `vmgMs(speed, course, bearing)` | Velocity made good toward target bearing |
| `destinationPoint(start, distM, bearing)` | Endpoint given start, distance, bearing |
| `knotsToMs()` / `msToKnots()` | Unit conversion |
| `metersToNm()` | Metres to nautical miles |
| `compass(deg)` | Degree → cardinal abbreviation (N, NE, ESE, …) |
| `formatEta(Duration)` | Format as `H:MM:SS` or `M:SS` |

VMG is positive when the boat is closing on the mark and negative when opening.

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `geolocator` | 14.0.2 | GPS on iOS, Android, Web |
| `shared_preferences` | 2.5.5 | On-device course & library storage |
| `file_selector` | 1.0.3 | Cross-platform file picker for import |
| `share_plus` | 13.1.0 | Native share sheet for export |
| `cupertino_icons` | 1.0.8 | iOS icon library |
| `flutter_launcher_icons` | 0.14.4 | App icon generation (dev) |
| `flutter_lints` | 6.0.0 | Static analysis (dev) |

---

## Platform Notes

### iOS
- Requires `NSLocationWhenInUseUsageDescription` in `Info.plist` (already configured).
- Background location is **not** requested; the screen must stay on during a race.

### Android
- Requires `ACCESS_FINE_LOCATION` permission (already configured).
- Tested on API 26+.

### Web
- Uses the browser Geolocation API via `geolocator`.
- HTTPS is required for geolocation in production web deployments.

---

## Bundled Courses

| File | Description |
|------|-------------|
| `demo_chicago.srcourse.json` | Four-mark demo course off Chicago (Lake Michigan) |
| `chicago_south_circle_s3.json` | Real South-Side Circle course used by Chicago racing fleets (SA7 start/finish, Marks 3/2/8) |

---

## Contributing

1. Fork the repository and create a feature branch.
2. Run `flutter test` and ensure all tests pass before opening a pull request.
3. Keep new geographic math covered by unit tests in `test/geo_test.dart`.
4. Course file format changes must update `CourseFile` validation and bump `version`.

---

## License

MIT — see `LICENSE` for details.
