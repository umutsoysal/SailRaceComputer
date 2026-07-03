import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sail_race_computer/app_shell.dart';
import 'package:sail_race_computer/models/course.dart';
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

Future<void> _drainAsyncUi(WidgetTester tester) async {
  await tester.pump();
  await tester.idle();
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'race tab stays between map and recordings in the bottom navigation bar',
      (
    tester,
  ) async {
    final course = Course(
      name: 'Wednesday Series',
      buoys: [
        Buoy(name: 'Start', position: const LatLng(41.88, -87.62)),
        Buoy(name: 'Finish', position: const LatLng(41.89, -87.61)),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(course: course, onCourseChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    final mapCenter = tester.getCenter(find.text('Map'));
    final raceCenter = tester.getCenter(find.text('Race'));
    final recordingsCenter = tester.getCenter(find.text('Recordings'));

    expect(raceCenter.dx, greaterThan(mapCenter.dx));
    expect(raceCenter.dx, lessThan(recordingsCenter.dx));
  });

  testWidgets('race tab stays highlighted while recording is active', (
    tester,
  ) async {
    final course = Course(
      name: 'Wednesday Series',
      buoys: [
        Buoy(name: 'Start', position: const LatLng(41.88, -87.62)),
        Buoy(name: 'Finish', position: const LatLng(41.89, -87.61)),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          course: course,
          onCourseChanged: (_) {},
          positionSource: _FakePositionSource(_makePosition()),
        ),
      ),
    );
    await _drainAsyncUi(tester);

    expect(
      find.byKey(const Key('race-tab-recording-indicator')),
      findsNothing,
    );

    await tester.tap(find.text('Race'));
    await _drainAsyncUi(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
    await _drainAsyncUi(tester);

    await tester.tap(find.text('Recordings'));
    await _drainAsyncUi(tester);

    final indicatorFinder = find.byKey(
      const Key('race-tab-recording-indicator'),
    );
    expect(indicatorFinder, findsOneWidget);

    final indicator = tester.widget<DecoratedBox>(indicatorFinder);
    final decoration = indicator.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFFC4C02));
    expect(decoration.shape, BoxShape.circle);

    await tester.tap(find.text('Race'));
    await _drainAsyncUi(tester);
    await tester.tap(find.byKey(const Key('finish-race-button')));
    await _drainAsyncUi(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Finish & save'),
      ),
    );
    await _drainAsyncUi(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const Key('race-tab-recording-indicator')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('race-tab-recording-selected')),
      findsNothing,
    );
  });
}
