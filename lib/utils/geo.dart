import 'dart:math' as math;

/// Geographic position in degrees.
class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
  factory LatLng.fromJson(Map<String, dynamic> j) =>
      LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
}

const double _earthRadiusM = 6371008.8;

double _toRad(double d) => d * math.pi / 180.0;
double _toDeg(double r) => r * 180.0 / math.pi;

/// Great-circle distance in meters between two points (haversine).
double distanceMeters(LatLng a, LatLng b) {
  final dLat = _toRad(b.lat - a.lat);
  final dLng = _toRad(b.lng - a.lng);
  final lat1 = _toRad(a.lat);
  final lat2 = _toRad(b.lat);
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return _earthRadiusM * c;
}

/// Destination point given a start, distance (m) and bearing (deg true).
LatLng destinationPoint(LatLng start, double distanceM, double bearingDeg) {
  final br = _toRad(bearingDeg);
  final lat1 = _toRad(start.lat);
  final lng1 = _toRad(start.lng);
  final dr = distanceM / _earthRadiusM;
  final lat2 = math.asin(
    math.sin(lat1) * math.cos(dr) +
        math.cos(lat1) * math.sin(dr) * math.cos(br),
  );
  final lng2 =
      lng1 +
      math.atan2(
        math.sin(br) * math.sin(dr) * math.cos(lat1),
        math.cos(dr) - math.sin(lat1) * math.sin(lat2),
      );
  return LatLng(_toDeg(lat2), ((_toDeg(lng2) + 540) % 360) - 180);
}

/// Convert knots to m/s.
double knotsToMs(double kn) => kn / 1.9438444924406;

/// Initial bearing from `a` to `b` in degrees true (0..360).
double bearingDegrees(LatLng a, LatLng b) {
  final lat1 = _toRad(a.lat);
  final lat2 = _toRad(b.lat);
  final dLng = _toRad(b.lng - a.lng);
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  final brng = _toDeg(math.atan2(y, x));
  return (brng + 360.0) % 360.0;
}

/// Velocity made good toward the target.
///
/// [speedMs] is speed over ground in m/s. [courseDeg] is heading over ground.
/// [bearingToTargetDeg] is the bearing from current position to the mark.
/// Returns VMG in m/s (positive = closing, negative = opening).
double vmgMs(double speedMs, double courseDeg, double bearingToTargetDeg) {
  final delta = _toRad(courseDeg - bearingToTargetDeg);
  return speedMs * math.cos(delta);
}

/// Convert meters per second to knots.
double msToKnots(double ms) => ms * 1.9438444924406;

/// Convert meters to nautical miles.
double metersToNm(double m) => m / 1852.0;

/// Compass shorthand for a bearing (e.g. 45 -> "NE").
String compass(double deg) {
  const dirs = [
    'N',
    'NNE',
    'NE',
    'ENE',
    'E',
    'ESE',
    'SE',
    'SSE',
    'S',
    'SSW',
    'SW',
    'WSW',
    'W',
    'WNW',
    'NW',
    'NNW',
  ];
  final i = (((deg % 360) / 22.5) + 0.5).floor() % 16;
  return dirs[i];
}

/// Format a duration as H:MM:SS or M:SS.
String formatEta(Duration d) {
  if (d.inSeconds < 0 || d.inSeconds.isInfinite) return '--:--';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${d.inMinutes}:${s.toString().padLeft(2, '0')}';
}
