import 'package:flutter_test/flutter_test.dart';

import 'package:sail_race_computer/utils/geo.dart';

void main() {
  group('distance', () {
    test('distance between same point is zero', () {
      const p = LatLng(41.88, -87.62);
      expect(distanceMeters(p, p), 0);
    });

    test('one degree of latitude is about 60 nautical miles', () {
      const a = LatLng(41.0, -87.6);
      const b = LatLng(42.0, -87.6);

      expect(metersToNm(distanceMeters(a, b)), closeTo(60, 0.2));
    });

    test('is symmetric', () {
      const a = LatLng(41.852833, -87.556833);
      const b = LatLng(41.871, -87.5395);

      expect(distanceMeters(a, b), closeTo(distanceMeters(b, a), 1e-6));
    });
  });

  group('bearing', () {
    test('bearing due east is ~90°', () {
      const a = LatLng(0, 0);
      const b = LatLng(0, 1);

      expect(bearingDegrees(a, b), closeTo(90, 0.5));
    });

    test('bearing due north is 0° and due south is 180°', () {
      const origin = LatLng(41.0, -87.6);

      expect(
        bearingDegrees(origin, const LatLng(42.0, -87.6)),
        closeTo(0, 0.1),
      );
      expect(
        bearingDegrees(origin, const LatLng(40.0, -87.6)),
        closeTo(180, 0.1),
      );
    });

    test('is always normalised into 0..360', () {
      const a = LatLng(41.0, -87.6);
      const b = LatLng(41.5, -88.6); // north-west, i.e. a negative raw bearing

      final bearing = bearingDegrees(a, b);
      expect(bearing, greaterThanOrEqualTo(0));
      expect(bearing, lessThan(360));
      expect(bearing, closeTo(303.95, 0.1));
    });
  });

  group('destinationPoint', () {
    test('zero distance returns the start', () {
      const start = LatLng(41.852833, -87.556833);
      final end = destinationPoint(start, 0, 42);

      expect(end.lat, closeTo(start.lat, 1e-9));
      expect(end.lng, closeTo(start.lng, 1e-9));
    });

    test('round-trips against distance and bearing', () {
      const start = LatLng(41.852833, -87.556833);
      final end = destinationPoint(start, 1852.0, 35);

      expect(distanceMeters(start, end), closeTo(1852.0, 0.5));
      expect(bearingDegrees(start, end), closeTo(35, 0.1));
    });

    test('heading north increases latitude only', () {
      const start = LatLng(41.0, -87.6);
      final end = destinationPoint(start, 1000, 0);

      expect(end.lat, greaterThan(start.lat));
      expect(end.lng, closeTo(start.lng, 1e-9));
    });

    test('normalises longitude across the antimeridian', () {
      const start = LatLng(0, 179.9);
      final end = destinationPoint(start, 40000, 90);

      expect(end.lng, inInclusiveRange(-180, 180));
      expect(end.lng, lessThan(0));
    });
  });

  group('VMG', () {
    test('heading straight at mark equals SOG', () {
      expect(vmgMs(5.0, 45.0, 45.0), closeTo(5.0, 1e-9));
    });

    test('perpendicular heading is zero', () {
      expect(vmgMs(5.0, 0.0, 90.0).abs(), closeTo(0, 1e-9));
    });

    test('sailing away is negative', () {
      expect(vmgMs(5.0, 180.0, 0.0), closeTo(-5.0, 1e-9));
    });

    test('a 60° error costs half the boat speed', () {
      expect(vmgMs(6.0, 60.0, 0.0), closeTo(3.0, 1e-9));
    });
  });

  group('unit conversion', () {
    test('knots and m/s round-trip', () {
      expect(msToKnots(knotsToMs(6.2)), closeTo(6.2, 1e-9));
    });

    test('one knot is one nautical mile per hour', () {
      expect(metersToNm(knotsToMs(1) * 3600), closeTo(1.0, 1e-9));
    });
  });

  group('compass', () {
    test('cardinal points', () {
      expect(compass(0), 'N');
      expect(compass(90), 'E');
      expect(compass(180), 'S');
      expect(compass(270), 'W');
    });

    test('intercardinal and secondary points', () {
      expect(compass(45), 'NE');
      expect(compass(112.5), 'ESE');
      expect(compass(315), 'NW');
    });

    test('wraps past 360 and rounds to the nearest sector', () {
      expect(compass(360), 'N');
      expect(compass(370), 'N');
      expect(compass(359), 'N');
      expect(compass(11.24), 'N');
      expect(compass(11.26), 'NNE');
    });
  });

  group('formatEta', () {
    test('formats under an hour as M:SS', () {
      expect(formatEta(const Duration(seconds: 5)), '0:05');
      expect(formatEta(const Duration(minutes: 2, seconds: 1)), '2:01');
      expect(formatEta(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('formats an hour or more as H:MM:SS', () {
      expect(formatEta(const Duration(hours: 1)), '1:00:00');
      expect(
        formatEta(const Duration(hours: 2, minutes: 3, seconds: 4)),
        '2:03:04',
      );
    });

    test('negative durations render as unknown', () {
      expect(formatEta(const Duration(seconds: -1)), '--:--');
    });
  });
}
