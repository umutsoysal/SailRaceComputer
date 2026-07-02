import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/course.dart';
import 'course_file.dart';

/// Where a course came from.
enum CourseSource { bundled, saved }

/// One entry in the library — either a bundled asset or a user-saved course.
class CourseEntry {
  CourseEntry({
    required this.id,
    required this.source,
    required this.course,
    this.groupName,
    this.details,
  });

  /// Stable identifier:
  /// - `asset:<asset path>` for bundled courses
  /// - `saved:<uuid-ish>` for user-saved courses
  final String id;
  final CourseSource source;
  final Course course;
  final String? groupName;
  final String? details;

  String get name => course.name;
  int get buoyCount => course.buoys.length;
  bool get isBundled => source == CourseSource.bundled;
}

/// Lists and stores race courses available to the app.
///
/// - Bundled courses are auto-discovered from `assets/courses/*.json`
///   (no code change needed when you add a new file).
/// - Saved courses are persisted in `SharedPreferences` and grow as the
///   user imports / saves new ones.
class CourseLibrary {
  static const _key = 'sail_race_library_v1';
  static const _assetDir = 'assets/courses/';

  Future<List<CourseEntry>> listBundled() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final keys = manifest
          .listAssets()
          .where((k) => k.startsWith(_assetDir) && k.endsWith('.json'))
          .toList()
        ..sort();
      final entries = <CourseEntry>[];
      for (final k in keys) {
        try {
          final raw = await rootBundle.loadString(k);
          final bundle = CourseFile.decodeBundle(raw);
          for (final imported in bundle.courses) {
            entries.add(CourseEntry(
              id: 'asset:$k#${imported.id}',
              source: CourseSource.bundled,
              course: imported.course,
              groupName: bundle.courses.length > 1 ? bundle.name : null,
              details: imported.summary,
            ));
          }
        } catch (_) {
          // Skip malformed asset; don't break the library.
        }
      }
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<List<CourseEntry>> listSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((item) {
        final m = item as Map<String, dynamic>;
        return CourseEntry(
          id: m['id'] as String,
          source: CourseSource.saved,
          course: CourseFile.decode(m['json'] as String),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<CourseEntry>> listAll() async {
    final bundled = await listBundled();
    final saved = await listSaved();
    return [...bundled, ...saved];
  }

  /// Saves a copy of [course] into the library. If [id] is provided and
  /// matches an existing saved entry, that entry is overwritten; otherwise a
  /// new ID is allocated.
  Future<CourseEntry> save(Course course, {String? id}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final list = (raw == null || raw.isEmpty)
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .toList();

    final newId = id ?? 'saved:${DateTime.now().microsecondsSinceEpoch}';
    final entryJson = CourseFile.encode(course);
    final idx = list.indexWhere((m) => m['id'] == newId);
    final payload = {'id': newId, 'json': entryJson};
    if (idx >= 0) {
      list[idx] = payload;
    } else {
      list.add(payload);
    }
    await prefs.setString(_key, jsonEncode(list));
    return CourseEntry(
      id: newId,
      source: CourseSource.saved,
      course: course,
    );
  }

  /// Removes a saved course by [id]. Bundled entries cannot be removed.
  Future<bool> remove(String id) async {
    if (!id.startsWith('saved:')) return false;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return false;
    final list = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .toList();
    final before = list.length;
    list.removeWhere((m) => m['id'] == id);
    if (list.length == before) return false;
    await prefs.setString(_key, jsonEncode(list));
    return true;
  }
}
