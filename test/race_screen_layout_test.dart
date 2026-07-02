import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/screens/race_screen.dart';
import 'package:sail_race_computer/services/position_source.dart';
import 'package:sail_race_computer/utils/geo.dart';

// ---------------------------------------------------------------------------
// Fake position source that emits a single canned fix for tests.
// ---------------------------------------------------------------------------

class _FakePositionSource implements PositionSource {
  _FakePositionSource(this._fix);

  final Position _fix;
  final _controller = StreamController<Position>.broadcast();

  @override
  Stream<Position> get stream => _controller.stream;

  @override
  Future<String?> ensureReady() async {
    Future<void>.delayed(Duration.zero, () {
      if (!_controller.isClosed) {
        _controller.add(_fix);
      }
    });
    return null; // no error
  }

  @override
  Future<void> dispose() => _controller.close();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [Position] with sensible defaults for the fields we don't care
/// about in layout tests.
Position _makePosition({
  double lat = 41.88,
  double lng = -87.62,
  double speed = 2.6, // m/s ≈ 5 kn
  double heading = 45.0,
  double accuracy = 5.0,
}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2024, 6, 1),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
    );

/// Builds the [RaceScreen] inside a [MaterialApp] with a controlled
/// [MediaQuery] so we can simulate portrait or landscape.
Widget _buildRaceScreen({
  required Course course,
  required Position fix,
  required Size screenSize,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: screenSize),
      child: RaceScreen(
        course: course,
        positionSource: _FakePositionSource(fix),
      ),
    ),
  );
}

Future<void> _drainAsyncUi(WidgetTester tester) async {
  await tester.pump();
  await tester.idle();
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const portrait = Size(390, 844); // typical phone portrait
  const landscape = Size(844, 390); // typical phone landscape
  const compactLandscape = Size(640, 360); // simulator/device landscape

  final course = Course(name: 'Test', buoys: [
    Buoy(
      name: 'Alpha',
      position: const LatLng(41.90, -87.62),
      roundingRadiusM: 25,
    ),
    Buoy(
      name: 'Beta',
      position: const LatLng(41.92, -87.60),
      roundingRadiusM: 25,
    ),
  ]);

  final fix = _makePosition();

  group('RaceScreen portrait layout', () {
    testWidgets('shows mark name and stopped prompt before race starts',
        (tester) async {
      await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: portrait));
      await tester.pump();

      // Mark header
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Race stopped'), findsOneWidget);
      expect(
        find.text(
          'Press Start to begin race tracking and record your GPS track.',
        ),
        findsOneWidget,
      );
      expect(find.text('VMG to mark'), findsNothing);
    });

    testWidgets('shows metrics after starting the race', (tester) async {
      await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: portrait));
      await tester.pump();
      await tester.tap(find.byTooltip('Start race'));
      await _drainAsyncUi(tester);

      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Bearing'), findsOneWidget);
      expect(find.text('SOG'), findsOneWidget);
      expect(find.text('COG'), findsOneWidget);
      expect(find.text('ETA at current VMG'), findsOneWidget);
      expect(find.text('VMG to mark'), findsOneWidget);
    });

    testWidgets('shows Previous and Next mark navigation buttons',
        (tester) async {
      await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: portrait));
      await tester.pump();

      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('Next mark'), findsOneWidget);
    });
  });

  group('RaceScreen landscape layout', () {
    testWidgets('shows mark name and stopped prompt before race starts',
        (tester) async {
      await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: landscape));
      await tester.pump();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Race stopped'), findsOneWidget);
      expect(find.text('VMG to mark'), findsNothing);
    });

    testWidgets('shows all secondary metric labels after starting',
        (tester) async {
      await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: landscape));
      await tester.pump();
      await tester.tap(find.byTooltip('Start race'));
      await _drainAsyncUi(tester);

      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Bearing'), findsOneWidget);
      expect(find.text('SOG'), findsOneWidget);
      expect(find.text('COG'), findsOneWidget);
      expect(find.text('ETA at current VMG'), findsOneWidget);
    });

    testWidgets('shows Previous and Next mark navigation buttons',
        (tester) async {
      await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: landscape));
      await tester.pump();

      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('Next mark'), findsOneWidget);
    });

    testWidgets('does not overflow on compact landscape screens',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = compactLandscape;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildRaceScreen(
        course: course,
        fix: fix,
        screenSize: compactLandscape,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('Next mark'), findsOneWidget);
      expect(find.text('Race stopped'), findsOneWidget);
    });

    testWidgets('VMG widget is horizontally centred (in the middle column)',
        (tester) async {
      // Use a fixed window size so pixel positions are deterministic.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = landscape;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: landscape));
      await tester.pump();
      await tester.tap(find.byTooltip('Start race'));
      await _drainAsyncUi(tester);

      // Find the big VMG Card by its label text.
      final vmgLabel = find.text('VMG to mark');
      expect(vmgLabel, findsOneWidget);

      final screenWidth = landscape.width;
      final vmgCenter = tester.getCenter(vmgLabel);

      // The VMG widget should be within the middle third of the screen width.
      expect(vmgCenter.dx, greaterThan(screenWidth / 3));
      expect(vmgCenter.dx, lessThan(screenWidth * 2 / 3));
    });

    testWidgets('finish saves the race and shows the finished state',
        (tester) async {
      await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: landscape));
      await tester.pump();

      await tester.tap(find.byTooltip('Start race'));
      await _drainAsyncUi(tester);
      await tester.tap(find.text('Next mark'));
      await tester.pump();

      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('VMG to mark'), findsOneWidget);

      await tester.tap(find.byTooltip('Finish race'));
      await _drainAsyncUi(tester);

      expect(find.text('Race finished'), findsOneWidget);
      expect(find.text('VMG to mark'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.byTooltip('Start new race'), findsOneWidget);
    });

    testWidgets('pause switches control to resume without hiding metrics',
        (tester) async {
      await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: landscape));
      await tester.pump();

      await tester.tap(find.byTooltip('Start race'));
      await _drainAsyncUi(tester);

      expect(find.byTooltip('Pause race'), findsOneWidget);
      expect(find.text('VMG to mark'), findsOneWidget);

      await tester.tap(find.byTooltip('Pause race'));
      await tester.pump();

      expect(find.byTooltip('Resume race'), findsOneWidget);
      expect(find.text('VMG to mark'), findsOneWidget);
    });

    testWidgets('starting a new race resets back to the first mark',
        (tester) async {
      await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: landscape));
      await tester.pump();

      await tester.tap(find.byTooltip('Start race'));
      await _drainAsyncUi(tester);
      await tester.tap(find.text('Next mark'));
      await tester.pump();
      await tester.tap(find.byTooltip('Finish race'));
      await _drainAsyncUi(tester);

      expect(find.text('Beta'), findsOneWidget);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Start new race'));
      await _drainAsyncUi(tester);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Race finished'), findsNothing);
    });
  });

  group('RaceScreen empty course', () {
    testWidgets('shows prompt when no buoys', (tester) async {
      final empty = Course(name: 'Empty', buoys: []);
      await tester.pumpWidget(MaterialApp(
        home: RaceScreen(
          course: empty,
          positionSource: _FakePositionSource(fix),
        ),
      ));
      expect(find.text('Add buoys on the Course tab first.'), findsOneWidget);
    });
  });

  testWidgets('auto finish saves the race on the last mark', (tester) async {
    final singleMarkCourse = Course(name: 'Sprint', buoys: [
      Buoy(
        name: 'Finish',
        position: const LatLng(41.88, -87.62),
        roundingRadiusM: 30,
      ),
    ]);

    await tester.pumpWidget(_buildRaceScreen(
      course: singleMarkCourse,
      fix: fix,
      screenSize: portrait,
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('Start race'));
    await _drainAsyncUi(tester);

    expect(find.text('Race finished'), findsOneWidget);
    expect(find.textContaining('Saved 1 GPS point'), findsWidgets);
  });
}
