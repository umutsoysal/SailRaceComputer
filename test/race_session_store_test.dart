import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sail_race_computer/services/race_session_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and reloads the last completed race with GPX output', () async {
    final store = RaceSessionStore();
    final record = RaceSessionRecord(
      courseName: 'Wednesday Series',
      startedAt: DateTime.utc(2026, 7, 2, 23, 40),
      finishedAt: DateTime.utc(2026, 7, 3),
      totalMarks: 3,
      finalMarkIndex: 2,
      completedCourse: true,
      track: [
        RaceTrackPoint(
          recordedAt: DateTime.utc(2026, 7, 2, 23, 40),
          latitude: 41.88,
          longitude: -87.62,
          accuracyM: 5,
          speedMs: 2.6,
          headingDeg: 45,
          altitudeM: 180,
        ),
        RaceTrackPoint(
          recordedAt: DateTime.utc(2026, 7, 2, 23, 45),
          latitude: 41.89,
          longitude: -87.61,
          accuracyM: 5,
          speedMs: 3.1,
          headingDeg: 60,
          altitudeM: 181,
        ),
      ],
    );

    await store.saveCompleted(record);

    final saved = await store.listSaved();
    final lastEntry = await store.loadLastEntry();
    final loaded = await store.loadLast();
    final gpx = await store.loadLastGpx();

    expect(saved, hasLength(1));
    expect(saved.single.fileName, endsWith('.gpx'));
    expect(loaded, isNotNull);
    expect(loaded!.courseName, 'Wednesday Series');
    expect(loaded.completedCourse, isTrue);
    expect(loaded.pointCount, 2);
    expect(lastEntry, isNotNull);
    expect(lastEntry!.title, 'Wednesday Series');
    expect(gpx, isNotNull);
    expect(gpx, contains('<trkpt lat="41.88" lon="-87.62">'));
    expect(gpx, contains('<name>Wednesday Series</name>'));
  });

  test('removes saved races from the library', () async {
    final store = RaceSessionStore();
    final first = RaceSessionRecord(
      courseName: 'One',
      startedAt: DateTime.utc(2026, 7, 2, 20),
      finishedAt: DateTime.utc(2026, 7, 2, 20, 5),
      totalMarks: 2,
      finalMarkIndex: 1,
      completedCourse: true,
      track: const [],
    );
    final second = RaceSessionRecord(
      courseName: 'Two',
      startedAt: DateTime.utc(2026, 7, 2, 21),
      finishedAt: DateTime.utc(2026, 7, 2, 21, 5),
      totalMarks: 2,
      finalMarkIndex: 1,
      completedCourse: false,
      track: const [],
    );

    final firstEntry = await store.saveCompleted(first);
    await store.saveCompleted(second);
    expect(await store.listSaved(), hasLength(2));

    final removed = await store.remove(firstEntry.id);

    expect(removed, isTrue);
    final saved = await store.listSaved();
    expect(saved, hasLength(1));
    expect(saved.single.title, 'Two');
  });
}
