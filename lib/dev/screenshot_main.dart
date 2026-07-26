// Dev-only entrypoint used to capture the README and app-store screenshots.
//
// It boots the real [AppShell] against the headless [BoatSimulator] so every
// screen shows plausible live data without needing a GPS fix, a device, or a
// network connection. Nothing here ships in the production app — the release
// entrypoint is lib/main.dart, which never imports lib/dev/.
//
//   ./tool/flutterw.sh run -t lib/dev/screenshot_main.dart -d chrome
//   make screenshots        # builds the web bundle and serves it on :8787
//
// On web the starting tab is selectable so each screen can be captured from a
// stable URL: `?tab=0` courses, `1` map, `2` race, `3` recordings,
// `4` settings.

import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../models/course.dart';
import '../services/position_source.dart';
import '../utils/geo.dart';
import 'boat_simulator.dart';
import 'simulated_position_source.dart';

/// Chicago "beer can" course marks — the same buoys as the bundled
/// `assets/courses/beercan_south.json`, inlined so the harness never depends
/// on asset loading or user preferences.
const _sa7 = LatLng(41.852833, -87.556833);
const _mark1 = LatLng(41.871, -87.556833);
const _mark2 = LatLng(41.865667, -87.5395);
const _mark3 = LatLng(41.852833, -87.5325);

Course _demoCourse() => Course(
  name: 'Wednesday Beer Can — Course 3',
  buoys: [
    Buoy(name: 'SA7 Start/Finish', position: _sa7, roundingRadiusM: 30),
    Buoy(name: 'Mark 1', position: _mark1),
    Buoy(name: 'Mark 2', position: _mark2),
    Buoy(name: 'Mark 3', position: _mark3),
    Buoy(name: 'SA7 Finish', position: _sa7, roundingRadiusM: 30),
  ],
);

int _initialTabFromUrl() {
  final raw = Uri.base.queryParameters['tab'];
  final parsed = int.tryParse(raw ?? '');
  if (parsed == null || parsed < 0 || parsed > 4) return 0;
  return parsed;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Approaching the start line from the south at hull speed, so every screen
  // shows a boat that is closing on the next mark rather than running from it.
  final start = destinationPoint(_sa7, 700, 196);
  final sim = BoatSimulator(
    startPosition: start,
    headingDeg: 14,
    speedKnots: 6.2,
  )..start();

  runApp(ScreenshotApp(sim: sim, initialTab: _initialTabFromUrl()));
}

/// Wraps [AppShell] with a simulated position source for screenshot capture.
class ScreenshotApp extends StatefulWidget {
  const ScreenshotApp({super.key, required this.sim, this.initialTab = 0});

  final BoatSimulator sim;
  final int initialTab;

  @override
  State<ScreenshotApp> createState() => _ScreenshotAppState();
}

class _ScreenshotAppState extends State<ScreenshotApp> {
  late final PositionSource _source = SimulatedPositionSource(widget.sim);
  late Course _course = _demoCourse();

  @override
  void dispose() {
    _source.dispose();
    widget.sim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Race Mate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6FB8)),
        useMaterial3: true,
      ),
      home: AppShell(
        course: _course,
        onCourseChanged: (c) => setState(() => _course = c),
        positionSource: _source,
        initialTab: widget.initialTab,
      ),
    );
  }
}
