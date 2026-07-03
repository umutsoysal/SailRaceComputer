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
///   "version": 2,
///   "name": "Demo Chicago",
///   "createdAt": "2026-06-04T12:00:00Z",
///   "notes": "optional free text",
///   "buoys": [
///     {
///       "id": "windward",
///       "name": "Windward",
///       "lat": 41.892,
///       "lng": -87.6101,
///       "roundingRadiusM": 25
///     }
///   ],
///   "courses": [
///     {
///       "id": "demo",
///       "name": "Demo Chicago",
///       "route": ["windward"]
///     }
///   ]
/// }
/// ```
///
/// `format` and `version` are required and validated on load so future
/// versions can be migrated or rejected cleanly.
class CourseFile {
  static const String formatId = 'sail-race-course';
  static const int currentVersion = 2;
  static const String fileExtension = 'srcourse';
  static const String mimeType = 'application/json';

  /// Serialize a [Course] to the canonical JSON string (pretty-printed,
  /// 2-space indent — diff-friendly for sharing via git/email).
  static String encode(
    Course course, {
    String? notes,
    DateTime? createdAt,
  }) {
    final catalog = _buildCatalog(course.buoys);
    final map = <String, dynamic>{
      'format': formatId,
      'version': currentVersion,
      'name': course.name,
      'createdAt': (createdAt ?? DateTime.now().toUtc()).toIso8601String(),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'units': {
        'distance': 'nm',
        'roundingRadius': 'm',
      },
      'buoys': catalog.buoys,
      'courses': [
        {
          'id': _allocateId(_slugify(course.name), <String>{}),
          'name': course.name,
          'route': catalog.route,
        },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Parse a JSON string into an [ImportedCourseBundle]. Throws
  /// [CourseFileException] on any structural problem.
  static ImportedCourseBundle decodeBundle(String source) {
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
    final versionValue = version;
    switch (versionValue) {
      case 1:
        return _decodeV1(raw, name.trim(), versionValue);
      case 2:
        return _decodeV2(raw, name.trim(), versionValue);
      default:
        throw CourseFileException(
            'Unsupported "version": $version (this build understands 1..$currentVersion).');
    }
  }

  /// Parse a JSON string into one or more [Course]s.
  static List<Course> decodeAll(String source) =>
      decodeBundle(source).courses.map((e) => e.course).toList();

  /// Parse a JSON string into a single [Course].
  ///
  /// Multi-course v2 files must be selected with [decodeBundle] or [decodeAll].
  static Course decode(String source) {
    final bundle = decodeBundle(source);
    if (bundle.courses.isEmpty) {
      throw const CourseFileException('File does not contain any courses.');
    }
    if (bundle.courses.length > 1) {
      throw CourseFileException(
        'File contains ${bundle.courses.length} courses. Choose one before loading it into the app.',
      );
    }
    return bundle.courses.single.course;
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

  static ImportedCourseBundle _decodeV1(
    Map<String, dynamic> raw,
    String documentName,
    int version,
  ) {
    final buoysRaw = raw['buoys'];
    if (buoysRaw is! List) {
      throw const CourseFileException('"buoys" must be an array.');
    }
    final buoys = <Buoy>[];
    for (var i = 0; i < buoysRaw.length; i++) {
      buoys.add(_decodeLegacyBuoy(buoysRaw[i], i));
    }
    return ImportedCourseBundle(
      name: documentName,
      version: version,
      courses: [
        ImportedCourseDefinition(
          id: _allocateId(_slugify(documentName), <String>{}),
          name: documentName,
          course: Course(name: documentName, buoys: buoys),
        ),
      ],
    );
  }

  static ImportedCourseBundle _decodeV2(
    Map<String, dynamic> raw,
    String documentName,
    int version,
  ) {
    final buoysRaw = raw['buoys'];
    if (buoysRaw is! List) {
      throw const CourseFileException('"buoys" must be an array.');
    }

    final buoyCatalog = <String, Buoy>{};
    for (var i = 0; i < buoysRaw.length; i++) {
      final b = buoysRaw[i];
      if (b is! Map) {
        throw CourseFileException('Buoy #${i + 1} is not an object.');
      }
      final obj = Map<String, dynamic>.from(b);
      final id = obj['id'];
      if (id is! String || id.trim().isEmpty) {
        throw CourseFileException('Buoy #${i + 1} missing "id".');
      }
      final trimmedId = id.trim();
      if (buoyCatalog.containsKey(trimmedId)) {
        throw CourseFileException('Duplicate buoy id "$trimmedId".');
      }
      buoyCatalog[trimmedId] = _decodeCatalogBuoy(obj, i + 1);
    }

    final coursesRaw = raw['courses'];
    if (coursesRaw is! List) {
      throw const CourseFileException('"courses" must be an array.');
    }
    if (coursesRaw.isEmpty) {
      throw const CourseFileException(
          '"courses" must contain at least one course.');
    }

    final usedIds = <String>{};
    final courses = <ImportedCourseDefinition>[];
    for (var i = 0; i < coursesRaw.length; i++) {
      final item = coursesRaw[i];
      if (item is! Map) {
        throw CourseFileException('Course #${i + 1} is not an object.');
      }
      final obj = Map<String, dynamic>.from(item);
      final id = obj['id'];
      if (id is! String || id.trim().isEmpty) {
        throw CourseFileException('Course #${i + 1} missing "id".');
      }
      final trimmedId = id.trim();
      if (!usedIds.add(trimmedId)) {
        throw CourseFileException('Duplicate course id "$trimmedId".');
      }

      final name = _courseDisplayName(
        obj['name'],
        trimmedId,
        appendId: coursesRaw.length > 1,
      );
      final routeIds = _decodeRouteIds(obj, trimmedId);
      final buoys = routeIds.map((buoyId) {
        final spec = buoyCatalog[buoyId];
        if (spec == null) {
          throw CourseFileException(
            'Course "$trimmedId" references unknown buoy id "$buoyId".',
          );
        }
        return Buoy(
          name: spec.name,
          position: LatLng(spec.position.lat, spec.position.lng),
          roundingRadiusM: spec.roundingRadiusM,
        );
      }).toList();

      courses.add(
        ImportedCourseDefinition(
          id: trimmedId,
          name: name,
          course: Course(name: name, buoys: buoys),
          type: _optionalTrimmedString(obj['type']),
          fleet: _optionalTrimmedString(obj['fleet']),
          distanceNm: _optionalPositiveNumber(
            obj['distanceNm'],
            'Course "$trimmedId" has invalid "distanceNm": ${obj['distanceNm']} (must be > 0).',
          ),
        ),
      );
    }

    return ImportedCourseBundle(
      name: documentName,
      version: version,
      courses: courses,
    );
  }

  static Buoy _decodeLegacyBuoy(dynamic raw, int index) {
    if (raw is! Map) {
      throw CourseFileException('Buoy #${index + 1} is not an object.');
    }
    return _decodeCatalogBuoy(
      Map<String, dynamic>.from(raw),
      index + 1,
      requireId: false,
    );
  }

  static Buoy _decodeCatalogBuoy(
    Map<String, dynamic> raw,
    int displayIndex, {
    bool requireId = true,
  }) {
    if (requireId) {
      final id = raw['id'];
      if (id is! String || id.trim().isEmpty) {
        throw CourseFileException('Buoy #$displayIndex missing "id".');
      }
    }
    final bn = raw['name'];
    final lat = raw['lat'];
    final lng = raw['lng'];
    final r = raw['roundingRadiusM'] ?? 25.0;
    if (bn is! String || bn.trim().isEmpty) {
      throw CourseFileException('Buoy #$displayIndex missing "name".');
    }
    if (lat is! num || lat < -90 || lat > 90) {
      throw CourseFileException(
          'Buoy "${bn.trim()}" has invalid "lat": $lat (expected -90..90).');
    }
    if (lng is! num || lng < -180 || lng > 180) {
      throw CourseFileException(
          'Buoy "${bn.trim()}" has invalid "lng": $lng (expected -180..180).');
    }
    if (r is! num || r <= 0) {
      throw CourseFileException(
          'Buoy "${bn.trim()}" has invalid "roundingRadiusM": $r (must be > 0).');
    }
    return Buoy(
      name: bn.trim(),
      position: LatLng(lat.toDouble(), lng.toDouble()),
      roundingRadiusM: r.toDouble(),
    );
  }

  static List<String> _decodeRouteIds(
    Map<String, dynamic> raw,
    String courseId,
  ) {
    final turns = raw['turns'];
    if (turns != null) {
      if (turns is! List) {
        throw CourseFileException('Course "$courseId" has invalid "turns".');
      }
      return turns.asMap().entries.map((entry) {
        final value = entry.value;
        if (value is! Map) {
          throw CourseFileException(
            'Course "$courseId" turn #${entry.key + 1} is not an object.',
          );
        }
        final obj = Map<String, dynamic>.from(value);
        final buoyId = obj['buoyId'];
        if (buoyId is! String || buoyId.trim().isEmpty) {
          throw CourseFileException(
            'Course "$courseId" turn #${entry.key + 1} missing "buoyId".',
          );
        }
        final role = obj['role'];
        if (role != null &&
            (role is! String ||
                !const {'start', 'round', 'finish'}.contains(role))) {
          throw CourseFileException(
            'Course "$courseId" turn #${entry.key + 1} has invalid "role": $role.',
          );
        }
        final rounding = obj['rounding'];
        if (rounding != null &&
            (rounding is! String ||
                !const {'PORT', 'STARBOARD'}.contains(rounding))) {
          throw CourseFileException(
            'Course "$courseId" turn #${entry.key + 1} has invalid "rounding": $rounding.',
          );
        }
        final headingToNext = obj['headingToNext'];
        if (headingToNext != null &&
            (headingToNext is! num ||
                headingToNext < 0 ||
                headingToNext > 360)) {
          throw CourseFileException(
            'Course "$courseId" turn #${entry.key + 1} has invalid "headingToNext": $headingToNext.',
          );
        }
        return buoyId.trim();
      }).toList();
    }

    final route = raw['route'];
    if (route is! List) {
      throw CourseFileException(
        'Course "$courseId" must define either "turns" or "route".',
      );
    }
    final routeIds = route.asMap().entries.map((entry) {
      final buoyId = entry.value;
      if (buoyId is! String || buoyId.trim().isEmpty) {
        throw CourseFileException(
          'Course "$courseId" route item #${entry.key + 1} is invalid.',
        );
      }
      return buoyId.trim();
    }).toList();

    final headings = raw['headings'];
    if (headings != null) {
      if (headings is! List) {
        throw CourseFileException('Course "$courseId" has invalid "headings".');
      }
      if (headings.length != routeIds.length - (routeIds.isEmpty ? 0 : 1)) {
        throw CourseFileException(
          'Course "$courseId" has ${headings.length} headings for ${routeIds.length} route points.',
        );
      }
      for (var i = 0; i < headings.length; i++) {
        final heading = headings[i];
        if (heading is! num || heading < 0 || heading > 360) {
          throw CourseFileException(
            'Course "$courseId" heading #${i + 1} is invalid: $heading.',
          );
        }
      }
    }

    final rounding = raw['rounding'];
    if (rounding != null &&
        (rounding is! String ||
            !const {'PORT', 'STARBOARD'}.contains(rounding))) {
      throw CourseFileException(
        'Course "$courseId" has invalid "rounding": $rounding.',
      );
    }
    return routeIds;
  }

  static String _courseDisplayName(
    dynamic rawName,
    String courseId, {
    required bool appendId,
  }) {
    final name = _optionalTrimmedString(rawName);
    if (name == null) return courseId;
    if (!appendId) return name;
    if (name.contains('($courseId)')) return name;
    return '$name ($courseId)';
  }

  static String? _optionalTrimmedString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _optionalPositiveNumber(dynamic value, String error) {
    if (value == null) return null;
    if (value is! num || value <= 0) {
      throw CourseFileException(error);
    }
    return value.toDouble();
  }

  static _EncodedCatalog _buildCatalog(List<Buoy> buoys) {
    final uniqueByKey = <String, String>{};
    final usedIds = <String>{};
    final encodedBuoys = <Map<String, dynamic>>[];
    final route = <String>[];

    for (final buoy in buoys) {
      final key = [
        buoy.name.trim(),
        buoy.position.lat.toStringAsFixed(6),
        buoy.position.lng.toStringAsFixed(6),
        buoy.roundingRadiusM.toStringAsFixed(2),
      ].join('|');
      var id = uniqueByKey[key];
      if (id == null) {
        id = _allocateId(_slugify(buoy.name), usedIds);
        uniqueByKey[key] = id;
        encodedBuoys.add({
          'id': id,
          'name': buoy.name,
          'lat': buoy.position.lat,
          'lng': buoy.position.lng,
          'roundingRadiusM': buoy.roundingRadiusM,
        });
      }
      route.add(id);
    }

    return _EncodedCatalog(buoys: encodedBuoys, route: route);
  }

  static String _slugify(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static String _allocateId(String base, Set<String> used) {
    final seed = base.isEmpty ? 'course' : base;
    if (!used.contains(seed)) return seed;
    var suffix = 2;
    while (used.contains('$seed-$suffix')) {
      suffix++;
    }
    return '$seed-$suffix';
  }
}

class CourseFileException implements Exception {
  final String message;
  const CourseFileException(this.message);
  @override
  String toString() => message;
}

class ImportedCourseBundle {
  const ImportedCourseBundle({
    required this.name,
    required this.version,
    required this.courses,
  });

  final String name;
  final int version;
  final List<ImportedCourseDefinition> courses;
}

class ImportedCourseDefinition {
  const ImportedCourseDefinition({
    required this.id,
    required this.name,
    required this.course,
    this.type,
    this.fleet,
    this.distanceNm,
  });

  final String id;
  final String name;
  final Course course;
  final String? type;
  final String? fleet;
  final double? distanceNm;

  String? get summary {
    final parts = <String>[
      id,
      ?type,
      if (distanceNm != null)
        '${distanceNm!.toStringAsFixed(distanceNm! % 1 == 0 ? 0 : 2)} NM',
      ?fleet,
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }
}

class _EncodedCatalog {
  const _EncodedCatalog({
    required this.buoys,
    required this.route,
  });

  final List<Map<String, dynamic>> buoys;
  final List<String> route;
}
