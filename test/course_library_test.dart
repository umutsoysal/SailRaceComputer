import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/services/course_library.dart';
import 'package:sail_race_computer/utils/geo.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'sail_race_library_v1';

Course _course(String name) => Course(
  name: name,
  buoys: [
    Buoy(name: 'Start', position: const LatLng(41.85, -87.55)),
    Buoy(name: 'Windward', position: const LatLng(41.87, -87.55)),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('CourseLibrary bundled', () {
    test('lists every course inside every bundled asset', () async {
      final entries = await CourseLibrary().listBundled();

      expect(entries, isNotEmpty);
      expect(entries.every((e) => e.isBundled), isTrue);
      expect(entries.every((e) => e.id.startsWith('asset:')), isTrue);
      expect(entries.every((e) => e.buoyCount > 0), isTrue);
    });

    test('assigns stable unique ids per bundled course', () async {
      final entries = await CourseLibrary().listBundled();
      final ids = entries.map((e) => e.id).toSet();

      expect(ids.length, entries.length);

      final again = await CourseLibrary().listBundled();
      expect(
        again.map((e) => e.id).toList(),
        entries.map((e) => e.id).toList(),
      );
    });

    test('groups multi-course MORF bundles by course type', () async {
      final entries = await CourseLibrary().listBundled();
      final morf = entries.where(
        (e) => e.groupName?.startsWith('MORF') == true,
      );

      expect(morf, isNotEmpty);
      expect(morf.every((e) => e.groupName!.contains('·')), isTrue);
    });
  });

  group('CourseLibrary saved', () {
    test('starts empty and round-trips a saved course', () async {
      final library = CourseLibrary();
      expect(await library.listSaved(), isEmpty);

      final saved = await library.save(_course('Tuesday Night'));
      expect(saved.id, startsWith('saved:'));
      expect(saved.source, CourseSource.saved);

      final listed = await library.listSaved();
      expect(listed.single.name, 'Tuesday Night');
      expect(listed.single.buoyCount, 2);
      expect(listed.single.isBundled, isFalse);
    });

    test('overwrites in place when saving with an existing id', () async {
      final library = CourseLibrary();
      final first = await library.save(_course('Draft'));
      await library.save(_course('Renamed'), id: first.id);

      final listed = await library.listSaved();
      expect(listed, hasLength(1));
      expect(listed.single.name, 'Renamed');
      expect(listed.single.id, first.id);
    });

    test('listAll returns bundled courses before saved ones', () async {
      final library = CourseLibrary();
      await library.save(_course('Mine'));

      final all = await library.listAll();
      final firstSavedIndex = all.indexWhere((e) => !e.isBundled);

      expect(firstSavedIndex, greaterThan(0));
      expect(all.sublist(0, firstSavedIndex).every((e) => e.isBundled), isTrue);
      expect(all.last.name, 'Mine');
    });

    test('returns an empty list when stored JSON is corrupt', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _prefsKey: 'not json',
      });

      expect(await CourseLibrary().listSaved(), isEmpty);
    });
  });

  group('CourseLibrary remove', () {
    test('removes a saved course and reports success', () async {
      final library = CourseLibrary();
      final saved = await library.save(_course('Scratch'));

      expect(await library.remove(saved.id), isTrue);
      expect(await library.listSaved(), isEmpty);
    });

    test('refuses to remove bundled entries', () async {
      final library = CourseLibrary();
      final bundled = (await library.listBundled()).first;

      expect(await library.remove(bundled.id), isFalse);
      expect(await library.listBundled(), isNotEmpty);
    });

    test('reports failure for an unknown saved id', () async {
      final library = CourseLibrary();
      await library.save(_course('Keep me'));

      expect(await library.remove('saved:does-not-exist'), isFalse);
      expect(await library.listSaved(), hasLength(1));
    });

    test('reports failure when nothing has been saved yet', () async {
      expect(await CourseLibrary().remove('saved:anything'), isFalse);
    });

    test('leaves other entries untouched', () async {
      final library = CourseLibrary();
      final a = await library.save(_course('A'));
      await library.save(_course('B'));

      expect(await library.remove(a.id), isTrue);

      final listed = await library.listSaved();
      expect(listed.map((e) => e.name), ['B']);

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(_prefsKey)!) as List<dynamic>;
      expect(stored, hasLength(1));
    });
  });
}
