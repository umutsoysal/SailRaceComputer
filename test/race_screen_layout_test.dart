import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/screens/race_screen.dart';
import 'package:sail_race_computer/services/position_source.dart';
import 'package:sail_race_computer/utils/geo.dart';

class _FakePositionSource implements PositionSource {
  _FakePositionSource(this._fix);

  final Position _fix;
  final _controller = StreamController<Position>.broadcast();

  @override
  Stream<Position> get stream => _controller.stream;

  @override
  Future<Position?> getInitialPosition() async => _fix;

  @override
  Future<Position?> getRecoveryPosition() async => _fix;

  @override
  Future<String?> ensureReady() async {
    Future<void>.delayed(Duration.zero, () {
      if (!_controller.isClosed) {
        _controller.add(_fix);
      }
    });
    return null;
  }

  @override
  Future<void> dispose() => _controller.close();
}

Position _makePosition({
  double lat = 41.88,
  double lng = -87.62,
  double speed = 2.6,
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

Widget _buildRaceScreen({
  required Course course,
  required Position fix,
  required Size screenSize,
  ValueChanged<Course>? onCourseChanged,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: screenSize),
      child: RaceScreen(
        course: course,
        positionSource: _FakePositionSource(fix),
        onCourseChanged: onCourseChanged,
      ),
    ),
  );
}

Future<void> _drainAsyncUi(WidgetTester tester) async {
  await tester.pump();
  await tester.idle();
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const portrait = Size(390, 844);
  const landscape = Size(844, 390);
  const compactLandscape = Size(640, 360);

  final course = Course(
    name: 'Test',
    buoys: [
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
    ],
  );

  final fix = _makePosition();

  group('RaceScreen portrait layout', () {
    testWidgets(
      'shows launcher with course picker and map preview before race starts',
      (tester) async {
        await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: portrait),
        );
        await tester.pumpAndSettle();

        expect(find.text('Ready to race'), findsOneWidget);
        expect(find.text('Race course'), findsOneWidget);
        expect(find.text('Course preview'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Start race'), findsOneWidget);
        expect(find.text('VMG to mark'), findsNothing);
      },
    );

    testWidgets('shows metrics after starting the race', (tester) async {
      await tester.pumpWidget(
        _buildRaceScreen(course: course, fix: fix, screenSize: portrait),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
      await _drainAsyncUi(tester);

      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Bearing'), findsOneWidget);
      expect(find.text('SOG'), findsOneWidget);
      expect(find.text('COG'), findsOneWidget);
      expect(find.text('ETA at current VMG'), findsOneWidget);
      expect(find.text('VMG to mark'), findsOneWidget);
    });

    testWidgets('supports swiping between overview, VMG, and heading views', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRaceScreen(course: course, fix: fix, screenSize: portrait),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
      await _drainAsyncUi(tester);

      expect(find.byKey(const Key('race-view-overview')), findsOneWidget);

      await tester.fling(
        find.byKey(const Key('race-view-overview')),
        const Offset(-300, 0),
        1200,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('race-view-vmg')), findsOneWidget);
      expect(find.text('VMG focus'), findsOneWidget);
      expect(find.text('VMG to mark'), findsOneWidget);

      await tester.fling(
        find.byKey(const Key('race-view-vmg')),
        const Offset(-300, 0),
        1200,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('race-view-heading')), findsOneWidget);
      expect(find.text('Heading to waypoint'), findsOneWidget);
      expect(find.text('Heading'), findsWidgets);
      expect(find.text('Bearing to waypoint'), findsOneWidget);
    });
  });

  group('RaceScreen landscape layout', () {
    testWidgets('shows launcher before race starts', (tester) async {
      await tester.pumpWidget(
        _buildRaceScreen(course: course, fix: fix, screenSize: landscape),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ready to race'), findsOneWidget);
      expect(find.text('Course preview'), findsOneWidget);
      expect(find.text('VMG to mark'), findsNothing);
    });

    testWidgets('shows all secondary metric labels after starting', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRaceScreen(course: course, fix: fix, screenSize: landscape),
      );
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.widgetWithText(FilledButton, 'Start race'));
      await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
      await _drainAsyncUi(tester);

      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Bearing'), findsOneWidget);
      expect(find.text('SOG'), findsOneWidget);
      expect(find.text('COG'), findsOneWidget);
      expect(find.text('ETA at current VMG'), findsOneWidget);
    });

    testWidgets(
      'shows Previous and Next mark navigation buttons once race is active',
      (tester) async {
        await tester.pumpWidget(
          _buildRaceScreen(course: course, fix: fix, screenSize: landscape),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
        await _drainAsyncUi(tester);

        expect(find.text('Previous'), findsOneWidget);
        expect(find.text('Next mark'), findsOneWidget);
      },
    );

    testWidgets('does not overflow on compact landscape screens', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = compactLandscape;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildRaceScreen(
          course: course,
          fix: fix,
          screenSize: compactLandscape,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Ready to race'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start race'), findsOneWidget);
    });

    testWidgets('shows COG and SOG cleanly on compact landscape after start', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = compactLandscape;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildRaceScreen(
          course: course,
          fix: fix,
          screenSize: compactLandscape,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Start race'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
      await _drainAsyncUi(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('SOG'), findsOneWidget);
      expect(find.text('COG'), findsOneWidget);
      expect(find.text('ETA at current VMG'), findsOneWidget);
    });

    testWidgets('VMG widget is horizontally centred (in the middle column)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRaceScreen(course: course, fix: fix, screenSize: landscape),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
      await _drainAsyncUi(tester);

      final vmgLabel = find.text('VMG to mark');
      expect(vmgLabel, findsOneWidget);

      final screenWidth = landscape.width;
      final vmgCenter = tester.getCenter(vmgLabel);

      expect(vmgCenter.dx, greaterThan(screenWidth / 3));
      expect(vmgCenter.dx, lessThan(screenWidth * 2 / 3));
    });

    testWidgets('manual finish asks for confirmation before saving', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRaceScreen(course: course, fix: fix, screenSize: landscape),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
      await _drainAsyncUi(tester);
      await tester.tap(find.text('Next mark'));
      await tester.pump();

      expect(find.text('VMG to mark'), findsOneWidget);

      await tester.tap(find.byKey(const Key('finish-race-button')));
      await tester.pumpAndSettle();

      expect(find.text('Finish race?'), findsOneWidget);
      expect(find.text('Keep racing'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Finish & save'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Finish & save'),
        ),
      );
      await _drainAsyncUi(tester);
      await tester.pumpAndSettle();

      expect(find.text('Race saved'), findsOneWidget);
      expect(find.text('VMG to mark'), findsNothing);
      expect(find.textContaining('Saved '), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Start new race'),
        findsOneWidget,
      );
    });

    testWidgets('canceling manual finish keeps the race running', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRaceScreen(course: course, fix: fix, screenSize: landscape),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
      await _drainAsyncUi(tester);

      expect(find.text('VMG to mark'), findsOneWidget);

      await tester.tap(find.byKey(const Key('finish-race-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep racing'));
      await tester.pumpAndSettle();

      expect(find.text('Finish race?'), findsNothing);
      expect(find.text('VMG to mark'), findsOneWidget);
      expect(find.byKey(const Key('finish-race-button')), findsOneWidget);
    });

    testWidgets('active race shows one prominent finish button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRaceScreen(course: course, fix: fix, screenSize: landscape),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
      await _drainAsyncUi(tester);

      expect(find.byKey(const Key('finish-race-button')), findsOneWidget);
      expect(find.text('VMG to mark'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
    });

    testWidgets('starting a new race resets back to the first mark', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildRaceScreen(course: course, fix: fix, screenSize: landscape),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
      await _drainAsyncUi(tester);
      await tester.tap(find.text('Next mark'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('finish-race-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Finish & save'),
        ),
      );
      await _drainAsyncUi(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start new race'));
      await _drainAsyncUi(tester);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Race saved'), findsNothing);
    });
  });

  group('RaceScreen empty course', () {
    testWidgets('shows prompt when no buoys', (tester) async {
      final empty = Course(name: 'Empty', buoys: []);
      await tester.pumpWidget(
        MaterialApp(
          home: RaceScreen(
            course: empty,
            positionSource: _FakePositionSource(fix),
          ),
        ),
      );
      expect(
        find.textContaining('Add buoys to create the course on the Course tab'),
        findsOneWidget,
      );
    });
  });

  testWidgets('auto finish saves the race on the last mark', (tester) async {
    final singleMarkCourse = Course(
      name: 'Sprint',
      buoys: [
        Buoy(
          name: 'Finish',
          position: const LatLng(41.88, -87.62),
          roundingRadiusM: 30,
        ),
      ],
    );

    await tester.pumpWidget(
      _buildRaceScreen(
        course: singleMarkCourse,
        fix: fix,
        screenSize: portrait,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
    await _drainAsyncUi(tester);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('Race saved'), findsOneWidget);
    expect(find.textContaining('Saved 1 GPS point'), findsWidgets);
  });
}
