import 'package:flutter_test/flutter_test.dart';

import 'package:sail_race_computer/widgets/course_map_painter.dart';

void main() {
  test('formats scale bar labels in nautical miles', () {
    expect(formatScaleBarNm(0.05), '0.05 NM');
    expect(formatScaleBarNm(0.5), '0.5 NM');
    expect(formatScaleBarNm(2), '2.0 NM');
    expect(formatScaleBarNm(10), '10 NM');
  });

  test('chooses a nice nautical mile scale bar near the target width', () {
    const pixelsPerMeter = 0.1;
    final choice = chooseScaleBarNm(
      pixelsPerMeter: pixelsPerMeter,
      targetWidthPx: 100,
    );

    expect(choice, anyOf(0.5, 1.0));
    final widthPx = choice * 1852.0 * pixelsPerMeter;
    expect(widthPx, greaterThanOrEqualTo(100));
    expect(widthPx, lessThan(220));
  });
}
