import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/services/race_computations.dart';
import 'package:sail_race_computer/utils/geo.dart';

Position _makePosition({
  double lat = 41.88,
  double lng = -87.62,
  double speed = 2.6,
  double heading = 45.0,
}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2024, 6, 1),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: heading,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
);

void main() {
  final course = Course(
    name: 'Series',
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

  test('buildRaceClockDisplay shows countdown before offset expires', () {
    final display = buildRaceClockDisplay(
      startedAt: DateTime.utc(2024, 6, 1, 12),
      elapsed: const Duration(seconds: 20),
      startOffset: const Duration(minutes: 1),
    );

    expect(display.caption, 'Start In');
    expect(display.label, formatEta(const Duration(seconds: 40)));
    expect(display.officialElapsed, Duration.zero);
    expect(display.isCountdown, isTrue);
  });

  test('buildRaceClockDisplay shows elapsed after countdown', () {
    final display = buildRaceClockDisplay(
      startedAt: DateTime.utc(2024, 6, 1, 12),
      elapsed: const Duration(minutes: 1, seconds: 15),
      startOffset: const Duration(minutes: 1),
    );

    expect(display.caption, 'Elapsed');
    expect(display.label, formatEta(const Duration(seconds: 15)));
    expect(display.officialElapsed, const Duration(seconds: 15));
    expect(display.isCountdown, isFalse);
  });

  test('computeOfficialRaceDuration never returns negative time', () {
    final duration = computeOfficialRaceDuration(
      startedAt: DateTime.utc(2024, 6, 1, 12),
      timestamp: DateTime.utc(2024, 6, 1, 12, 0, 30),
      startOffset: const Duration(minutes: 1),
    );

    expect(duration, Duration.zero);
  });

  test('buildActiveRaceMetrics derives distance, bearing, vmg, and eta', () {
    final mark = course.buoys.first;
    final fix = _makePosition();

    final metrics = buildActiveRaceMetrics(fix: fix, mark: mark);

    expect(metrics.fix, same(fix));
    expect(metrics.position, isNotNull);
    expect(metrics.distanceMeters, isNotNull);
    expect(metrics.bearingDegrees, isNotNull);
    expect(metrics.vmgMs, greaterThan(0));
    expect(metrics.etaSeconds, isNotNull);
  });

  test('buildCourseMetrics sums leg distances across the course', () {
    final metrics = buildCourseMetrics(course);
    final expected = distanceMeters(
      course.buoys[0].position,
      course.buoys[1].position,
    );

    expect(metrics.totalDistanceMeters, closeTo(expected, 0.001));
    expect(metrics.hasLegDistance, isTrue);
  });

  test('computeRaceProgress advances to the next mark inside radius', () {
    final update = computeRaceProgress(
      fix: _makePosition(lat: 41.90, lng: -87.62),
      course: course,
      currentMarkIndex: 0,
      autoAdvance: true,
      canFinishRace: true,
    );

    expect(update.nextMarkIndex, 1);
    expect(update.reachedFinish, isFalse);
  });

  test('computeRaceProgress finishes on the final mark', () {
    final update = computeRaceProgress(
      fix: _makePosition(lat: 41.92, lng: -87.60),
      course: course,
      currentMarkIndex: 1,
      autoAdvance: true,
      canFinishRace: true,
    );

    expect(update.nextMarkIndex, 1);
    expect(update.reachedFinish, isTrue);
  });
}
