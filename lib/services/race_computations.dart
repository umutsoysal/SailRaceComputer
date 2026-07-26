import 'package:geolocator/geolocator.dart';

import '../models/course.dart';
import '../utils/geo.dart';

class RaceClockDisplay {
  const RaceClockDisplay({
    required this.caption,
    required this.label,
    required this.officialElapsed,
    required this.isCountdown,
  });

  final String caption;
  final String label;
  final Duration officialElapsed;
  final bool isCountdown;
}

class ActiveRaceMetrics {
  const ActiveRaceMetrics({
    required this.fix,
    required this.position,
    required this.distanceMeters,
    required this.bearingDegrees,
    required this.speedMs,
    required this.headingDegrees,
    required this.vmgMs,
    required this.etaSeconds,
  });

  final Position? fix;
  final LatLng? position;
  final double? distanceMeters;
  final double? bearingDegrees;
  final double speedMs;
  final double headingDegrees;
  final double vmgMs;
  final int? etaSeconds;
}

class CourseMetrics {
  const CourseMetrics({required this.totalDistanceMeters});

  final double totalDistanceMeters;

  bool get hasLegDistance => totalDistanceMeters > 0;
}

class RaceProgressUpdate {
  const RaceProgressUpdate({
    required this.nextMarkIndex,
    required this.reachedFinish,
  });

  final int nextMarkIndex;
  final bool reachedFinish;
}

RaceClockDisplay buildRaceClockDisplay({
  required DateTime? startedAt,
  required Duration elapsed,
  required Duration startOffset,
}) {
  if (startedAt == null) {
    return const RaceClockDisplay(
      caption: '',
      label: 'Ready to race',
      officialElapsed: Duration.zero,
      isCountdown: false,
    );
  }

  final remaining = startOffset - elapsed;
  if (remaining > Duration.zero) {
    return RaceClockDisplay(
      caption: 'Start In',
      label: formatEta(remaining),
      officialElapsed: Duration.zero,
      isCountdown: true,
    );
  }

  final officialElapsed = elapsed - startOffset;
  return RaceClockDisplay(
    caption: 'Elapsed',
    label: formatEta(officialElapsed),
    officialElapsed: officialElapsed,
    isCountdown: false,
  );
}

Duration computeOfficialRaceDuration({
  required DateTime? startedAt,
  required DateTime timestamp,
  required Duration startOffset,
}) {
  if (startedAt == null) return Duration.zero;
  final duration = timestamp.difference(startedAt) - startOffset;
  return duration.isNegative ? Duration.zero : duration;
}

ActiveRaceMetrics buildActiveRaceMetrics({
  required Position? fix,
  required Buoy mark,
}) {
  final position = fix == null ? null : LatLng(fix.latitude, fix.longitude);
  final distance = position == null
      ? null
      : distanceMeters(position, mark.position);
  final bearing = position == null
      ? null
      : bearingDegrees(position, mark.position);
  final speedMs = fix?.speed ?? 0.0;
  final headingDegrees = fix?.heading ?? 0.0;
  final vmg = bearing == null ? 0.0 : vmgMs(speedMs, headingDegrees, bearing);
  final etaSeconds = vmg > 0.05 && distance != null
      ? (distance / vmg).round()
      : null;

  return ActiveRaceMetrics(
    fix: fix,
    position: position,
    distanceMeters: distance,
    bearingDegrees: bearing,
    speedMs: speedMs,
    headingDegrees: headingDegrees,
    vmgMs: vmg,
    etaSeconds: etaSeconds,
  );
}

CourseMetrics buildCourseMetrics(Course course) {
  double totalDistance = 0;
  final buoys = course.buoys;
  for (var i = 0; i < buoys.length - 1; i++) {
    totalDistance += distanceMeters(buoys[i].position, buoys[i + 1].position);
  }
  return CourseMetrics(totalDistanceMeters: totalDistance);
}

RaceProgressUpdate computeRaceProgress({
  required Position fix,
  required Course course,
  required int currentMarkIndex,
  required bool autoAdvance,
  required bool canFinishRace,
}) {
  if (!autoAdvance || currentMarkIndex >= course.buoys.length) {
    return RaceProgressUpdate(
      nextMarkIndex: currentMarkIndex,
      reachedFinish: false,
    );
  }

  final mark = course.buoys[currentMarkIndex];
  final distanceToMark = distanceMeters(
    LatLng(fix.latitude, fix.longitude),
    mark.position,
  );
  if (distanceToMark > mark.roundingRadiusM) {
    return RaceProgressUpdate(
      nextMarkIndex: currentMarkIndex,
      reachedFinish: false,
    );
  }

  if (currentMarkIndex < course.buoys.length - 1) {
    return RaceProgressUpdate(
      nextMarkIndex: currentMarkIndex + 1,
      reachedFinish: false,
    );
  }

  return RaceProgressUpdate(
    nextMarkIndex: currentMarkIndex,
    reachedFinish: canFinishRace,
  );
}
