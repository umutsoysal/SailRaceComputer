import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_shell.dart';
import 'models/course.dart';
import 'services/app_analytics.dart';
import 'services/course_file.dart';
import 'services/course_store.dart';
import 'widgets/imported_course_picker_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppAnalytics.instance.initialize();
  runApp(const SailRaceApp());
}

class SailRaceApp extends StatelessWidget {
  const SailRaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Race Mate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6FB8)),
        useMaterial3: true,
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  static const _fileChannel = MethodChannel('sail_race/file_open');

  final _store = CourseStore();
  Course? _course;

  @override
  void initState() {
    super.initState();
    _load();
    _fileChannel.setMethodCallHandler((call) async {
      if (call.method == 'openCourse') {
        _handleIncomingJson(call.arguments as String);
      }
    });
    _fileChannel.invokeMethod<String>('getInitialFile').then((json) {
      if (json != null && json.isNotEmpty) _handleIncomingJson(json);
    }).catchError((_) {});
  }

  Future<void> _load() async {
    final c = await _store.load();
    setState(() {
      _course = c ?? Course(name: 'My Course', buoys: []);
    });
  }

  void _handleIncomingJson(String json) {
    if (!mounted) return;
    try {
      final bundle = CourseFile.decodeBundle(json);
      pickImportedCourse(context, bundle).then((selected) {
        if (selected != null) _promptImport(selected.course);
      });
    } on CourseFileException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid course file: $e')),
      );
    }
  }

  Future<void> _promptImport(Course incoming) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import course?'),
        content: Text(
          'Load "${incoming.name}" '
          '(${incoming.buoys.length} marks) as your current course?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok == true) _onCourseChanged(incoming);
  }

  void _onCourseChanged(Course c) {
    setState(() => _course = c);
    _store.save(c);
  }

  @override
  Widget build(BuildContext context) {
    final course = _course;
    if (course == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return AppShell(
      course: course,
      onCourseChanged: _onCourseChanged,
    );
  }
}
