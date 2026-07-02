import 'package:flutter_test/flutter_test.dart';

import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/services/course_file.dart';
import 'package:sail_race_computer/utils/geo.dart';

void main() {
  group('CourseFile', () {
    final sample = Course(name: 'Test Course', buoys: [
      Buoy(name: 'A', position: const LatLng(10, 20), roundingRadiusM: 30),
      Buoy(name: 'B', position: const LatLng(11, 21)),
    ]);

    test('round-trips through v2 encode/decode', () {
      final json = CourseFile.encode(sample, notes: 'hi');
      final decoded = CourseFile.decode(json);
      expect(decoded.name, sample.name);
      expect(decoded.buoys.length, 2);
      expect(decoded.buoys[0].name, 'A');
      expect(decoded.buoys[0].position.lat, 10);
      expect(decoded.buoys[0].position.lng, 20);
      expect(decoded.buoys[0].roundingRadiusM, 30);
      expect(decoded.buoys[1].roundingRadiusM, 25); // default
      expect(CourseFile.decodeBundle(json).version, 2);
    });

    test('decodes legacy v1 files', () {
      final decoded = CourseFile.decode(
        '''
        {
          "format": "sail-race-course",
          "version": 1,
          "name": "Legacy",
          "buoys": [
            {"name": "Start", "lat": 41.8, "lng": -87.5}
          ]
        }
        ''',
      );
      expect(decoded.name, 'Legacy');
      expect(decoded.buoys.single.name, 'Start');
      expect(decoded.buoys.single.roundingRadiusM, 25);
    });

    test('decodes v2 route shorthand with reusable buoys', () {
      final bundle = CourseFile.decodeBundle(
        '''
        {
          "format": "sail-race-course",
          "version": 2,
          "name": "Series",
          "buoys": [
            {"id": "sa7", "name": "SA7", "lat": 41.852833, "lng": -87.556833},
            {"id": "1", "name": "Mark 1", "lat": 41.871, "lng": -87.556833}
          ],
          "courses": [
            {
              "id": "L1",
              "name": "Long Course 1",
              "type": "Long",
              "distanceNm": 5.37,
              "route": ["sa7", "1", "sa7"]
            }
          ]
        }
        ''',
      );
      expect(bundle.name, 'Series');
      expect(bundle.courses, hasLength(1));
      final imported = bundle.courses.single;
      expect(imported.name, 'Long Course 1');
      expect(imported.summary, 'L1 · Long · 5.37 NM');
      expect(imported.course.buoys, hasLength(3));
      expect(imported.course.buoys.first.name, 'SA7');
      expect(imported.course.buoys.last.name, 'SA7');
    });

    test('decodes v2 turns and decodeAll returns each course', () {
      final courses = CourseFile.decodeAll(
        '''
        {
          "format": "sail-race-course",
          "version": 2,
          "name": "Beer Can Series",
          "buoys": [
            {"id": "sa7", "name": "SA7", "lat": 41.852833, "lng": -87.556833},
            {"id": "1", "name": "Mark 1", "lat": 41.871, "lng": -87.556833},
            {"id": "8", "name": "Mark 8", "lat": 41.865667, "lng": -87.574}
          ],
          "courses": [
            {
              "id": "S1",
              "name": "Short Course 1",
              "turns": [
                {"buoyId": "sa7", "role": "start", "headingToNext": 0},
                {"buoyId": "1", "role": "round", "rounding": "PORT"},
                {"buoyId": "8", "role": "round", "rounding": "PORT"},
                {"buoyId": "sa7", "role": "finish"}
              ]
            },
            {
              "id": "S2",
              "name": "Short Course 2",
              "route": ["sa7", "8", "1", "sa7"],
              "headings": [45, 180, 225]
            }
          ]
        }
        ''',
      );
      expect(courses, hasLength(2));
      expect(courses.first.name, 'Short Course 1 (S1)');
      expect(courses.first.buoys, hasLength(4));
      expect(courses.last.name, 'Short Course 2 (S2)');
    });

    test('decode rejects multi-course files without a selection', () {
      expect(
        () => CourseFile.decode(
          '''
          {
            "format": "sail-race-course",
            "version": 2,
            "name": "Series",
            "buoys": [
              {"id": "a", "name": "A", "lat": 10, "lng": 20}
            ],
            "courses": [
              {"id": "one", "route": ["a"]},
              {"id": "two", "route": ["a"]}
            ]
          }
          ''',
        ),
        throwsA(isA<CourseFileException>()),
      );
    });

    test('rejects unknown format', () {
      expect(
          () => CourseFile.decode(
              '{"format":"other","version":1,"name":"x","buoys":[]}'),
          throwsA(isA<CourseFileException>()));
    });

    test('rejects unsupported version', () {
      expect(
          () => CourseFile.decode(
              '{"format":"sail-race-course","version":99,"name":"x","buoys":[]}'),
          throwsA(isA<CourseFileException>()));
    });

    test('rejects invalid lat/lng', () {
      expect(
          () => CourseFile.decode(
              '{"format":"sail-race-course","version":1,"name":"x","buoys":[{"name":"a","lat":200,"lng":0}]}'),
          throwsA(isA<CourseFileException>()));
    });

    test('rejects v2 route references to unknown buoys', () {
      expect(
        () => CourseFile.decodeBundle(
          '''
          {
            "format": "sail-race-course",
            "version": 2,
            "name": "Series",
            "buoys": [],
            "courses": [
              {"id": "one", "route": ["missing"]}
            ]
          }
          ''',
        ),
        throwsA(isA<CourseFileException>()),
      );
    });

    test('rejects non-JSON', () {
      expect(() => CourseFile.decode('not json at all'),
          throwsA(isA<CourseFileException>()));
    });

    test('suggested filename is slugified', () {
      final c = Course(name: 'My  Cool / Race!!', buoys: []);
      expect(CourseFile.suggestedFileName(c), 'my-cool-race.srcourse.json');
    });
  });
}
