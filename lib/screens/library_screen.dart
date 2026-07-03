import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course.dart';
import '../services/course_file.dart';
import '../services/course_library.dart';
import '../services/race_session_store.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onCourseLoaded});

  final ValueChanged<Course> onCourseLoaded;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _courseLibrary = CourseLibrary();
  final _raceSessions = RaceSessionStore();

  List<CourseEntry> _courseEntries = const [];
  List<RaceSessionEntry> _raceEntries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final courses = await _courseLibrary.listAll();
    final races = await _raceSessions.listSaved();
    if (!mounted) return;
    setState(() {
      _courseEntries = courses;
      _raceEntries = races;
      _loading = false;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadCourse(CourseEntry entry) async {
    widget.onCourseLoaded(entry.course);
    _snack('Loaded "${entry.name}" as the active course.');
  }

  Future<void> _shareCourse(CourseEntry entry) async {
    final json = CourseFile.encode(entry.course);
    final filename = CourseFile.suggestedFileName(entry.course);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: json,
          subject: entry.name,
          fileNameOverrides: [filename],
        ),
      );
    } catch (err) {
      _snack('Share failed: $err');
    }
  }

  Future<void> _deleteCourse(CourseEntry entry) async {
    await _courseLibrary.remove(entry.id);
    await _reload();
    _snack('Removed "${entry.name}" from library.');
  }

  Future<void> _shareRace(RaceSessionEntry entry) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(entry.gpx)),
              mimeType: 'application/gpx+xml',
              name: entry.fileName,
            ),
          ],
          fileNameOverrides: [entry.fileName],
          subject: entry.title,
          text: 'GPX track exported from Race Mate.',
          downloadFallbackEnabled: true,
        ),
      );
    } catch (err) {
      _snack('Share failed: $err');
    }
  }

  Future<void> _viewRace(RaceSessionEntry entry) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(entry.fileName),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              entry.gpx,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.ios_share),
            label: const Text('Share GPX'),
            onPressed: () {
              Navigator.pop(ctx);
              _shareRace(entry);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRace(RaceSessionEntry entry) async {
    await _raceSessions.remove(entry.id);
    await _reload();
    _snack('Removed "${entry.fileName}" from library.');
  }

  @override
  Widget build(BuildContext context) {
    final bundled = _courseEntries.where((entry) => entry.isBundled).toList();
    final saved = _courseEntries.where((entry) => !entry.isBundled).toList();
    final hasAnyEntries =
        bundled.isNotEmpty || saved.isNotEmpty || _raceEntries.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !hasAnyEntries
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved items yet. Save a course or finish a race to add it to the library.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  if (_raceEntries.isNotEmpty) ...[
                    _sectionHeader(context, 'Races'),
                    ..._raceEntries.map(_buildRaceRow),
                  ],
                  if (saved.isNotEmpty) ...[
                    _sectionHeader(context, 'Saved Courses'),
                    ...saved.map(_buildCourseRow),
                  ],
                  if (bundled.isNotEmpty) ...[
                    _sectionHeader(context, 'Bundled Courses'),
                    ...bundled.map(_buildCourseRow),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _buildCourseRow(CourseEntry entry) {
    final parts = <String>[
      if (entry.groupName != null && entry.groupName!.isNotEmpty)
        entry.groupName!,
      if (entry.details != null && entry.details!.isNotEmpty) entry.details!,
      '${entry.buoyCount} mark${entry.buoyCount == 1 ? '' : 's'}',
      if (entry.isBundled) 'bundled',
    ];
    return ListTile(
      leading: CircleAvatar(
        child: Icon(
          entry.isBundled ? Icons.inventory_2_outlined : Icons.bookmark,
        ),
      ),
      title: Text(entry.name),
      subtitle: Text(parts.join(' · ')),
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share course',
            onPressed: () => _shareCourse(entry),
          ),
          if (!entry.isBundled)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove course',
              onPressed: () => _deleteCourse(entry),
            ),
          FilledButton.tonal(
            onPressed: () => _loadCourse(entry),
            child: const Text('Load'),
          ),
        ],
      ),
    );
  }

  Widget _buildRaceRow(RaceSessionEntry entry) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.route_outlined)),
      title: Text(entry.title),
      subtitle: Text('${entry.fileName} · ${entry.subtitle}'),
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'View GPX',
            onPressed: () => _viewRace(entry),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share GPX',
            onPressed: () => _shareRace(entry),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove race',
            onPressed: () => _deleteRace(entry),
          ),
        ],
      ),
    );
  }
}
