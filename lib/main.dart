import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'models/course.dart';
import 'services/course_store.dart';

void main() {
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
  final _store = CourseStore();
  Course? _course;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _store.load();
    setState(() {
      _course = c ?? Course(name: 'My Course', buoys: []);
    });
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
