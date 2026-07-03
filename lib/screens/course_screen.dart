import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/course.dart';
import '../services/course_file.dart';
import '../services/course_library.dart';
import '../services/race_session_store.dart';
import '../utils/geo.dart';
import '../widgets/imported_course_picker_dialog.dart';

/// Course setup screen — manage the list of buoys for the race.
class CourseScreen extends StatefulWidget {
  final Course course;
  final ValueChanged<Course> onChanged;

  const CourseScreen({
    super.key,
    required this.course,
    required this.onChanged,
  });

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  late Course _course;
  final _library = CourseLibrary();
  final _raceSessions = RaceSessionStore();

  @override
  void initState() {
    super.initState();
    _course = widget.course;
  }

  @override
  void didUpdateWidget(covariant CourseScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.course, widget.course)) {
      _course = widget.course;
    }
  }

  void _commit() => widget.onChanged(_course);

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
    _commit();
  }

  void _remove(int i) {
    setState(() => _course.buoys.removeAt(i));
    _commit();
  }

  void _rename() async {
    final controller = TextEditingController(text: _course.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Course name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _course.name = name);
    _commit();
  }

  Future<void> _exportShare() async {
    final json = CourseFile.encode(_course);
    final filename = CourseFile.suggestedFileName(_course);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: json,
          subject: _course.name,
          fileNameOverrides: [filename],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Share failed: $e');
    }
  }

  Future<void> _exportShowJson() async {
    final json = CourseFile.encode(_course);
    if (!mounted) return;
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
              _exportShare();
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
      final selected =
          await pickImportedCourse(context, bundle, sourceName: file.name);
      if (selected == null) return;
      await _applyImported(selected.course, sourceName: file.name);
    } on CourseFileException catch (e) {
      _snack('Invalid course file: $e');
    } catch (e) {
      _snack('Import failed: $e');
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
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
      final selected = await pickImportedCourse(
        context,
        bundle,
        sourceName: 'pasted JSON',
      );
      if (selected == null) return;
      await _applyImported(selected.course, sourceName: 'pasted JSON');
    } on CourseFileException catch (e) {
      _snack('Invalid course file: $e');
    }
  }

  Future<void> _applyImported(Course imported, {String? sourceName}) async {
    if (!mounted) return;
    if (_course.buoys.isEmpty) {
      await _library.save(imported);
      setState(() => _course = imported);
      _commit();
      _snack('Loaded "${imported.name}" (${imported.buoys.length} buoys).');
      return;
    }
    final from = sourceName == null ? '' : ' from $sourceName';
    final choice = await showDialog<_ImportChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import course'),
        content: Text(
          'Import "${imported.name}" (${imported.buoys.length} marks)$from.\n\n'
          'Replace your current course, or load it as a new course alongside the current one?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, _ImportChoice.replace),
            child: const Text('Replace current'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _ImportChoice.addNew),
            child: const Text('New course'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == _ImportChoice.addNew) {
      // Preserve the current course so the user can switch back.
      await _library.save(_course);
    }
    await _library.save(imported);
    setState(() => _course = imported);
    _commit();
    _snack('Loaded "${imported.name}" (${imported.buoys.length} buoys).');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveCurrentToLibrary() async {
    await _library.save(_course);
    _snack('Saved "${_course.name}" to library.');
  }

  Future<void> _newCourse() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New course'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Course name'),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final n = controller.text.trim();
              if (n.isNotEmpty) Navigator.pop(ctx, n);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null) return;
    if (_course.buoys.isNotEmpty) await _library.save(_course);
    setState(() => _course = Course(name: name, buoys: []));
    _commit();
  }

  Future<void> _exportShareEntry(CourseEntry e) async {
    final json = CourseFile.encode(e.course);
    final filename = CourseFile.suggestedFileName(e.course);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: json,
          subject: e.name,
          fileNameOverrides: [filename],
        ),
      );
    } catch (err) {
      if (!mounted) return;
      _snack('Share failed: $err');
    }
  }

  Future<void> _shareRaceEntry(RaceSessionEntry entry) async {
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
      if (!mounted) return;
      _snack('Share failed: $err');
    }
  }

  Future<void> _viewRaceEntry(RaceSessionEntry entry) async {
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
              _shareRaceEntry(entry);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openLibrary() async {
    final entries = await _library.listAll();
    final raceEntries = await _raceSessions.listSaved();
    if (!mounted) return;
    final action = await showModalBottomSheet<_LibraryAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) =>
          _LibrarySheet(entries: entries, raceEntries: raceEntries),
    );
    if (action == null) return;
    switch (action.kind) {
      case _LibraryActionKind.loadCourse:
        _applyImported(
          action.courseEntry!.course,
          sourceName: action.courseEntry!.isBundled ? 'bundled' : 'library',
        );
        break;
      case _LibraryActionKind.shareCourse:
        _exportShareEntry(action.courseEntry!);
        break;
      case _LibraryActionKind.deleteCourse:
        await _library.remove(action.courseEntry!.id);
        _snack('Removed "${action.courseEntry!.name}" from library.');
        break;
      case _LibraryActionKind.newCourse:
        _newCourse();
        break;
      case _LibraryActionKind.viewRace:
        _viewRaceEntry(action.raceEntry!);
        break;
      case _LibraryActionKind.shareRace:
        _shareRaceEntry(action.raceEntry!);
        break;
      case _LibraryActionKind.deleteRace:
        await _raceSessions.remove(action.raceEntry!.id);
        _snack('Removed "${action.raceEntry!.fileName}" from library.');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_course.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_books_outlined),
            tooltip: 'Library',
            onPressed: _openLibrary,
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Rename course',
            onPressed: _rename,
          ),
          PopupMenuButton<String>(
            tooltip: 'Share / import',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'new':
                  _newCourse();
                  break;
                case 'save':
                  _saveCurrentToLibrary();
                  break;
                case 'share':
                  _exportShare();
                  break;
                case 'view':
                  _exportShowJson();
                  break;
                case 'pick':
                  _importFromFile();
                  break;
                case 'paste':
                  _importFromPaste();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'new',
                child: ListTile(
                  leading: Icon(Icons.add_circle_outline),
                  title: Text('New course'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'save',
                child: ListTile(
                  leading: Icon(Icons.bookmark_add_outlined),
                  title: Text('Save to library'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Share as file'),
                  subtitle: Text('Send via Mail, Messages, AirDrop…'),
                ),
              ),
              PopupMenuItem(
                value: 'view',
                child: ListTile(
                  leading: Icon(Icons.code),
                  title: Text('View / copy JSON'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'pick',
                child: ListTile(
                  leading: Icon(Icons.folder_open),
                  title: Text('Import from file…'),
                ),
              ),
              PopupMenuItem(
                value: 'paste',
                child: ListTile(
                  leading: Icon(Icons.paste),
                  title: Text('Import from pasted JSON…'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _course.buoys.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Add the race marks in order.\nTap + to add a buoy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            )
          : ReorderableListView.builder(
              itemCount: _course.buoys.length,
              onReorder: (oldI, newI) {
                setState(() {
                  if (newI > oldI) newI -= 1;
                  final b = _course.buoys.removeAt(oldI);
                  _course.buoys.insert(newI, b);
                });
                _commit();
              },
              itemBuilder: (ctx, i) {
                final b = _course.buoys[i];
                return ListTile(
                  key: ValueKey('${b.name}-$i'),
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(b.name),
                  subtitle: Text(
                    '${b.position.lat.toStringAsFixed(5)}, '
                    '${b.position.lng.toStringAsFixed(5)}  •  '
                    'r=${b.roundingRadiusM.toStringAsFixed(0)} m',
                  ),
                  onTap: () => _addOrEdit(existing: b, index: i),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(i),
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
  final Buoy? buoy;
  const _BuoyDialog({this.buoy});

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
        text: widget.buoy?.position.lat.toStringAsFixed(6) ?? '');
    _lng = TextEditingController(
        text: widget.buoy?.position.lng.toStringAsFixed(6) ?? '');
    _radius = TextEditingController(
        text: (widget.buoy?.roundingRadiusM ?? 25.0).toStringAsFixed(0));
  }

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    _radius.dispose();
    super.dispose();
  }

  String? _validateLat(String? s) {
    final v = double.tryParse(s ?? '');
    if (v == null || v < -90 || v > 90) return 'Latitude must be -90..90';
    return null;
  }

  String? _validateLng(String? s) {
    final v = double.tryParse(s ?? '');
    if (v == null || v < -180 || v > 180) return 'Longitude must be -180..180';
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
                validator: (s) =>
                    (s == null || s.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _lat,
                decoration: const InputDecoration(labelText: 'Latitude'),
                keyboardType: const TextInputType.numberWithOptions(
                    signed: true, decimal: true),
                validator: _validateLat,
              ),
              TextFormField(
                controller: _lng,
                decoration: const InputDecoration(labelText: 'Longitude'),
                keyboardType: const TextInputType.numberWithOptions(
                    signed: true, decimal: true),
                validator: _validateLng,
              ),
              TextFormField(
                controller: _radius,
                decoration:
                    const InputDecoration(labelText: 'Rounding radius (m)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (s) {
                  final v = double.tryParse(s ?? '');
                  if (v == null || v <= 0) return 'Must be > 0';
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
            child: const Text('Cancel')),
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

enum _LibraryActionKind {
  loadCourse,
  shareCourse,
  deleteCourse,
  newCourse,
  viewRace,
  shareRace,
  deleteRace,
}

class _LibraryAction {
  _LibraryAction(
    this.kind, {
    this.courseEntry,
    this.raceEntry,
  });

  final _LibraryActionKind kind;
  final CourseEntry? courseEntry;
  final RaceSessionEntry? raceEntry;
}

enum _ImportChoice { replace, addNew }

class _LibrarySheet extends StatelessWidget {
  const _LibrarySheet({
    required this.entries,
    required this.raceEntries,
  });

  final List<CourseEntry> entries;
  final List<RaceSessionEntry> raceEntries;

  @override
  Widget build(BuildContext context) {
    final bundled = entries.where((e) => e.isBundled).toList();
    final saved = entries.where((e) => !e.isBundled).toList();
    final hasAnyEntries =
        bundled.isNotEmpty || saved.isNotEmpty || raceEntries.isNotEmpty;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Library',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _LibraryAction(_LibraryActionKind.newCourse),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('New'),
                  ),
                ],
              ),
            ),
            if (!hasAnyEntries)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved items yet. Save a course or finish a race to add it to the library.',
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (raceEntries.isNotEmpty) ...[
                      _sectionHeader(context, 'Races'),
                      ...raceEntries.map((e) => _raceRow(context, e)),
                    ],
                    if (saved.isNotEmpty) ...[
                      _sectionHeader(context, 'Saved Courses'),
                      ...saved.map((e) => _courseRow(context, e)),
                    ],
                    if (bundled.isNotEmpty) ...[
                      _sectionHeader(context, 'Bundled Courses'),
                      ...bundled.map((e) => _courseRow(context, e)),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
      );

  Widget _courseRow(BuildContext context, CourseEntry e) {
    final parts = <String>[
      if (e.groupName != null && e.groupName!.isNotEmpty) e.groupName!,
      if (e.details != null && e.details!.isNotEmpty) e.details!,
      '${e.buoyCount} mark${e.buoyCount == 1 ? '' : 's'}',
      if (e.isBundled) 'bundled',
    ];
    return ListTile(
      leading: CircleAvatar(
        child: Icon(e.isBundled ? Icons.inventory_2_outlined : Icons.bookmark),
      ),
      title: Text(e.name),
      subtitle: Text(parts.join(' · ')),
      onTap: () => Navigator.pop(
        context,
        _LibraryAction(_LibraryActionKind.loadCourse, courseEntry: e),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share',
            onPressed: () => Navigator.pop(
              context,
              _LibraryAction(_LibraryActionKind.shareCourse, courseEntry: e),
            ),
          ),
          if (!e.isBundled)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: () => Navigator.pop(
                context,
                _LibraryAction(_LibraryActionKind.deleteCourse, courseEntry: e),
              ),
            ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(
              context,
              _LibraryAction(_LibraryActionKind.loadCourse, courseEntry: e),
            ),
            child: const Text('Load'),
          ),
        ],
      ),
    );
  }

  Widget _raceRow(BuildContext context, RaceSessionEntry entry) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.route_outlined),
      ),
      title: Text(entry.title),
      subtitle: Text('${entry.fileName} · ${entry.subtitle}'),
      onTap: () => Navigator.pop(
        context,
        _LibraryAction(_LibraryActionKind.viewRace, raceEntry: entry),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share GPX',
            onPressed: () => Navigator.pop(
              context,
              _LibraryAction(_LibraryActionKind.shareRace, raceEntry: entry),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove',
            onPressed: () => Navigator.pop(
              context,
              _LibraryAction(_LibraryActionKind.deleteRace, raceEntry: entry),
            ),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(
              context,
              _LibraryAction(_LibraryActionKind.viewRace, raceEntry: entry),
            ),
            child: const Text('View GPX'),
          ),
        ],
      ),
    );
  }
}
