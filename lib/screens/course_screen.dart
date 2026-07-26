import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course.dart';
import '../services/app_analytics.dart';
import '../services/course_file.dart';
import '../services/course_library.dart';
import '../utils/geo.dart';
import '../widgets/imported_course_picker_dialog.dart';

/// Course setup screen — starts with a simple course list and opens a focused
/// editor only when the user chooses to create or edit a course.
class CourseScreen extends StatefulWidget {
  const CourseScreen({
    super.key,
    required this.course,
    required this.onChanged,
  });

  final Course course;
  final ValueChanged<Course> onChanged;

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  final _library = CourseLibrary();

  late Course _course;
  List<CourseEntry> _entries = const [];
  bool _loading = true;
  String? _groupFilter;

  @override
  void initState() {
    super.initState();
    _course = _copyCourse(widget.course);
    unawaited(_reloadEntries());
  }

  @override
  void didUpdateWidget(covariant CourseScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.course, widget.course)) {
      _course = _copyCourse(widget.course);
    }
  }

  String _courseFingerprint(Course course) => course.encode();

  Course _copyCourse(Course course) => Course.decode(course.encode());

  void _commit() => widget.onChanged(_copyCourse(_course));

  CourseEntry? get _activeEntry {
    final fingerprint = _courseFingerprint(_course);
    for (final entry in _entries) {
      if (_courseFingerprint(entry.course) == fingerprint) {
        return entry;
      }
    }
    return null;
  }

  bool get _isEmptyDraft => _activeEntry == null && _course.buoys.isEmpty;

  List<CourseEntry> get _savedEntries =>
      _entries.where((entry) => !entry.isBundled).toList(growable: false)
        ..sort((a, b) => a.name.compareTo(b.name));

  List<CourseEntry> get _bundledEntries =>
      _entries.where((entry) => entry.isBundled).toList(growable: false)
        ..sort((a, b) => a.name.compareTo(b.name));

  String _groupKeyForCourse(CourseEntry entry) {
    final groupName = entry.groupName?.trim();
    if (groupName != null && groupName.isNotEmpty) {
      return groupName;
    }
    return entry.name;
  }

  List<String> _availableGroupFilters([List<CourseEntry>? entries]) {
    final source = entries ?? _entries;
    final unique = source.map(_groupKeyForCourse).toSet().toList()..sort();
    return unique;
  }

  void _syncGroupFilter([List<CourseEntry>? entries]) {
    final options = _availableGroupFilters(entries);
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

  Future<void> _reloadEntries() async {
    final entries = await _library.listAll();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
      _syncGroupFilter(entries);
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectEntry(CourseEntry entry) async {
    setState(() => _course = _copyCourse(entry.course));
    _commit();
    _snack('Selected "${entry.name}".');
  }

  Future<void> _createCourse({bool openEditor = true}) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New course'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Course name'),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null) return;

    final created = await _library.save(Course(name: name, buoys: []));
    AppAnalytics.instance.logCourseSaved(buoyCount: 0, source: 'course_create');
    await _reloadEntries();
    if (!mounted) return;
    setState(() => _course = _copyCourse(created.course));
    _commit();
    if (openEditor) {
      await _editCourseEntry(created);
    }
  }

  Future<void> _editCurrentCourse() async {
    if (_isEmptyDraft) {
      await _createCourse();
      return;
    }
    await _editCourseEntry(_activeEntry);
  }

  Future<void> _editCourseEntry(CourseEntry? sourceEntry) async {
    final initialCourse = sourceEntry?.course ?? _course;
    final edited = await Navigator.of(context).push<Course>(
      MaterialPageRoute(
        builder: (_) => _CourseEditorPage(
          course: _copyCourse(initialCourse),
          isBundledTemplate: sourceEntry?.isBundled ?? false,
        ),
      ),
    );
    if (edited == null) return;
    await _persistEditedCourse(edited, sourceEntry: sourceEntry);
  }

  Future<void> _persistEditedCourse(
    Course edited, {
    CourseEntry? sourceEntry,
  }) async {
    final overwriteId = sourceEntry != null && !sourceEntry.isBundled
        ? sourceEntry.id
        : null;
    final saved = await _library.save(edited, id: overwriteId);
    AppAnalytics.instance.logCourseSaved(
      buoyCount: edited.buoys.length,
      source: overwriteId == null ? 'course_create' : 'course_editor',
    );
    await _reloadEntries();
    if (!mounted) return;
    setState(() => _course = _copyCourse(saved.course));
    _commit();
    _snack(
      overwriteId == null
          ? 'Saved "${saved.name}" to courses.'
          : 'Updated "${saved.name}".',
    );
  }

  Future<void> _shareCourse(Course course) async {
    final filename = CourseFile.suggestedFileName(course);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              CourseFile.encodeBytes(course),
              mimeType: CourseFile.mimeType,
              name: filename,
            ),
          ],
          subject: course.name,
          fileNameOverrides: [filename],
          text: 'Course exported from Race Mate.',
          downloadFallbackEnabled: true,
        ),
      );
    } catch (error) {
      _snack('Share failed: $error');
    }
  }

  Future<void> _shareCurrentCourse() async {
    if (_isEmptyDraft) return;
    await _shareCourse(_course);
  }

  Future<void> _showCurrentCourseJson() async {
    if (_isEmptyDraft || !mounted) return;
    final json = CourseFile.encode(_course);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Export "${_course.name}"'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
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
            label: const Text('Share file'),
            onPressed: () {
              Navigator.pop(ctx);
              _shareCurrentCourse();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _importFromFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'Course',
        extensions: ['srcourse', 'json'],
        uniformTypeIdentifiers: [
          'com.sailrace.sail-race-course',
          'public.json',
        ],
        mimeTypes: ['application/json'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final json = utf8.decode(bytes);
      final bundle = CourseFile.decodeBundle(json);
      if (!mounted) return;
      final selected = await pickImportedCourse(
        context,
        bundle,
        sourceName: file.name,
      );
      if (selected == null) return;
      await _saveImportedCourse(selected.course, sourceName: file.name);
    } on CourseFileException catch (error) {
      _snack('Invalid course file: $error');
    } catch (error) {
      _snack('Import failed: $error');
    }
  }

  Future<void> _importFromPaste() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste course JSON'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 14,
            minLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '{ "format": "sail-race-course", "version": 2, ... }',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final bundle = CourseFile.decodeBundle(text);
      if (!mounted) return;
      final selected = await pickImportedCourse(
        context,
        bundle,
        sourceName: 'pasted JSON',
      );
      if (selected == null) return;
      await _saveImportedCourse(selected.course, sourceName: 'pasted JSON');
    } on CourseFileException catch (error) {
      _snack('Invalid course file: $error');
    }
  }

  Future<void> _saveImportedCourse(
    Course imported, {
    required String sourceName,
  }) async {
    final saved = await _library.save(imported);
    AppAnalytics.instance.logCourseSaved(
      buoyCount: imported.buoys.length,
      source: 'course_import',
    );
    await _reloadEntries();
    if (!mounted) return;
    setState(() => _course = _copyCourse(saved.course));
    _commit();
    _snack('Imported "${saved.name}" from $sourceName.');
  }

  Future<void> _deleteCourseEntry(CourseEntry entry) async {
    final removingActive = _activeEntry?.id == entry.id;
    await _library.remove(entry.id);
    await _reloadEntries();
    if (!mounted) return;
    if (removingActive) {
      final fallbackEntries = [..._savedEntries, ..._bundledEntries];
      final fallbackCourse = fallbackEntries.isNotEmpty
          ? _copyCourse(fallbackEntries.first.course)
          : Course(name: 'My Course', buoys: []);
      setState(() => _course = fallbackCourse);
      _commit();
    }
    _snack('Removed "${entry.name}" from courses.');
  }

  void _handleCourseMenuSelection(CourseEntry entry, String value) {
    switch (value) {
      case 'edit':
        unawaited(_editCourseEntry(entry));
        break;
      case 'share':
        unawaited(_shareCourse(entry.course));
        break;
      case 'delete':
        unawaited(_deleteCourseEntry(entry));
        break;
    }
  }

  void _handleTopMenuSelection(String value) {
    switch (value) {
      case 'import_file':
        unawaited(_importFromFile());
        break;
      case 'import_paste':
        unawaited(_importFromPaste());
        break;
      case 'share_current':
        unawaited(_shareCurrentCourse());
        break;
      case 'view_json':
        unawaited(_showCurrentCourseJson());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _applyCourseFilter(_savedEntries);
    final bundled = _applyCourseFilter(_bundledEntries);
    final groupOptions = _availableGroupFilters();
    final hasEntries = saved.isNotEmpty || bundled.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Courses'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Course options',
            icon: const Icon(Icons.more_vert),
            onSelected: _handleTopMenuSelection,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'import_file',
                child: ListTile(
                  leading: Icon(Icons.folder_open),
                  title: Text('Import from file'),
                ),
              ),
              const PopupMenuItem(
                value: 'import_paste',
                child: ListTile(
                  leading: Icon(Icons.paste),
                  title: Text('Import pasted JSON'),
                ),
              ),
              if (!_isEmptyDraft) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'share_current',
                  child: ListTile(
                    leading: Icon(Icons.ios_share),
                    title: Text('Share current course'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'view_json',
                  child: ListTile(
                    leading: Icon(Icons.code),
                    title: Text('View current JSON'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _selectedCourseCard(context),
                const SizedBox(height: 16),
                if (groupOptions.length > 1) ...[
                  _courseFilterBar(context, groupOptions),
                  const SizedBox(height: 16),
                ],
                if (!hasEntries)
                  _emptyState(context)
                else ...[
                  if (saved.isNotEmpty) ...[
                    _sectionHeader(context, 'Saved Courses'),
                    ...saved.map((entry) => _courseRow(context, entry)),
                  ],
                  if (bundled.isNotEmpty) ...[
                    _sectionHeader(context, 'Bundled Courses'),
                    ...bundled.map((entry) => _courseRow(context, entry)),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _courseFilterBar(BuildContext context, List<String> groupOptions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Filter', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          key: const Key('course-group-filter'),
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
    );
  }

  Widget _selectedCourseCard(BuildContext context) {
    final activeEntry = _activeEntry;
    final isBundled = activeEntry?.isBundled ?? false;
    final title = _isEmptyDraft
        ? 'Choose a course to get started'
        : _course.name;
    final subtitle = _isEmptyDraft
        ? 'Start with a bundled course, import one, or create your own.'
        : '${_course.buoys.length} mark${_course.buoys.length == 1 ? '' : 's'}'
              '${activeEntry == null
                  ? ' · draft'
                  : isBundled
                  ? ' · bundled'
                  : ' · saved'}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selected course',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (isBundled) ...[
              const SizedBox(height: 10),
              Text(
                'Editing this course will save your own copy.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _editCurrentCourse,
                  icon: Icon(_isEmptyDraft ? Icons.add : Icons.edit_outlined),
                  label: Text(_isEmptyDraft ? 'Create course' : 'Edit course'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _createCourse(openEditor: true),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('New course'),
                ),
                OutlinedButton.icon(
                  onPressed: _importFromFile,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Import'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No saved courses yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first course or import one to start racing.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => _createCourse(openEditor: true),
                  icon: const Icon(Icons.add),
                  label: const Text('Create course'),
                ),
                OutlinedButton.icon(
                  onPressed: _importFromFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Import file'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _courseRow(BuildContext context, CourseEntry entry) {
    final active = _activeEntry?.id == entry.id;
    final parts = <String>[
      if (entry.groupName != null && entry.groupName!.isNotEmpty)
        entry.groupName!,
      if (entry.details != null && entry.details!.isNotEmpty) entry.details!,
      '${entry.buoyCount} mark${entry.buoyCount == 1 ? '' : 's'}',
    ];
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: active ? colors.primaryContainer.withValues(alpha: 0.55) : null,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          onTap: () => _selectEntry(entry),
          leading: CircleAvatar(
            backgroundColor: active
                ? colors.primary
                : colors.surfaceContainerHighest,
            foregroundColor: active
                ? colors.onPrimary
                : colors.onSurfaceVariant,
            child: Icon(
              active
                  ? Icons.check
                  : entry.isBundled
                  ? Icons.inventory_2_outlined
                  : Icons.bookmark_outline,
            ),
          ),
          title: Text(
            entry.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(parts.join(' · ')),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    'Active',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'Course actions',
                onSelected: (value) => _handleCourseMenuSelection(entry, value),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit course'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      leading: Icon(Icons.ios_share),
                      title: Text('Share course'),
                    ),
                  ),
                  if (!entry.isBundled)
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete course'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseEditorPage extends StatefulWidget {
  const _CourseEditorPage({
    required this.course,
    required this.isBundledTemplate,
  });

  final Course course;
  final bool isBundledTemplate;

  @override
  State<_CourseEditorPage> createState() => _CourseEditorPageState();
}

class _CourseEditorPageState extends State<_CourseEditorPage> {
  late Course _course;

  @override
  void initState() {
    super.initState();
    _course = widget.course;
  }

  Future<void> _addOrEdit({Buoy? existing, int? index}) async {
    final result = await showDialog<Buoy>(
      context: context,
      builder: (_) => _BuoyDialog(buoy: existing),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _course.buoys.add(result);
      } else {
        _course.buoys[index] = result;
      }
    });
  }

  void _remove(int index) {
    setState(() => _course.buoys.removeAt(index));
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _course.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Course name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _course.name = name);
  }

  void _closeEditor() {
    Navigator.pop(context, _course);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Done',
          onPressed: _closeEditor,
        ),
        title: Text(_course.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Rename course',
            onPressed: _rename,
          ),
          TextButton(onPressed: _closeEditor, child: const Text('Done')),
        ],
      ),
      body: _course.buoys.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.isBundledTemplate
                          ? 'Add or adjust the race marks for your own copy of this course.'
                          : 'Add the race marks in order.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _addOrEdit(),
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('Add first buoy'),
                    ),
                  ],
                ),
              ),
            )
          : ReorderableListView.builder(
              itemCount: _course.buoys.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final buoy = _course.buoys.removeAt(oldIndex);
                  _course.buoys.insert(newIndex, buoy);
                });
              },
              itemBuilder: (ctx, index) {
                final buoy = _course.buoys[index];
                return ListTile(
                  key: ValueKey('${buoy.name}-$index'),
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(buoy.name),
                  subtitle: Text(
                    '${buoy.position.lat.toStringAsFixed(5)}, '
                    '${buoy.position.lng.toStringAsFixed(5)}  •  '
                    'r=${buoy.roundingRadiusM.toStringAsFixed(0)} m',
                  ),
                  onTap: () => _addOrEdit(existing: buoy, index: index),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(index),
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Add buoy'),
      ),
    );
  }
}

class _BuoyDialog extends StatefulWidget {
  const _BuoyDialog({this.buoy});

  final Buoy? buoy;

  @override
  State<_BuoyDialog> createState() => _BuoyDialogState();
}

class _BuoyDialogState extends State<_BuoyDialog> {
  late final TextEditingController _name;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _radius;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.buoy?.name ?? '');
    _lat = TextEditingController(
      text: widget.buoy?.position.lat.toStringAsFixed(6) ?? '',
    );
    _lng = TextEditingController(
      text: widget.buoy?.position.lng.toStringAsFixed(6) ?? '',
    );
    _radius = TextEditingController(
      text: (widget.buoy?.roundingRadiusM ?? 25.0).toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    _radius.dispose();
    super.dispose();
  }

  String? _validateLat(String? value) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null || parsed < -90 || parsed > 90) {
      return 'Latitude must be -90..90';
    }
    return null;
  }

  String? _validateLng(String? value) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null || parsed < -180 || parsed > 180) {
      return 'Longitude must be -180..180';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.buoy == null ? 'Add buoy' : 'Edit buoy'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _lat,
                decoration: const InputDecoration(labelText: 'Latitude'),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                validator: _validateLat,
              ),
              TextFormField(
                controller: _lng,
                decoration: const InputDecoration(labelText: 'Longitude'),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                validator: _validateLng,
              ),
              TextFormField(
                controller: _radius,
                decoration: const InputDecoration(
                  labelText: 'Rounding radius (m)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed <= 0) return 'Must be > 0';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              Buoy(
                name: _name.text.trim(),
                position: LatLng(
                  double.parse(_lat.text),
                  double.parse(_lng.text),
                ),
                roundingRadiusM: double.parse(_radius.text),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
