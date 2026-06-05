import 'package:flutter/material.dart';
import 'models/course.dart';
import 'screens/course_screen.dart';
import 'screens/race_screen.dart';
import 'services/course_store.dart';

void main() {
  runApp(const SailRaceApp());
}

class SailRaceApp extends StatelessWidget {
  const SailRaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sail Race Computer',
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
  int _tab = 0;

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
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          CourseScreen(course: course, onChanged: _onCourseChanged),
          RaceScreen(course: course),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.flag_outlined),
              selectedIcon: Icon(Icons.flag),
              label: 'Course'),
          NavigationDestination(
              icon: Icon(Icons.speed_outlined),
              selectedIcon: Icon(Icons.speed),
              label: 'Race'),
        ],
      ),
    );
  }
}
