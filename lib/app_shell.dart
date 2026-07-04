import 'package:flutter/material.dart';
import 'models/course.dart';
import 'screens/course_screen.dart';
import 'screens/library_screen.dart';
import 'screens/map_screen.dart';
import 'screens/race_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_analytics.dart';
import 'services/position_source.dart';
import 'widgets/help_tour.dart';

/// The user-facing app: course editing, racing, recordings, and settings.
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
    this.showTourOnFirstLaunch = false,
  });

  final Course course;
  final ValueChanged<Course> onCourseChanged;
  final PositionSource? positionSource;
  final int initialTab;

  /// When true, the overlay help tour is shown once on first launch
  /// (tracked via shared preferences). Production enables this; the dev
  /// simulator and tests leave it off.
  final bool showTourOnFirstLaunch;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _tab = widget.initialTab;
  var _libraryVersion = 0;
  var _raceRecording = false;

  final _navDestinationKeys =
      List.generate(5, (i) => GlobalKey(debugLabel: 'nav-destination-$i'));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _logTabSelection(_tab);
      if (widget.showTourOnFirstLaunch && !await HelpTour.hasSeen()) {
        if (mounted) _startTour();
      }
    });
  }

  void _startTour() {
    HelpTour.show(
      context,
      steps: [
        const HelpTourStep(
          title: 'Welcome to Race Mate',
          body: 'Here is a quick tour of the main tabs. '
              'Tap anywhere to continue, or skip at any time.',
        ),
        HelpTourStep(
          targetKey: _navDestinationKeys[0],
          title: 'Courses',
          body: 'Set up your racecourse: add and edit buoys, and share or '
              'import course files with your crew.',
        ),
        HelpTourStep(
          targetKey: _navDestinationKeys[1],
          title: 'Map',
          body: 'See the course top-down with your live GPS position '
              'overlaid. Pinch to zoom and pan around.',
        ),
        HelpTourStep(
          targetKey: _navDestinationKeys[2],
          title: 'Race',
          body: 'Race day lives here: live speed and headings, plus track '
              'recording. The tab glows orange while recording.',
        ),
        HelpTourStep(
          targetKey: _navDestinationKeys[3],
          title: 'Recordings',
          body: 'Review past races and load a recorded course back into '
              'the editor.',
        ),
        HelpTourStep(
          targetKey: _navDestinationKeys[4],
          title: 'Settings',
          body: 'Preferences, feedback, and legal info. You can replay '
              'this tour from here anytime.',
        ),
      ],
      onStepShown: (step) {
        if (step == 0 || !mounted) return;
        final tab = step - 1;
        if (_tab != tab) setState(() => _tab = tab);
      },
    );
  }

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
            onCourseChanged: widget.onCourseChanged,
            onRecordingChanged: (isRecording) {
              if (_raceRecording == isRecording || !mounted) return;
              setState(() => _raceRecording = isRecording);
            },
          ),
          LibraryScreen(
            key: ValueKey('recordings-$_libraryVersion'),
            onCourseLoaded: (course) {
              widget.onCourseChanged(course);
              setState(() => _tab = 0);
            },
            title: 'Recordings',
            mode: LibraryContentMode.recordings,
          ),
          SettingsScreen(onStartTour: _startTour),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() {
            if (i == 3 && _tab != i) {
              _libraryVersion++;
            }
            _tab = i;
          });
          _logTabSelection(i);
        },
        destinations: [
          NavigationDestination(
            key: _navDestinationKeys[0],
            icon: const Icon(Icons.flag_outlined),
            selectedIcon: const Icon(Icons.flag),
            label: 'Courses',
          ),
          NavigationDestination(
            key: _navDestinationKeys[1],
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            key: _navDestinationKeys[2],
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
          NavigationDestination(
            key: _navDestinationKeys[3],
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: 'Recordings',
          ),
          NavigationDestination(
            key: _navDestinationKeys[4],
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  void _logTabSelection(int index) {
    final tabName = switch (index) {
      0 => 'courses',
      1 => 'map',
      2 => 'race',
      3 => 'recordings',
      4 => 'settings',
      _ => 'unknown',
    };
    AppAnalytics.instance.logTabSelected(tabName);
    if (tabName == 'recordings') {
      AppAnalytics.instance.logLibraryOpened(source: 'bottom_nav');
    }
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
