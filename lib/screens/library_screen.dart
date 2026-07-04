import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course.dart';
import '../services/course_file.dart';
import '../services/course_library.dart';
import '../services/race_session_store.dart';
import '../widgets/recording_map_preview.dart';

enum LibraryContentMode { courses, recordings }

enum _LibraryGrouping { defaultView, name }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.onCourseLoaded,
    required this.title,
    required this.mode,
    this.showModeSwitcher = false,
  });

  final ValueChanged<Course> onCourseLoaded;
  final String title;
  final LibraryContentMode mode;
  final bool showModeSwitcher;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _courseLibrary = CourseLibrary();
  final _raceSessions = RaceSessionStore();

  List<CourseEntry> _courseEntries = const [];
  List<RaceSessionEntry> _raceEntries = const [];
  bool _loading = true;
  late LibraryContentMode _filter;
  _LibraryGrouping _grouping = _LibraryGrouping.defaultView;
  String? _groupFilter;

  @override
  void initState() {
    super.initState();
    _filter = widget.mode;
    _reload();
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showModeSwitcher && oldWidget.mode != widget.mode) {
      _filter = widget.mode;
    }
  }

  Future<void> _reload() async {
    final courses = await _courseLibrary.listAll();
    final races = await _raceSessions.listSaved();
    if (!mounted) return;
    setState(() {
      _courseEntries = courses;
      _raceEntries = races;
      _loading = false;
      _syncGroupFilter();
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

  String _groupKeyForCourse(CourseEntry entry) {
    final groupName = entry.groupName?.trim();
    if (groupName != null && groupName.isNotEmpty) {
      return groupName;
    }
    return entry.name;
  }

  String _groupKeyForRace(RaceSessionEntry entry) => entry.title;

  List<String> _availableGroupFilters() {
    final values = switch (_filter) {
      LibraryContentMode.courses => _courseEntries.map(_groupKeyForCourse),
      LibraryContentMode.recordings => _raceEntries.map(_groupKeyForRace),
    };
    final unique = values.toSet().toList()..sort();
    return unique;
  }

  void _syncGroupFilter() {
    final options = _availableGroupFilters();
    if (_groupFilter != null && !options.contains(_groupFilter)) {
      _groupFilter = null;
    }
  }

  List<CourseEntry> _applyCourseFilter(List<CourseEntry> entries) {
    final filter = _groupFilter;
    if (filter == null) return entries;
    return entries
        .where((entry) => _groupKeyForCourse(entry) == filter)
        .toList(growable: false);
  }

  List<RaceSessionEntry> _applyRaceFilter(List<RaceSessionEntry> entries) {
    final filter = _groupFilter;
    if (filter == null) return entries;
    return entries
        .where((entry) => _groupKeyForRace(entry) == filter)
        .toList(growable: false);
  }

  Map<String, List<CourseEntry>> _groupCoursesByName(
      List<CourseEntry> entries) {
    final grouped = <String, List<CourseEntry>>{};
    for (final entry in entries) {
      final key = _groupKeyForCourse(entry);
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    final orderedKeys = grouped.keys.toList()..sort();
    return {
      for (final key in orderedKeys)
        key: grouped[key]!..sort((a, b) => a.name.compareTo(b.name)),
    };
  }

  Map<String, List<RaceSessionEntry>> _groupRacesByName(
    List<RaceSessionEntry> entries,
  ) {
    final grouped = <String, List<RaceSessionEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.title, () => []).add(entry);
    }
    final orderedKeys = grouped.keys.toList()..sort();
    return {
      for (final key in orderedKeys)
        key: grouped[key]!
          ..sort((a, b) => b.record.startedAt.compareTo(a.record.startedAt)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final bundled = _courseEntries.where((entry) => entry.isBundled).toList();
    final saved = _courseEntries.where((entry) => !entry.isBundled).toList();
    final showRaces = _filter == LibraryContentMode.recordings;
    final showCourses = _filter == LibraryContentMode.courses;
    final visibleRaces =
        showRaces ? _applyRaceFilter(_raceEntries) : const <RaceSessionEntry>[];
    final visibleSaved =
        showCourses ? _applyCourseFilter(saved) : const <CourseEntry>[];
    final visibleBundled =
        showCourses ? _applyCourseFilter(bundled) : const <CourseEntry>[];
    final hasAnyEntries = visibleBundled.isNotEmpty ||
        visibleSaved.isNotEmpty ||
        visibleRaces.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    children: [
                      _libraryControls(),
                      if (_grouping == _LibraryGrouping.defaultView) ...[
                        if (visibleRaces.isNotEmpty) ...[
                          _sectionHeader(context, 'Recorded Races'),
                          ...visibleRaces.map(_buildRaceRow),
                        ],
                        if (visibleSaved.isNotEmpty) ...[
                          _sectionHeader(context, 'Saved Courses'),
                          ...visibleSaved.map(_buildCourseRow),
                        ],
                        if (visibleBundled.isNotEmpty) ...[
                          _sectionHeader(context, 'Bundled Courses'),
                          ...visibleBundled.map(_buildCourseRow),
                        ],
                      ] else ...[
                        if (visibleRaces.isNotEmpty)
                          ..._buildGroupedRaceSections(visibleRaces),
                        if (visibleSaved.isNotEmpty) ...[
                          _sectionHeader(context, 'Saved Courses'),
                          ..._buildGroupedCourseSections(visibleSaved),
                        ],
                        if (visibleBundled.isNotEmpty) ...[
                          _sectionHeader(context, 'Bundled Courses'),
                          ..._buildGroupedCourseSections(visibleBundled),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _libraryControls() {
    final groupOptions = _availableGroupFilters();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showModeSwitcher) ...[
                SegmentedButton<LibraryContentMode>(
                  segments: const [
                    ButtonSegment(
                      value: LibraryContentMode.courses,
                      label: Text('Courses'),
                    ),
                    ButtonSegment(
                      value: LibraryContentMode.recordings,
                      label: Text('Recordings'),
                    ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _filter = selection.first;
                      _syncGroupFilter();
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Group by',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<_LibraryGrouping>(
                initialValue: _grouping,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: _LibraryGrouping.defaultView,
                    child: Text('Default'),
                  ),
                  DropdownMenuItem(
                    value: _LibraryGrouping.name,
                    child: Text('Name'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _grouping = value);
                },
              ),
              if (groupOptions.length > 1) ...[
                const SizedBox(height: 12),
                Text(
                  'Filter',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  key: const Key('library-group-filter'),
                  initialValue: _groupFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('All groups'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All groups'),
                    ),
                    ...groupOptions.map(
                      (value) => DropdownMenuItem<String?>(
                        value: value,
                        child: Text(value, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _groupFilter = value);
                  },
                ),
              ],
            ],
          ),
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

  List<Widget> _buildGroupedCourseSections(List<CourseEntry> entries) {
    final grouped = _groupCoursesByName(entries);
    return [
      for (final group in grouped.entries) ...[
        _subsectionHeader(group.key),
        ...group.value.map(_buildCourseRow),
      ],
    ];
  }

  List<Widget> _buildGroupedRaceSections(List<RaceSessionEntry> entries) {
    final grouped = _groupRacesByName(entries);
    return [
      _sectionHeader(context, 'Recorded Races'),
      for (final group in grouped.entries) ...[
        _subsectionHeader(group.key),
        ...group.value.map(_buildRaceRow),
      ],
    ];
  }

  Widget _subsectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      );

  Widget _buildCourseRow(CourseEntry entry) {
    final subtitle = entry.details?.trim().isNotEmpty == true
        ? entry.details!.trim()
        : '${entry.buoyCount} mark${entry.buoyCount == 1 ? '' : 's'}';
    return ListTile(
      onTap: () => _loadCourse(entry),
      leading: CircleAvatar(
        child: Icon(
          entry.isBundled ? Icons.inventory_2_outlined : Icons.bookmark,
        ),
      ),
      title: Text(entry.name),
      subtitle: Text(subtitle),
      trailing: PopupMenuButton<String>(
        tooltip: 'Course actions',
        onSelected: (value) {
          switch (value) {
            case 'share':
              _shareCourse(entry);
              break;
            case 'remove':
              _deleteCourse(entry);
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'share',
            child: Text('Share course'),
          ),
          if (!entry.isBundled)
            const PopupMenuItem(
              value: 'remove',
              child: Text('Remove course'),
            ),
        ],
      ),
    );
  }

  Widget _buildRaceRow(RaceSessionEntry entry) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _viewRace(entry),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecordingMapPreview(entry: entry),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.subtitle,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Race actions',
                      onSelected: (value) {
                        switch (value) {
                          case 'share':
                            _shareRace(entry);
                            break;
                          case 'remove':
                            _deleteRace(entry);
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'share',
                          child: Text('Share GPX'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove race'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
