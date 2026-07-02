import 'package:flutter/material.dart';
import 'models/course.dart';
import 'screens/course_screen.dart';
import 'screens/map_screen.dart';
import 'screens/race_screen.dart';
import 'services/position_source.dart';

/// The user-facing app: Course editor + Race screen tabs.
///
/// Production passes no [positionSource] (real GPS is used). The dev simulator
/// passes a fake source so the same widget tree can be exercised on the desk.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.course,
    required this.onCourseChanged,
    this.positionSource,
    this.initialTab = 0,
  });

  final Course course;
  final ValueChanged<Course> onCourseChanged;
  final PositionSource? positionSource;
  final int initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          CourseScreen(
            course: widget.course,
            onChanged: widget.onCourseChanged,
          ),
          MapScreen(
            course: widget.course,
            positionSource: widget.positionSource,
          ),
          RaceScreen(
            course: widget.course,
            positionSource: widget.positionSource,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Course',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label: 'Race',
          ),
        ],
      ),
    );
  }
}
