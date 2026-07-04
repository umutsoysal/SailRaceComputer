import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/course.dart';
import '../services/app_analytics.dart';
import '../services/course_library.dart';
import '../services/location_service.dart';
import '../services/position_source.dart';
import '../services/race_computations.dart';
import '../services/race_session_store.dart';
import '../utils/geo.dart';
import '../widgets/course_map_painter.dart';

enum _RaceState { stopped, running, finished }

/// Live race screen — shows the next mark with bearing, distance, SOG, COG,
/// and VMG toward the mark.
class RaceScreen extends StatefulWidget {
  final Course course;
  final PositionSource? positionSource;
  final ValueChanged<Course>? onCourseChanged;
  final ValueChanged<bool>? onRecordingChanged;

  const RaceScreen({
    super.key,
    required this.course,
    this.positionSource,
    this.onCourseChanged,
    this.onRecordingChanged,
  });

  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen> {
  static const _startOffsetOptions = <int>[0, 1, 5];
  static const _raceViewLabels = <String>['Overview', 'VMG', 'Heading'];

  Timer? _raceClockTimer;
  late final PageController _raceViewController;
  late final LocationService _locationService;
  final _courseLibrary = CourseLibrary();
  final _sessionStore = RaceSessionStore();
  String? _raceError;
  int _currentMark = 0;
  bool _autoAdvance = true;
  _RaceState _raceState = _RaceState.stopped;
  DateTime? _raceStartedAt;
  Duration _raceClockElapsed = Duration.zero;
  int _startOffsetMinutes = 0;
  String? _finishMessage;
  bool _finishingRace = false;
  final List<RaceTrackPoint> _track = [];
  late Course _selectedCourse;
  List<CourseEntry> _courseEntries = const [];
  bool _loadingCourses = true;
  bool? _lastReportedRecording;
  int _raceViewIndex = 0;
  int _lastProcessedFixVersion = 0;

  String? get _displayError => _raceError ?? _locationService.error;

  @override
  void initState() {
    super.initState();
    _raceViewController = PageController();
    _selectedCourse = _copyCourse(widget.course);
    _locationService = LocationService(positionSource: widget.positionSource);
    _locationService.addListener(_handleLocationServiceChanged);
    _reportRecordingChanged();
    unawaited(_loadCourseEntries());
  }

  @override
  void dispose() {
    _raceClockTimer?.cancel();
    _raceViewController.dispose();
    if (_lastReportedRecording == true) {
      widget.onRecordingChanged?.call(false);
    }
    _locationService.removeListener(_handleLocationServiceChanged);
    _locationService.dispose();
    super.dispose();
  }

  void _handleLocationServiceChanged() {
    if (!mounted) return;
    if (_consumePendingLocationFix()) {
      return;
    }
    setState(() {});
  }

  bool _consumePendingLocationFix() {
    final fix = _locationService.position;
    if (fix == null) return false;
    if (_locationService.fixVersion == _lastProcessedFixVersion) return false;
    if (_raceState != _RaceState.running) {
      return false;
    }
    _lastProcessedFixVersion = _locationService.fixVersion;
    _processRaceFix(fix);
    return true;
  }

  @override
  void didUpdateWidget(covariant RaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFingerprint = _courseFingerprint(oldWidget.course);
    final newFingerprint = _courseFingerprint(widget.course);
    if (oldFingerprint != newFingerprint &&
        _courseFingerprint(_selectedCourse) == oldFingerprint &&
        (_raceState == _RaceState.stopped ||
            _raceState == _RaceState.finished)) {
      _selectedCourse = _copyCourse(widget.course);
    }
  }

  Future<void> _loadCourseEntries() async {
    final entries = await _courseLibrary.listAll();
    if (!mounted) return;
    setState(() {
      _courseEntries = entries;
      _loadingCourses = false;
    });
  }

  Future<void> _selectCourse(Course course) async {
    if (_raceState == _RaceState.running) {
      return;
    }
    setState(() {
      _selectedCourse = _copyCourse(course);
      _currentMark = 0;
      _finishMessage = null;
      _raceError = null;
      _track.clear();
    });
    widget.onCourseChanged?.call(_copyCourse(course));
  }

  String _courseFingerprint(Course course) => course.encode();

  Course _copyCourse(Course course) => Course.decode(course.encode());

  Duration get _startOffset => Duration(minutes: _startOffsetMinutes);
  RaceClockDisplay get _raceClock => buildRaceClockDisplay(
        startedAt: _raceStartedAt,
        elapsed: _raceClockElapsed,
        startOffset: _startOffset,
      );
  CourseMetrics get _selectedCourseMetrics =>
      buildCourseMetrics(_selectedCourse);

  void _startRaceClock() {
    _raceClockTimer?.cancel();
    _raceClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _raceStartedAt == null) return;
      setState(() {
        _raceClockElapsed += const Duration(seconds: 1);
      });
    });
  }

  void _stopRaceClock() {
    _raceClockTimer?.cancel();
    _raceClockTimer = null;
  }

  String _startOffsetLabel(int minutes) {
    if (minutes == 0) return 'Now';
    if (minutes == 1) return '1 min';
    return '$minutes mins';
  }

  void _reportRecordingChanged() {
    final isRecording = _raceState == _RaceState.running;
    if (_lastReportedRecording == isRecording) return;
    _lastReportedRecording = isRecording;
    widget.onRecordingChanged?.call(isRecording);
  }

  void _setRaceView(int index, {bool animate = false}) {
    if (_raceViewIndex != index && mounted) {
      setState(() => _raceViewIndex = index);
    }
    if (!_raceViewController.hasClients) return;
    if (animate) {
      unawaited(
        _raceViewController.animateToPage(
          index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
      return;
    }
    _raceViewController.jumpToPage(index);
  }

  Future<void> _startRace() async {
    try {
      if (!mounted) return;
      setState(() {
        _raceError = null;
        _finishMessage = null;
        _raceStartedAt = DateTime.now().toUtc();
        _raceClockElapsed = Duration.zero;
        _currentMark = 0;
        _raceViewIndex = 0;
        _track.clear();
        _finishingRace = false;
        _lastProcessedFixVersion = 0;
      });
      _setRaceView(0);
      final err = await _locationService.start();
      if (!mounted) return;
      if (err != null) {
        _handleLocationStartupError(err);
        return;
      }
      setState(() => _raceState = _RaceState.running);
      _consumePendingLocationFix();
      _startRaceClock();
      _reportRecordingChanged();
      AppAnalytics.instance.logRaceStarted(
        markCount: _selectedCourse.buoys.length,
        startOffsetMinutes: _startOffsetMinutes,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _raceError = e.toString();
        _raceState = _RaceState.stopped;
        _raceStartedAt = null;
        _raceClockElapsed = Duration.zero;
      });
      _stopRaceClock();
      unawaited(_locationService.stop(clearPosition: true));
      _reportRecordingChanged();
    }
  }

  void _handleLocationStartupError(String error) {
    setState(() {
      _raceError = null;
      _raceState = _RaceState.stopped;
      _raceStartedAt = null;
      _raceClockElapsed = Duration.zero;
    });
    _stopRaceClock();
    _reportRecordingChanged();
    if (isLocationServicesDisabledError(error) ||
        isLocationPermissionError(error)) {
      _showLocationErrorDialog(error);
    }
  }

  void _showLocationErrorDialog(String error) {
    if (!mounted) return;
    final actionLabel = isLocationServicesDisabledError(error)
        ? 'Open Location Services'
        : 'Open Settings';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location Access Needed'),
        content: Text(
          isLocationServicesDisabledError(error)
              ? 'Turn on Location Services to start recording the race.'
              : 'Allow Race Mate to access your location so it can record the race.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _openSettingsForLocationError(error);
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettingsForLocationError(String error) async {
    if (isLocationServicesDisabledError(error)) {
      await Geolocator.openLocationSettings();
      return;
    }
    if (isLocationPermissionError(error)) {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _confirmAndFinishRace() async {
    if (_finishingRace || _raceStartedAt == null) return;

    final finishedAt = DateTime.now().toUtc();
    final duration = computeOfficialRaceDuration(
      startedAt: _raceStartedAt,
      timestamp: finishedAt,
      startOffset: _startOffset,
    );
    final pointCount = _track.length;
    final markLabel =
        'Mark ${_currentMark + 1} of ${_selectedCourse.buoys.length}';
    final durationLabel = duration.inMinutes > 0
        ? '${duration.inMinutes}m ${duration.inSeconds % 60}s'
        : '${duration.inSeconds}s';
    final pointLabel =
        pointCount == 1 ? '1 GPS point' : '$pointCount GPS points';

    final shouldFinish = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish race?'),
        content: Text(
          'This will stop tracking and save the race to the library.\n\n'
          '$markLabel\n'
          '$durationLabel elapsed\n'
          '$pointLabel recorded',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep racing'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.flag),
            label: const Text('Finish & save'),
          ),
        ],
      ),
    );

    if (shouldFinish == true) {
      await _finishRace();
    }
  }

  Future<void> _finishRace({bool completedCourse = false}) async {
    if (_finishingRace || _raceStartedAt == null) return;
    _finishingRace = true;

    final finishedAt = DateTime.now().toUtc();
    final pointCount = _track.length;
    final duration = computeOfficialRaceDuration(
      startedAt: _raceStartedAt,
      timestamp: finishedAt,
      startOffset: _startOffset,
    );
    final finishMessage = _buildFinishMessage(
      completedCourse: completedCourse,
      pointCount: pointCount,
      duration: duration,
    );
    final record = RaceSessionRecord(
      courseName: _selectedCourse.name,
      startedAt: _raceStartedAt!,
      finishedAt: finishedAt,
      totalMarks: _selectedCourse.buoys.length,
      finalMarkIndex: _currentMark,
      completedCourse: completedCourse,
      track: List<RaceTrackPoint>.unmodifiable(_track),
    );

    _locationService.pause();
    _stopRaceClock();
    if (mounted) {
      setState(() {
        _raceState = _RaceState.finished;
        _raceError = null;
        _finishMessage = finishMessage;
        _raceClockElapsed = finishedAt.difference(_raceStartedAt!);
      });
      _reportRecordingChanged();
    }
    try {
      await _sessionStore.saveCompleted(record);
      await _locationService.stop(clearError: true);
      AppAnalytics.instance.logRaceFinished(
        totalMarks: _selectedCourse.buoys.length,
        finalMarkIndex: _currentMark,
        completedCourse: completedCourse,
        durationSeconds: duration.inSeconds,
        trackPointCount: pointCount,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(finishMessage)));
    } catch (e) {
      if (!mounted) return;
      _locationService.resume();
      _startRaceClock();
      setState(() {
        _raceState = _RaceState.running;
        _raceError = 'Could not save race data: $e';
      });
      _reportRecordingChanged();
      _finishingRace = false;
    }
  }

  String _buildFinishMessage({
    required bool completedCourse,
    required int pointCount,
    required Duration duration,
  }) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final durationText =
        minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
    final summary =
        pointCount == 1 ? 'Saved 1 GPS point' : 'Saved $pointCount GPS points';
    if (completedCourse) {
      return 'Race finished. $summary over $durationText. GPX added to library.';
    }
    return 'Race saved. $summary over $durationText. GPX added to library.';
  }

  void _processRaceFix(Position p) {
    final point = RaceTrackPoint.fromPosition(p);
    final progress = computeRaceProgress(
      fix: p,
      course: _selectedCourse,
      currentMarkIndex: _currentMark,
      autoAdvance: _autoAdvance,
      canFinishRace: _raceState == _RaceState.running,
    );
    setState(() {
      _raceError = null;
      _track.add(point);
      _currentMark = progress.nextMarkIndex;
    });
    if (progress.reachedFinish) {
      unawaited(_finishRace(completedCourse: true));
    }
  }

  void _prev() {
    if (_currentMark > 0) setState(() => _currentMark--);
  }

  void _next() {
    if (_currentMark < _selectedCourse.buoys.length - 1) {
      setState(() => _currentMark++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buoys = _selectedCourse.buoys;
    if (buoys.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Race')),
        body: const Center(
            child: Text(
                'Add buoys to create the course on the Course tab or choose one of the existing courses.')),
      );
    }

    final mark = buoys[_currentMark];
    final metrics = buildActiveRaceMetrics(
      fix: _locationService.position,
      mark: mark,
    );
    final fix = metrics.fix;
    final distance = metrics.distanceMeters;
    final bearing = metrics.bearingDegrees;
    final sog = metrics.speedMs;
    final cog = metrics.headingDegrees;
    final vmg = metrics.vmgMs;
    final etaSeconds = metrics.etaSeconds;
    final clock = _raceClock;

    return Scaffold(
      appBar: AppBar(
        title: _raceState == _RaceState.running
            ? Column(
                key: const Key('race-app-bar-timer'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clock.caption,
                    key: const Key('race-app-bar-timer-caption'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    clock.label,
                    key: const Key('race-app-bar-timer-value'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : const Text('Race'),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Auto'),
              Tooltip(
                message:
                    'Auto-advance steps to the next mark automatically when\n'
                    'the boat enters the rounding radius.',
                child: const Icon(Icons.info_outline, size: 16),
              ),
              Switch(
                value: _autoAdvance,
                onChanged: (v) => setState(() => _autoAdvance = v),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_raceState == _RaceState.running)
              _buildGpsStatusBanner(context),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_raceState == _RaceState.stopped ||
                      _raceState == _RaceState.finished) {
                    return _buildLauncherBody(mark: mark, fix: fix);
                  }
                  return _buildActiveRaceBody(
                    mark: mark,
                    fix: fix,
                    buoys: buoys,
                    distance: distance,
                    bearing: bearing,
                    sog: sog,
                    cog: cog,
                    vmg: vmg,
                    etaSeconds: etaSeconds,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsStatusBanner(BuildContext context) {
    if (_locationService.showNoSignal) {
      return ColoredBox(
        color: Colors.orange.shade700,
        child: const SizedBox(
          width: double.infinity,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gps_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'No GPS Signal',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_displayError != null || _locationService.hasReceivedFix) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.gps_not_fixed,
                  color: colors.onSurfaceVariant, size: 16),
              const SizedBox(width: 8),
              Text(
                'Acquiring GPS...',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveRaceBody({
    required Buoy mark,
    required Position? fix,
    required List<Buoy> buoys,
    required double? distance,
    required double? bearing,
    required double sog,
    required double cog,
    required double vmg,
    required int? etaSeconds,
  }) {
    return OrientationBuilder(
      builder: (context, orientation) {
        final overview = orientation == Orientation.landscape
            ? _buildLandscapeBody(
                key: const Key('race-view-overview'),
                mark: mark,
                fix: fix,
                buoys: buoys,
                distance: distance,
                bearing: bearing,
                sog: sog,
                cog: cog,
                vmg: vmg,
                etaSeconds: etaSeconds,
              )
            : _buildPortraitBody(
                key: const Key('race-view-overview'),
                mark: mark,
                fix: fix,
                buoys: buoys,
                distance: distance,
                bearing: bearing,
                sog: sog,
                cog: cog,
                vmg: vmg,
                etaSeconds: etaSeconds,
              );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _buildRaceViewSelector(),
            ),
            Expanded(
              child: PageView(
                key: const Key('race-view-pager'),
                controller: _raceViewController,
                onPageChanged: (index) {
                  if (_raceViewIndex == index) return;
                  setState(() => _raceViewIndex = index);
                },
                children: [
                  overview,
                  _buildVmgFocusBody(
                    mark: mark,
                    fix: fix,
                    buoys: buoys,
                    vmg: vmg,
                  ),
                  _buildHeadingBearingBody(
                    mark: mark,
                    fix: fix,
                    buoys: buoys,
                    bearing: bearing,
                    distance: distance,
                    heading: cog,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _finishRaceButton(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRaceViewSelector() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _raceViewLabels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ChoiceChip(
            label: Text(_raceViewLabels[index]),
            selected: _raceViewIndex == index,
            onSelected: (selected) {
              if (!selected) return;
              _setRaceView(index, animate: true);
            },
          );
        },
      ),
    );
  }

  Widget _buildLauncherBody({required Buoy mark, required Position? fix}) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _launcherCard(mark: mark),
        const SizedBox(height: 16),
        _coursePreviewCard(fix),
        if (_displayError != null) ...[
          const SizedBox(height: 16),
          _errorCard(_displayError!),
        ],
      ],
    );
  }

  Widget _launcherCard({required Buoy mark}) {
    final options = _buildCourseOptions();
    final selectedKey = _courseFingerprint(_selectedCourse);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _raceState == _RaceState.finished
                  ? 'Race saved'
                  : 'Ready to race',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _raceState == _RaceState.finished
                  ? (_finishMessage ??
                      'Your race has been saved to the library.')
                  : 'Pick a course, check the layout, and start tracking when you are lined up.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('race-course-picker'),
              isExpanded: true,
              initialValue: options.any((option) => option.key == selectedKey)
                  ? selectedKey
                  : null,
              decoration: const InputDecoration(
                labelText: 'Race course',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.route_outlined),
              ),
              items: options
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option.key,
                      child: Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _loadingCourses
                  ? null
                  : (value) {
                      Course? next;
                      for (final option in options) {
                        if (option.key == value) {
                          next = option.course;
                          break;
                        }
                      }
                      if (next != null) {
                        unawaited(_selectCourse(next));
                      }
                    },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _courseChip(
                  Icons.flag_outlined,
                  '${_selectedCourse.buoys.length} marks',
                ),
                _courseChip(Icons.place_outlined, 'Next: ${mark.name}'),
                _courseChip(
                  Icons.radio_button_checked,
                  'Radius ${mark.roundingRadiusM.toStringAsFixed(0)} m',
                ),
                if (_selectedCourse.buoys.length >= 2)
                  _courseChip(
                    Icons.straighten,
                    '${metersToNm(_selectedCourseMetrics.totalDistanceMeters).toStringAsFixed(1)} NM total',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Start timer',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _startOffsetOptions
                  .map(
                    (minutes) => ChoiceChip(
                      key: Key('start-offset-$minutes'),
                      label: Text(_startOffsetLabel(minutes)),
                      selected: _startOffsetMinutes == minutes,
                      onSelected: (selected) {
                        if (!selected) return;
                        setState(() => _startOffsetMinutes = minutes);
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 8),
            Text(
              _startOffsetMinutes == 0
                  ? 'Starts counting up immediately.'
                  : 'Counts down first, then rolls into elapsed race time.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _startRace,
              icon: const Icon(Icons.play_arrow),
              label: Text(
                _raceState == _RaceState.finished
                    ? 'Start new race'
                    : 'Start race',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coursePreviewCard(Position? fix) {
    final boat = fix == null ? null : LatLng(fix.latitude, fix.longitude);
    final track = _track
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedCourse.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Course preview',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 240,
            child: ColoredBox(
              color: const Color(0xFFEAF3FA),
              child: CustomPaint(
                painter: CourseMapPainter(
                  course: _selectedCourse,
                  boat: boat,
                  heading: fix?.heading ?? 0,
                  speedMs: fix?.speed ?? 0,
                  track: track,
                  currentMarkIndex: _currentMark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _finishRaceButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.tonalIcon(
        key: const Key('finish-race-button'),
        onPressed: _finishingRace ? null : _confirmAndFinishRace,
        icon: const Icon(Icons.flag_outlined, size: 18),
        label: const Text('Finish'),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  List<_RaceCourseOption> _buildCourseOptions() {
    final options = <_RaceCourseOption>[];
    final seen = <String>{};

    void addOption(Course course, String sourceLabel) {
      final key = _courseFingerprint(course);
      if (!seen.add(key)) return;
      options.add(
        _RaceCourseOption(
          key: key,
          course: _copyCourse(course),
          label: sourceLabel.isEmpty
              ? course.name
              : '${course.name} · $sourceLabel',
        ),
      );
    }

    addOption(widget.course, '');
    for (final entry in _courseEntries) {
      addOption(entry.course, entry.isBundled ? 'bundled' : 'saved');
    }
    return options;
  }

  Widget _courseChip(IconData icon, String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }

  /// Portrait layout: vertical column with VMG at top, metrics below, nav at
  /// the bottom.
  Widget _buildPortraitBody({
    Key? key,
    required Buoy mark,
    required Position? fix,
    required List<Buoy> buoys,
    required double? distance,
    required double? bearing,
    required double sog,
    required double cog,
    required double vmg,
    required int? etaSeconds,
  }) {
    return KeyedSubtree(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _markHeader(mark),
                    const SizedBox(height: 16),
                    if (_displayError != null)
                      _errorCard(_displayError!)
                    else if (fix == null)
                      const _Waiting()
                    else ...[
                      _bigMetric(
                        label: 'VMG to mark',
                        value: msToKnots(vmg).toStringAsFixed(2),
                        unit: 'kn',
                        good: vmg > 0,
                      ),
                      const SizedBox(height: 12),
                      _secondaryMetricsGrid(
                        distance: distance,
                        bearing: bearing,
                        sog: sog,
                        cog: cog,
                        compactThreshold: 480,
                      ),
                      const SizedBox(height: 12),
                      _metric(
                        'ETA at current VMG',
                        etaSeconds == null
                            ? '--:--'
                            : formatEta(Duration(seconds: etaSeconds)),
                        '',
                      ),
                      const SizedBox(height: 16),
                      _fixSummary(fix),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _navButtons(buoys),
          ],
        ),
      ),
    );
  }

  /// Landscape layout: 3-column row.
  ///
  /// Left  — mark header + Previous/Next buttons.
  /// Centre — VMG (the most important metric, prominently centred).
  /// Right — secondary metrics: Distance, Bearing, SOG, COG, ETA, fix info.
  Widget _buildLandscapeBody({
    Key? key,
    required Buoy mark,
    required Position? fix,
    required List<Buoy> buoys,
    required double? distance,
    required double? bearing,
    required double sog,
    required double cog,
    required double vmg,
    required int? etaSeconds,
  }) {
    final screenSize = MediaQuery.sizeOf(context);
    final compactLandscape =
        screenSize.width < 760 || screenSize.height < 420;
    if (compactLandscape) {
      return _buildCompactLandscapeBody(
        key: key,
        mark: mark,
        fix: fix,
        buoys: buoys,
        distance: distance,
        bearing: bearing,
        sog: sog,
        cog: cog,
        vmg: vmg,
        etaSeconds: etaSeconds,
      );
    }

    return KeyedSubtree(
      key: key,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left: mark info + nav ──────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(child: _markHeader(mark)),
                  ),
                  const SizedBox(height: 12),
                  _navButtons(buoys, direction: Axis.vertical),
                ],
              ),
            ),
          ),

          // ── Centre: VMG ────────────────────────────────────────────────────
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              child: Center(
                child: _raceState == _RaceState.stopped
                    ? const SizedBox.shrink()
                    : _raceState == _RaceState.finished
                        ? const SizedBox.shrink()
                        : _displayError != null
                            ? _errorCard(_displayError!)
                            : fix == null
                                ? const _Waiting()
                                : _bigMetric(
                                    label: 'VMG to mark',
                                    value: msToKnots(vmg).toStringAsFixed(2),
                                    unit: 'kn',
                                    good: vmg > 0,
                                  ),
              ),
            ),
          ),

          // ── Right: secondary metrics ───────────────────────────────────────
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
              child: (_raceState == _RaceState.stopped ||
                      _raceState == _RaceState.finished ||
                      _displayError != null ||
                      fix == null)
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _secondaryMetricsGrid(
                            distance: distance,
                            bearing: bearing,
                            sog: sog,
                            cog: cog,
                            compactThreshold: 420,
                            spacing: 8,
                          ),
                          const SizedBox(height: 8),
                          _metric(
                            'ETA at current VMG',
                            etaSeconds == null
                                ? '--:--'
                                : formatEta(Duration(seconds: etaSeconds)),
                            '',
                          ),
                          const SizedBox(height: 8),
                          _fixSummary(fix),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLandscapeBody({
    Key? key,
    required Buoy mark,
    required Position? fix,
    required List<Buoy> buoys,
    required double? distance,
    required double? bearing,
    required double sog,
    required double cog,
    required double vmg,
    required int? etaSeconds,
  }) {
    return KeyedSubtree(
      key: key,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _markHeader(mark),
                    const SizedBox(height: 12),
                    if (_displayError != null)
                      _errorCard(_displayError!)
                    else if (fix == null)
                      const _Waiting()
                    else ...[
                      _bigMetric(
                        label: 'VMG to mark',
                        value: msToKnots(vmg).toStringAsFixed(2),
                        unit: 'kn',
                        good: vmg > 0,
                      ),
                      const SizedBox(height: 10),
                      _secondaryMetricsGrid(
                        distance: distance,
                        bearing: bearing,
                        sog: sog,
                        cog: cog,
                        compactThreshold: 560,
                        spacing: 10,
                      ),
                      const SizedBox(height: 10),
                      _metric(
                        'ETA at current VMG',
                        etaSeconds == null
                            ? '--:--'
                            : formatEta(Duration(seconds: etaSeconds)),
                        '',
                      ),
                      const SizedBox(height: 10),
                      _fixSummary(fix),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _navButtons(buoys),
          ],
        ),
      ),
    );
  }

  Widget _buildVmgFocusBody({
    required Buoy mark,
    required Position? fix,
    required List<Buoy> buoys,
    required double vmg,
  }) {
    return KeyedSubtree(
      key: const Key('race-view-vmg'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _markHeader(mark),
                    const SizedBox(height: 16),
                    Text(
                      'VMG focus',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A clean, high-contrast view of velocity made good toward the active mark.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (_displayError != null)
                      _errorCard(_displayError!)
                    else if (fix == null)
                      const _Waiting()
                    else
                      _bigMetric(
                        label: 'VMG to mark',
                        value: msToKnots(vmg).toStringAsFixed(2),
                        unit: 'kn',
                        good: vmg > 0,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _navButtons(buoys),
          ],
        ),
      ),
    );
  }

  Widget _buildHeadingBearingBody({
    required Buoy mark,
    required Position? fix,
    required List<Buoy> buoys,
    required double heading,
    required double? bearing,
    required double? distance,
  }) {
    return KeyedSubtree(
      key: const Key('race-view-heading'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _markHeader(mark),
                    const SizedBox(height: 16),
                    Text(
                      'Heading to waypoint',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_displayError != null)
                      _errorCard(_displayError!)
                    else if (fix == null)
                      const _Waiting()
                    else ...[
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 640;
                          final headingCard = _directionMetric(
                            label: 'Heading',
                            value: '${heading.toStringAsFixed(0)}°',
                            direction: compass(heading),
                          );
                          final bearingCard = _directionMetric(
                            label: 'Bearing to waypoint',
                            value: bearing == null
                                ? '--'
                                : '${bearing.toStringAsFixed(0)}°',
                            direction: bearing == null ? '' : compass(bearing),
                          );
                          if (compact) {
                            return Column(
                              children: [
                                headingCard,
                                const SizedBox(height: 12),
                                bearingCard,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: headingCard),
                              const SizedBox(width: 12),
                              Expanded(child: bearingCard),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _metric(
                        'Turn',
                        _steeringAdjustmentLabel(heading, bearing),
                        '',
                      ),
                      const SizedBox(height: 12),
                      _metric(
                        'Distance',
                        distance == null
                            ? '--'
                            : metersToNm(distance).toStringAsFixed(2),
                        'NM',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _navButtons(buoys),
          ],
        ),
      ),
    );
  }

  Widget _navButtons(List<Buoy> buoys, {Axis direction = Axis.horizontal}) {
    final previousButton = OutlinedButton.icon(
      onPressed: _currentMark > 0 ? _prev : null,
      icon: const Icon(Icons.skip_previous),
      label: const Text('Previous'),
    );
    final nextButton = FilledButton.icon(
      onPressed: _currentMark < buoys.length - 1 ? _next : null,
      icon: const Icon(Icons.skip_next),
      label: const Text('Next mark'),
    );

    if (direction == Axis.vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [previousButton, const SizedBox(height: 12), nextButton],
      );
    }

    return Row(
      children: [
        Expanded(child: previousButton),
        const SizedBox(width: 12),
        Expanded(child: nextButton),
      ],
    );
  }

  Widget _markHeader(Buoy mark) {
    final buoys = _selectedCourse.buoys;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark ${_currentMark + 1} / ${buoys.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(mark.name, style: Theme.of(context).textTheme.headlineSmall),
            Text(
              '${mark.position.lat.toStringAsFixed(5)}, '
              '${mark.position.lng.toStringAsFixed(5)}  •  '
              'r=${mark.roundingRadiusM.toStringAsFixed(0)} m',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _steeringAdjustmentLabel(double heading, double? bearing) {
    if (bearing == null) return 'Waiting for bearing';
    final delta = ((bearing - heading + 540) % 360) - 180;
    final absDelta = delta.abs().round();
    if (absDelta < 5) return 'On target';
    final side = delta > 0 ? 'Starboard' : 'Port';
    return '$side $absDelta°';
  }

  Widget _bigMetric({
    required String label,
    required String value,
    required String unit,
    required bool good,
  }) {
    final color = good ? Colors.green.shade700 : Colors.red.shade700;
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(unit, style: TextStyle(fontSize: 22, color: color)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _directionMetric({
    required String label,
    required String value,
    required String direction,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style:
                    const TextStyle(fontSize: 40, fontWeight: FontWeight.w700),
              ),
            ),
            if (direction.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                direction,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, String unit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(unit, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secondaryMetricsGrid({
    required double? distance,
    required double? bearing,
    required double sog,
    required double cog,
    required double compactThreshold,
    double spacing = 12,
  }) {
    final tiles = <Widget>[
      _metric(
        'Distance',
        distance == null ? '--' : metersToNm(distance).toStringAsFixed(2),
        'NM',
      ),
      _metric(
        'Bearing',
        bearing == null ? '--' : '${bearing.toStringAsFixed(0)}°',
        bearing == null ? '' : compass(bearing),
      ),
      _metric(
        'SOG',
        msToKnots(sog).toStringAsFixed(2),
        'kn',
      ),
      _metric(
        'COG',
        '${cog.toStringAsFixed(0)}°',
        compass(cog),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < compactThreshold) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i < tiles.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: tiles[0]),
                SizedBox(width: spacing),
                Expanded(child: tiles[1]),
              ],
            ),
            SizedBox(height: spacing),
            Row(
              children: [
                Expanded(child: tiles[2]),
                SizedBox(width: spacing),
                Expanded(child: tiles[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _fixSummary(Position fix) {
    return Text(
      'Fix: ${fix.latitude.toStringAsFixed(5)}, '
      '${fix.longitude.toStringAsFixed(5)}  '
      '±${fix.accuracy.toStringAsFixed(0)} m',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget _errorCard(String msg) {
    final showSettingsAction =
        isLocationServicesDisabledError(msg) || isLocationPermissionError(msg);
    final settingsLabel = isLocationServicesDisabledError(msg)
        ? 'Open Location Services'
        : 'Open Settings';

    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
            if (showSettingsAction)
              TextButton(
                onPressed: () => _openSettingsForLocationError(msg),
                child: Text(settingsLabel),
              ),
            TextButton(onPressed: _startRace, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Acquiring GPS fix…'),
        ],
      ),
    );
  }
}

class _RaceCourseOption {
  const _RaceCourseOption({
    required this.key,
    required this.course,
    required this.label,
  });

  final String key;
  final Course course;
  final String label;
}
