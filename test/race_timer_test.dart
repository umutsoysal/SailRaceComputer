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
}) {
  return MaterialApp(
    home: RaceScreen(
      course: course,
      positionSource: _FakePositionSource(fix),
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

  final course = Course(
    name: 'Harbor Start',
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

  testWidgets('app bar shows elapsed time once the race starts', (
    tester,
  ) async {
    await tester.pumpWidget(_buildRaceScreen(course: course, fix: fix));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
    await _drainAsyncUi(tester);

    expect(find.byKey(const Key('race-app-bar-timer')), findsOneWidget);
    expect(find.byKey(const Key('race-app-bar-timer-caption')), findsOneWidget);
    expect(find.text('Elapsed'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));

    expect(find.text('0:02'), findsOneWidget);
  });

  testWidgets('countdown offset rolls into elapsed race time', (tester) async {
    await tester.pumpWidget(_buildRaceScreen(course: course, fix: fix));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start-offset-1')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
    await _drainAsyncUi(tester);

    expect(find.text('Start In'), findsOneWidget);
    expect(find.text('1:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:59'), findsOneWidget);

    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Elapsed'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('0:03'), findsOneWidget);
  });
}
