import 'package:flutter_test/flutter_test.dart';

import 'package:sail_race_computer/utils/geo.dart';

void main() {
  test('distance between same point is zero', () {
    const p = LatLng(41.88, -87.62);
    expect(distanceMeters(p, p), 0);
  });

  test('bearing due east is ~90°', () {
    const a = LatLng(0, 0);
    const b = LatLng(0, 1);
    final br = bearingDegrees(a, b);
    expect(br, closeTo(90, 0.5));
  });

  test('VMG: heading straight at mark equals SOG', () {
    final v = vmgMs(5.0, 45.0, 45.0);
    expect(v, closeTo(5.0, 1e-9));
  });

  test('VMG: perpendicular heading is zero', () {
    final v = vmgMs(5.0, 0.0, 90.0);
    expect(v.abs(), closeTo(0, 1e-9));
  });

  test('VMG: sailing away is negative', () {
    final v = vmgMs(5.0, 180.0, 0.0);
    expect(v, closeTo(-5.0, 1e-9));
  });

  test('compass shorthand', () {
    expect(compass(0), 'N');
    expect(compass(90), 'E');
    expect(compass(180), 'S');
    expect(compass(270), 'W');
  });
}
