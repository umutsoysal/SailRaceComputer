import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RaceTrackPoint {
  const RaceTrackPoint({
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.speedMs,
    required this.headingDeg,
    required this.altitudeM,
  });

  factory RaceTrackPoint.fromPosition(Position position) {
    return RaceTrackPoint(
      recordedAt: position.timestamp.toUtc(),
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      speedMs: position.speed,
      headingDeg: position.heading,
      altitudeM: position.altitude,
    );
  }

  factory RaceTrackPoint.fromJson(Map<String, dynamic> json) {
    return RaceTrackPoint(
      recordedAt: DateTime.parse(json['recordedAt'] as String).toUtc(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyM: (json['accuracyM'] as num).toDouble(),
      speedMs: (json['speedMs'] as num).toDouble(),
      headingDeg: (json['headingDeg'] as num).toDouble(),
      altitudeM: (json['altitudeM'] as num).toDouble(),
    );
  }

  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double accuracyM;
  final double speedMs;
  final double headingDeg;
  final double altitudeM;

  Map<String, dynamic> toJson() => {
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'accuracyM': accuracyM,
    'speedMs': speedMs,
    'headingDeg': headingDeg,
    'altitudeM': altitudeM,
  };
}

class RaceSessionRecord {
  const RaceSessionRecord({
    required this.courseName,
    required this.startedAt,
    required this.finishedAt,
    required this.totalMarks,
    required this.finalMarkIndex,
    required this.completedCourse,
    required this.track,
  });

  factory RaceSessionRecord.fromJson(Map<String, dynamic> json) {
    final rawTrack = json['track'] as List<dynamic>? ?? const [];
    return RaceSessionRecord(
      courseName: json['courseName'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
      finishedAt: DateTime.parse(json['finishedAt'] as String).toUtc(),
      totalMarks: json['totalMarks'] as int,
      finalMarkIndex: json['finalMarkIndex'] as int,
      completedCourse: json['completedCourse'] as bool? ?? false,
      track: rawTrack
          .map(
            (point) => RaceTrackPoint.fromJson(
              Map<String, dynamic>.from(point as Map),
            ),
          )
          .toList(),
    );
  }

  final String courseName;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int totalMarks;
  final int finalMarkIndex;
  final bool completedCourse;
  final List<RaceTrackPoint> track;

  Duration get duration => finishedAt.difference(startedAt);
  int get pointCount => track.length;

  Map<String, dynamic> toJson() => {
    'courseName': courseName,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'totalMarks': totalMarks,
    'finalMarkIndex': finalMarkIndex,
    'completedCourse': completedCourse,
    'track': track.map((point) => point.toJson()).toList(),
  };

  String toGpx({String creator = 'Race Mate'}) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="${_xmlEscape(creator)}" xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${_xmlEscape(courseName)}</name>')
      ..writeln('    <time>${startedAt.toUtc().toIso8601String()}</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_xmlEscape(courseName)}</name>')
      ..writeln('    <trkseg>');

    for (final point in track) {
      buffer.writeln(
        '      <trkpt lat="${point.latitude}" lon="${point.longitude}">',
      );
      buffer.writeln(
        '        <time>${point.recordedAt.toUtc().toIso8601String()}</time>',
      );
      buffer.writeln('        <ele>${point.altitudeM}</ele>');
      buffer.writeln('        <speed>${point.speedMs}</speed>');
      buffer.writeln('        <course>${point.headingDeg}</course>');
      buffer.writeln('      </trkpt>');
    }

    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..write('</gpx>');

    return buffer.toString();
  }
}

class RaceSessionEntry {
  const RaceSessionEntry({
    required this.id,
    required this.fileName,
    required this.record,
    required this.gpx,
  });

  factory RaceSessionEntry.fromJson(Map<String, dynamic> json) {
    return RaceSessionEntry(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      record: RaceSessionRecord.fromJson(
        Map<String, dynamic>.from(json['record'] as Map),
      ),
      gpx: json['gpx'] as String,
    );
  }

  final String id;
  final String fileName;
  final RaceSessionRecord record;
  final String gpx;

  String get title => record.courseName;

  String get subtitle {
    final started = record.startedAt.toLocal();
    final date =
        _two(started.month) +
        '/' +
        _two(started.day) +
        '/' +
        started.year.toString();
    final time = _two(started.hour) + ':' + _two(started.minute);
    final duration = record.duration;
    final durationText = duration.inHours > 0
        ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m'
        : '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    final completion = record.completedCourse ? 'finished' : 'saved early';
    return '$date $time · $durationText · ${record.pointCount} pts · $completion';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'record': record.toJson(),
    'gpx': gpx,
  };
}

class RaceSessionStore {
  static const _libraryKey = 'sail_race_session_library_v2';
  static const _lastSessionKey = 'sail_race_last_session_v1';
  static const _lastGpxKey = 'sail_race_last_session_gpx_v1';

  Future<RaceSessionEntry> saveCompleted(RaceSessionRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await listSaved();
    final entry = RaceSessionEntry(
      id: 'race:${DateTime.now().microsecondsSinceEpoch}',
      fileName: _suggestedFileName(record),
      record: record,
      gpx: record.toGpx(),
    );
    final updated = [entry, ...entries];
    await prefs.setString(
      _libraryKey,
      jsonEncode(updated.map((saved) => saved.toJson()).toList()),
    );
    await prefs.setString(_lastSessionKey, jsonEncode(record.toJson()));
    await prefs.setString(_lastGpxKey, entry.gpx);
    return entry;
  }

  Future<List<RaceSessionEntry>> listSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_libraryKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final entries = list
          .map(
            (item) => RaceSessionEntry.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      entries.sort((a, b) => b.record.startedAt.compareTo(a.record.startedAt));
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<RaceSessionEntry?> loadLastEntry() async {
    final entries = await listSaved();
    if (entries.isNotEmpty) return entries.first;
    final record = await loadLast();
    final gpx = await loadLastGpx();
    if (record == null || gpx == null) return null;
    return RaceSessionEntry(
      id: 'legacy:last',
      fileName: _suggestedFileName(record),
      record: record,
      gpx: gpx,
    );
  }

  Future<RaceSessionRecord?> loadLast() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return RaceSessionRecord.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadLastGpx() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastGpxKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Future<bool> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await listSaved();
    final updated = entries.where((entry) => entry.id != id).toList();
    if (updated.length == entries.length) return false;
    await prefs.setString(
      _libraryKey,
      jsonEncode(updated.map((entry) => entry.toJson()).toList()),
    );
    if (updated.isEmpty) {
      await prefs.remove(_lastSessionKey);
      await prefs.remove(_lastGpxKey);
    } else {
      await prefs.setString(
        _lastSessionKey,
        jsonEncode(updated.first.record.toJson()),
      );
      await prefs.setString(_lastGpxKey, updated.first.gpx);
    }
    return true;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_libraryKey);
    await prefs.remove(_lastSessionKey);
    await prefs.remove(_lastGpxKey);
  }

  String _suggestedFileName(RaceSessionRecord record) {
    final started = record.startedAt.toUtc();
    final datePart =
        started.year.toString() +
        _two(started.month) +
        _two(started.day) +
        '-' +
        _two(started.hour) +
        _two(started.minute) +
        _two(started.second);
    return '${_slugify(record.courseName)}-$datePart.gpx';
  }
}

String _slugify(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'race' : slug;
}

String _two(int value) => value.toString().padLeft(2, '0');

String _xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
