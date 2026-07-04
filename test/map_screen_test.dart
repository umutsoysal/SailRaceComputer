import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/screens/map_screen.dart';
import 'package:sail_race_computer/services/position_source.dart';
import 'package:sail_race_computer/utils/geo.dart';

class _ErrorPositionSource implements PositionSource {
  _ErrorPositionSource(this._error);

  final String _error;
  final _controller = StreamController<Position>.broadcast();

  @override
  Future<String?> ensureReady() async => _error;

  @override
  Future<Position?> getInitialPosition() async => null;

  @override
  Future<Position?> getRecoveryPosition() async => null;

  @override
  Stream<Position> get stream => _controller.stream;

  @override
  Future<void> dispose() => _controller.close();
}

class _TransientErrorThenFixPositionSource implements PositionSource {
  _TransientErrorThenFixPositionSource(this._position);

  final Position _position;
  final _controller = StreamController<Position>.broadcast();

  @override
  Future<String?> ensureReady() async => null;

  @override
  Future<Position?> getInitialPosition() async => null;

  @override
  Future<Position?> getRecoveryPosition() async => null;

  @override
  Stream<Position> get stream => _controller.stream;

  void emitTransientError() {
    if (!_controller.isClosed) {
      _controller.addError(
        'LOCATION UPDATE FAILURE:Error reason: (null)Error description: '
        'The operation couldn’t be completed. (kCLErrorDomain error 1.)',
      );
    }
  }

  void emitFix() {
    if (!_controller.isClosed) {
      _controller.add(_position);
    }
  }

  @override
  Future<void> dispose() => _controller.close();
}

class _InitialFixOnlyPositionSource implements PositionSource {
  _InitialFixOnlyPositionSource(this._position);

  final Position _position;
  final _controller = StreamController<Position>.broadcast();

  @override
  Future<String?> ensureReady() async => null;

  @override
  Future<Position?> getInitialPosition() async => _position;

  @override
  Future<Position?> getRecoveryPosition() async => null;

  @override
  Stream<Position> get stream => _controller.stream;

  @override
  Future<void> dispose() => _controller.close();
}

class _RecoveryOnlyPositionSource implements PositionSource {
  _RecoveryOnlyPositionSource(this._position);

  final Position _position;
  final _controller = StreamController<Position>.broadcast();

  @override
  Future<String?> ensureReady() async => null;

  @override
  Future<Position?> getInitialPosition() async => null;

  @override
  Future<Position?> getRecoveryPosition() async => _position;

  @override
  Stream<Position> get stream => _controller.stream;

  @override
  Future<void> dispose() => _controller.close();
}

void main() {
  testWidgets('shows the course name in the map app bar', (tester) async {
    final course = Course(
      name: 'Wednesday Series',
      buoys: [
        Buoy(name: 'Start', position: const LatLng(41.88, -87.62)),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          course: course,
          positionSource: _ErrorPositionSource('temporary'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Wednesday Series'), findsOneWidget);
  });

  testWidgets('shows actionable permission error instead of waiting chip', (
    tester,
  ) async {
    final course = Course(
      name: 'Wednesday Series',
      buoys: [
        Buoy(name: 'Start', position: const LatLng(41.88, -87.62)),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          course: course,
          positionSource: _ErrorPositionSource(locationPermissionDeniedMessage),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(locationPermissionDeniedMessage), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    expect(find.text('Waiting for GPS'), findsNothing);
  });

  testWidgets('wraps the course canvas in an interactive viewer for pinch zoom',
      (
    tester,
  ) async {
    final course = Course(
      name: 'Wednesday Series',
      buoys: [
        Buoy(name: 'Start', position: const LatLng(41.88, -87.62)),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          course: course,
          positionSource: _ErrorPositionSource('temporary'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('fit button resets the map transform to the fitted view', (
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
        home: MapScreen(
          course: course,
          positionSource: _ErrorPositionSource('temporary'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final controller = viewer.transformationController!;
    controller.value = Matrix4.identity()
      ..translateByDouble(48.0, -36.0, 0.0, 1.0)
      ..scaleByDouble(1.8, 1.8, 1.0, 1.0);
    await tester.pump();

    expect(controller.value, isNot(Matrix4.identity()));

    await tester.tap(find.byKey(const Key('map-fit-button')));
    await tester.pump();

    expect(controller.value, equals(Matrix4.identity()));
  });

  testWidgets('ignores transient iOS location-unknown stream errors', (
    tester,
  ) async {
    final source = _TransientErrorThenFixPositionSource(
      Position(
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
      ),
    );
    final course = Course(
      name: 'Wednesday Series',
      buoys: [
        Buoy(name: 'Start', position: const LatLng(41.88, -87.62)),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          course: course,
          positionSource: source,
        ),
      ),
    );
    await tester.pumpAndSettle();

    source.emitTransientError();
    await tester.pump();

    expect(find.text('Waiting for GPS'), findsOneWidget);
    expect(find.textContaining('kCLErrorDomain error 1'), findsNothing);

    source.emitFix();
    await tester.pump();
    await tester.idle();
    await tester.pump();

    expect(find.text('Waiting for GPS'), findsNothing);
  });

  testWidgets('uses an initial gps fix before the live stream updates', (
    tester,
  ) async {
    final source = _InitialFixOnlyPositionSource(
      Position(
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
      ),
    );
    final course = Course(
      name: 'Wednesday Series',
      buoys: [
        Buoy(name: 'Start', position: const LatLng(41.88, -87.62)),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          course: course,
          positionSource: source,
        ),
      ),
    );
    await tester.pump();
    await tester.idle();
    await tester.pump();

    expect(find.text('Waiting for GPS'), findsNothing);
  });

  testWidgets('uses a recovery gps sample after startup timeout',
      (tester) async {
    final source = _RecoveryOnlyPositionSource(
      Position(
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
      ),
    );
    final course = Course(
      name: 'Wednesday Series',
      buoys: [
        Buoy(name: 'Start', position: const LatLng(41.88, -87.62)),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          course: course,
          positionSource: source,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Waiting for GPS'), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
    await tester.idle();
    await tester.pump();

    expect(find.text('Waiting for GPS'), findsNothing);
  });
}
