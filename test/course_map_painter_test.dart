import 'package:flutter_test/flutter_test.dart';

import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/utils/geo.dart';
import 'package:sail_race_computer/widgets/course_map_painter.dart';

const _sa7 = LatLng(41.852833, -87.556833);
const _mark1 = LatLng(41.871, -87.556833);
const _mark2 = LatLng(41.865667, -87.5395);

/// Maps degrees to canvas pixels 1:1 so expected offsets stay readable.
Offset _project(LatLng p) => Offset(p.lng * 10000, -p.lat * 10000);

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

  group('buoyLabelGroups', () {
    test('labels each distinct mark with its 1-based position', () {
      final course = Course(
        name: 'Triangle',
        buoys: [
          Buoy(name: 'SA7 Start/Finish', position: _sa7),
          Buoy(name: 'Mark 1', position: _mark1),
          Buoy(name: 'Mark 2', position: _mark2),
        ],
      );

      final groups = buoyLabelGroups(course, _project);

      expect(groups.map((g) => g.text), [
        '1. SA7 Start/Finish',
        '2. Mark 1',
        '3. Mark 2',
      ]);
      expect(groups.first.at, _project(_sa7));
    });

    test('merges marks that project onto the same point', () {
      final course = Course(
        name: 'Windward-leeward',
        buoys: [
          Buoy(name: 'SA7 Start/Finish', position: _sa7),
          Buoy(name: 'Mark 1', position: _mark1),
          Buoy(name: 'SA7 Finish', position: _sa7),
        ],
      );

      final groups = buoyLabelGroups(course, _project);

      expect(groups, hasLength(2));
      // The merged label keeps the first mark's name and lists both ordinals.
      expect(groups.first.text, '1·3. SA7 Start/Finish');
      expect(groups.last.text, '2. Mark 1');
    });

    test('merges marks that are merely close on screen', () {
      final course = Course(
        name: 'Gate',
        buoys: [
          Buoy(name: 'Gate', position: _sa7),
          Buoy(name: 'Gate pin', position: _sa7),
        ],
      );

      // Nudge the second projection 3px away — inside the default 6px radius.
      var call = 0;
      Offset project(LatLng p) =>
          _project(p) + (call++ == 0 ? Offset.zero : const Offset(3, 0));

      expect(buoyLabelGroups(course, project).single.text, '1·2. Gate');
    });

    test('keeps marks apart when they exceed the merge radius', () {
      final course = Course(
        name: 'Gate',
        buoys: [
          Buoy(name: 'Gate', position: _sa7),
          Buoy(name: 'Gate pin', position: _sa7),
        ],
      );

      var call = 0;
      Offset project(LatLng p) =>
          _project(p) + (call++ == 0 ? Offset.zero : const Offset(30, 0));

      final groups = buoyLabelGroups(course, project, mergeRadiusPx: 6);

      expect(groups.map((g) => g.text), ['1. Gate', '2. Gate pin']);
    });

    test('returns nothing for an empty course', () {
      final course = Course(name: 'Empty', buoys: []);

      expect(buoyLabelGroups(course, _project), isEmpty);
    });
  });
}
