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
  Stream<Position> get stream => _controller.stream;

  @override
  Future<void> dispose() => _controller.close();
}

void main() {
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
}
