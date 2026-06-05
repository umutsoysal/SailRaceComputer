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

    test('round-trips through encode/decode', () {
      final json = CourseFile.encode(sample, notes: 'hi');
      final decoded = CourseFile.decode(json);
      expect(decoded.name, sample.name);
      expect(decoded.buoys.length, 2);
      expect(decoded.buoys[0].name, 'A');
      expect(decoded.buoys[0].position.lat, 10);
      expect(decoded.buoys[0].position.lng, 20);
      expect(decoded.buoys[0].roundingRadiusM, 30);
      expect(decoded.buoys[1].roundingRadiusM, 25); // default
    });

    test('rejects unknown format', () {
      expect(() => CourseFile.decode('{"format":"other","version":1,"name":"x","buoys":[]}'),
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
