import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/screens/race_screen.dart';
import 'package:sail_race_computer/services/position_source.dart';
import 'package:sail_race_computer/utils/geo.dart';

class _ErrorPositionSource implements PositionSource {
  _ErrorPositionSource(this._error);

  final String _error;
  final _controller = StreamController<Position>.broadcast();

  @override
  Future<String?> ensureReady() async => _error;

  @override
  Stream<Position> get stream => _controller.stream;

  @override
  Future<void> dispose() => _controller.close();
}

class _DelayedPositionSource implements PositionSource {
  _DelayedPositionSource();

  final _controller = StreamController<Position>.broadcast();

  @override
  Future<String?> ensureReady() async => null;

  @override
  Stream<Position> get stream => _controller.stream;

  void emit(Position position) {
    if (!_controller.isClosed) {
      _controller.add(position);
    }
  }

  @override
  Future<void> dispose() => _controller.close();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Position makePosition() => Position(
        latitude: 41.88,
        longitude: -87.62,
        timestamp: DateTime(2024, 6, 1),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 45,
        headingAccuracy: 0,
        speed: 2.6,
        speedAccuracy: 0,
      );

  testWidgets(
      'shows permission error and settings action when location is denied', (
    tester,
  ) async {
    final course = Course(
      name: 'Harbor Start',
      buoys: [
        Buoy(name: 'Alpha', position: const LatLng(41.90, -87.62)),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RaceScreen(
          course: course,
          positionSource: _ErrorPositionSource(locationPermissionDeniedMessage),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
    await tester.pumpAndSettle();

    expect(find.text('Location Access Needed'), findsOneWidget);
    expect(find.text('Open Settings'), findsWidgets);
    expect(
      find.text(
        'Allow Race Mate to access your location so it can record the race.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'does not show no gps signal during initial warm-up before timeout', (
    tester,
  ) async {
    final source = _DelayedPositionSource();
    final course = Course(
      name: 'Harbor Start',
      buoys: [
        Buoy(name: 'Alpha', position: const LatLng(41.90, -87.62)),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RaceScreen(
          course: course,
          positionSource: source,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Start race'));
    await tester.pump();

    expect(find.text('No GPS Signal'), findsNothing);

    await tester.pump(const Duration(seconds: 7));
    expect(find.text('No GPS Signal'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('No GPS Signal'), findsOneWidget);

    source.emit(makePosition());
    await tester.pump();
    await tester.idle();
    await tester.pump();

    expect(find.text('No GPS Signal'), findsNothing);
  });
}
