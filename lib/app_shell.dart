import 'package:flutter/material.dart';
import 'models/course.dart';
import 'screens/course_screen.dart';
import 'screens/library_screen.dart';
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
  var _libraryVersion = 0;
  var _raceRecording = false;

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
          RaceScreen(
            course: widget.course,
            positionSource: widget.positionSource,
            onCourseChanged: widget.onCourseChanged,
            onRecordingChanged: (isRecording) {
              if (_raceRecording == isRecording || !mounted) return;
              setState(() => _raceRecording = isRecording);
            },
          ),
          MapScreen(
            course: widget.course,
            positionSource: widget.positionSource,
          ),
          LibraryScreen(
            key: ValueKey('library-$_libraryVersion'),
            onCourseLoaded: (course) {
              widget.onCourseChanged(course);
              setState(() => _tab = 0);
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() {
            if (i == 3 && _tab != 3) {
              _libraryVersion++;
            }
            _tab = i;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Course',
          ),
          NavigationDestination(
            icon: _RaceTabIcon(
              isHighlighted: _raceRecording,
              isSelected: false,
            ),
            selectedIcon: _RaceTabIcon(
              isHighlighted: _raceRecording,
              isSelected: true,
            ),
            label: 'Race',
          ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          const NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}

class _RaceTabIcon extends StatelessWidget {
  const _RaceTabIcon({
    required this.isHighlighted,
    required this.isSelected,
  });

  static const _recordOrange = Color(0xFFFC4C02);

  final bool isHighlighted;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    if (!isHighlighted) {
      return Icon(isSelected ? Icons.speed : Icons.speed_outlined);
    }

    return DecoratedBox(
      key: Key(
        isSelected
            ? 'race-tab-recording-selected'
            : 'race-tab-recording-indicator',
      ),
      decoration: BoxDecoration(
        color: _recordOrange,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 22,
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}
