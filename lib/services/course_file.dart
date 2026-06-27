import 'dart:convert';
import 'dart:typed_data';
import '../models/course.dart';
import '../utils/geo.dart';

/// File format for shareable race courses.
///
/// Wire format (.srcourse.json):
/// ```json
/// {
///   "format": "sail-race-course",
///   "version": 1,
///   "name": "Demo Chicago",
///   "createdAt": "2026-06-04T12:00:00Z",
///   "notes": "optional free text",
///   "buoys": [
///     {"name": "Windward", "lat": 41.892, "lng": -87.6101, "roundingRadiusM": 25}
///   ]
/// }
/// ```
///
/// `format` and `version` are required and validated on load so future
/// versions can be migrated or rejected cleanly.
class CourseFile {
  static const String formatId = 'sail-race-course';
  static const int currentVersion = 1;
  static const String fileExtension = 'srcourse';
  static const String mimeType = 'application/json';

  /// Serialize a [Course] to the canonical JSON string (pretty-printed,
  /// 2-space indent — diff-friendly for sharing via git/email).
  static String encode(
    Course course, {
    String? notes,
    DateTime? createdAt,
  }) {
    final map = <String, dynamic>{
      'format': formatId,
      'version': currentVersion,
      'name': course.name,
      'createdAt': (createdAt ?? DateTime.now().toUtc()).toIso8601String(),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'buoys': course.buoys
          .map((b) => {
                'name': b.name,
                'lat': b.position.lat,
                'lng': b.position.lng,
                'roundingRadiusM': b.roundingRadiusM,
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Parse a JSON string into a [Course]. Throws [CourseFileException] on
  /// any structural problem.
  static Course decode(String source) {
    final dynamic raw;
    try {
      raw = jsonDecode(source);
    } catch (e) {
      throw CourseFileException('Not valid JSON: $e');
    }
    if (raw is! Map<String, dynamic>) {
      throw const CourseFileException('Root must be a JSON object.');
    }
    final format = raw['format'];
    if (format != formatId) {
      throw CourseFileException(
          'Unexpected "format": $format (want "$formatId").');
    }
    final version = raw['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      throw CourseFileException(
          'Unsupported "version": $version (this build understands 1..$currentVersion).');
    }
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const CourseFileException('"name" must be a non-empty string.');
    }
    final buoysRaw = raw['buoys'];
    if (buoysRaw is! List) {
      throw const CourseFileException('"buoys" must be an array.');
    }
    final buoys = <Buoy>[];
    for (var i = 0; i < buoysRaw.length; i++) {
      final b = buoysRaw[i];
      if (b is! Map<String, dynamic>) {
        throw CourseFileException('Buoy #${i + 1} is not an object.');
      }
      final bn = b['name'];
      final lat = b['lat'];
      final lng = b['lng'];
      final r = b['roundingRadiusM'] ?? 25.0;
      if (bn is! String || bn.trim().isEmpty) {
        throw CourseFileException('Buoy #${i + 1} missing "name".');
      }
      if (lat is! num || lat < -90 || lat > 90) {
        throw CourseFileException(
            'Buoy "$bn" has invalid "lat": $lat (expected -90..90).');
      }
      if (lng is! num || lng < -180 || lng > 180) {
        throw CourseFileException(
            'Buoy "$bn" has invalid "lng": $lng (expected -180..180).');
      }
      if (r is! num || r <= 0) {
        throw CourseFileException(
            'Buoy "$bn" has invalid "roundingRadiusM": $r (must be > 0).');
      }
      buoys.add(Buoy(
        name: bn.trim(),
        position: LatLng(lat.toDouble(), lng.toDouble()),
        roundingRadiusM: r.toDouble(),
      ));
    }
    return Course(name: name.trim(), buoys: buoys);
  }

  static Uint8List encodeBytes(Course c, {String? notes}) =>
      Uint8List.fromList(utf8.encode(encode(c, notes: notes)));

  /// Suggest a filename like "demo-course.srcourse.json".
  static String suggestedFileName(Course c) {
    final slug = c.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final base = slug.isEmpty ? 'course' : slug;
    return '$base.$fileExtension';
  }
}

class CourseFileException implements Exception {
  final String message;
  const CourseFileException(this.message);
  @override
  String toString() => message;
}
