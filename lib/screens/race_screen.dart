import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/course.dart';
import '../services/course_library.dart';
import '../services/position_source.dart';
import '../services/race_session_store.dart';
import '../utils/geo.dart';
import '../widgets/course_map_painter.dart';

enum _RaceState { stopped, running, paused, finished }

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

  StreamSubscription<Position>? _sub;
  Timer? _raceClockTimer;
  late final PositionSource _source;
  late final bool _ownsSource;
  final _courseLibrary = CourseLibrary();
  final _sessionStore = RaceSessionStore();
  Position? _pos;
  String? _error;
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

  @override
  void initState() {
    super.initState();
    _selectedCourse = _copyCourse(widget.course);
    if (widget.positionSource != null) {
      _source = widget.positionSource!;
      _ownsSource = false;
    } else {
      _source = GeolocatorPositionSource();
      _ownsSource = true;
    }
    _reportRecordingChanged();
    unawaited(_loadCourseEntries());
  }

  @override
  void dispose() {
    _raceClockTimer?.cancel();
    if (_lastReportedRecording == true) {
      widget.onRecordingChanged?.call(false);
    }
    _sub?.cancel();
    if (_ownsSource) _source.dispose();
    super.dispose();
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
    if (_raceState == _RaceState.running || _raceState == _RaceState.paused) {
      return;
    }
    setState(() {
      _selectedCourse = _copyCourse(course);
      _currentMark = 0;
      _finishMessage = null;
      _error = null;
      _track.clear();
      _pos = null;
    });
    widget.onCourseChanged?.call(_copyCourse(course));
  }

  String _courseFingerprint(Course course) => course.encode();

  Course _copyCourse(Course course) => Course.decode(course.encode());

  Duration get _startOffset => Duration(minutes: _startOffsetMinutes);

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

  Duration _officialRaceDuration(DateTime timestamp) {
    final startedAt = _raceStartedAt;
    if (startedAt == null) return Duration.zero;
    final duration = timestamp.difference(startedAt) - _startOffset;
    return duration.isNegative ? Duration.zero : duration;
  }

  String _formatRaceClockLabel() {
    if (_raceStartedAt == null) return 'Ready to race';
    final remaining = _startOffset - _raceClockElapsed;
    if (remaining > Duration.zero) {
      return formatEta(remaining);
    }
    return formatEta(_raceClockElapsed - _startOffset);
  }

  String _raceClockCaption() {
    if (_raceStartedAt == null) return '';
    final remaining = _startOffset - _raceClockElapsed;
    return remaining > Duration.zero ? 'Start In' : 'Elapsed';
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

  Future<void> _startRace() async {
    try {
      if (_sub != null) {
        final oldSub = _sub;
        _sub = null;
        unawaited(oldSub?.cancel());
      }
      if (!mounted) return;
      setState(() {
        _error = null;
        _finishMessage = null;
        _raceStartedAt = DateTime.now().toUtc();
        _raceClockElapsed = Duration.zero;
        _currentMark = 0;
        _pos = null;
        _track.clear();
        _finishingRace = false;
      });
      final err = await _source.ensureReady();
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _error = err;
          _raceState = _RaceState.stopped;
          _raceStartedAt = null;
          _raceClockElapsed = Duration.zero;
        });
        _stopRaceClock();
        _reportRecordingChanged();
        return;
      }
      setState(() => _raceState = _RaceState.running);
      _startRaceClock();
      _reportRecordingChanged();
      _sub = _source.stream.listen(
        _onFix,
        onError: (e) {
          if (!mounted) return;
          setState(() => _error = e.toString());
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _raceState = _RaceState.stopped;
        _raceStartedAt = null;
        _raceClockElapsed = Duration.zero;
      });
      _stopRaceClock();
      _reportRecordingChanged();
    }
  }

  void _pauseRace() {
    if (_sub == null) return;
    _sub!.pause();
    if (!mounted) return;
    setState(() {
      _error = null;
      _raceState = _RaceState.paused;
    });
    _reportRecordingChanged();
  }

  void _resumeRace() {
    if (_sub == null) return;
    _sub!.resume();
    if (!mounted) return;
    setState(() {
      _error = null;
      _raceState = _RaceState.running;
    });
    _reportRecordingChanged();
  }

  Future<void> _confirmAndFinishRace() async {
    if (_finishingRace || _raceStartedAt == null) return;

    final finishedAt = DateTime.now().toUtc();
    final duration = _officialRaceDuration(finishedAt);
    final pointCount = _track.length;
    final markLabel =
        'Mark ${_currentMark + 1} of ${widget.course.buoys.length}';
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
    final duration = _officialRaceDuration(finishedAt);
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

    _sub?.pause();
    if (mounted) {
      setState(() {
        _raceState = _RaceState.finished;
        _error = null;
        _finishMessage = finishMessage;
        _raceClockElapsed = finishedAt.difference(_raceStartedAt!);
      });
      _reportRecordingChanged();
    }

    _stopRaceClock();
    await _sub?.cancel();
    _sub = null;
    try {
      await _sessionStore.saveCompleted(record);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(finishMessage)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _raceState = _RaceState.paused;
        _error = 'Could not save race data: $e';
      });
      _startRaceClock();
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

  void _onFix(Position p) {
    final point = RaceTrackPoint.fromPosition(p);
    var reachedFinish = false;
    setState(() {
      _pos = p;
      _track.add(point);
      if (_autoAdvance && _currentMark < _selectedCourse.buoys.length) {
        final mark = _selectedCourse.buoys[_currentMark];
        final d = distanceMeters(
          LatLng(p.latitude, p.longitude),
          mark.position,
        );
        if (d <= mark.roundingRadiusM) {
          if (_currentMark < _selectedCourse.buoys.length - 1) {
            _currentMark++;
          } else if (_raceState == _RaceState.running) {
            reachedFinish = true;
          }
        }
      }
    });
    if (reachedFinish) {
      unawaited(_finishRace(completedCourse: true));
    }
  }

  void _prev() {
    if (_currentMark > 0) setState(() => _currentMark--);
  }

  void _next() {
    if (_currentMark < widget.course.buoys.length - 1) {
      setState(() => _currentMark++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buoys = _selectedCourse.buoys;
    if (buoys.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Race')),
        body: const Center(child: Text('Add buoys on the Course tab first.')),
      );
    }

    final mark = buoys[_currentMark];
    final fix = _pos;
    final here = fix == null ? null : LatLng(fix.latitude, fix.longitude);

    final distance = here == null ? null : distanceMeters(here, mark.position);
    final bearing = here == null ? null : bearingDegrees(here, mark.position);
    final sog = fix?.speed ?? 0.0; // m/s
    final cog = fix?.heading ?? 0.0; // degrees true
    final vmg = (bearing == null) ? 0.0 : vmgMs(sog, cog, bearing);
    final etaSeconds =
        (vmg > 0.05 && distance != null) ? (distance / vmg).round() : null;

    return Scaffold(
      appBar: AppBar(
        title:
            _raceState == _RaceState.running || _raceState == _RaceState.paused
                ? Column(
                    key: const Key('race-app-bar-timer'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _raceClockCaption(),
                        key: const Key('race-app-bar-timer-caption'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        _formatRaceClockLabel(),
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
          if (_raceState == _RaceState.running ||
              _raceState == _RaceState.paused)
            IconButton(
              tooltip: switch (_raceState) {
                _RaceState.running => 'Pause race',
                _RaceState.paused => 'Resume race',
                _RaceState.stopped => 'Start race',
                _RaceState.finished => 'Start new race',
              },
              icon: Icon(
                _raceState == _RaceState.running
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              onPressed: switch (_raceState) {
                _RaceState.running => _pauseRace,
                _RaceState.paused => _resumeRace,
                _RaceState.stopped => _startRace,
                _RaceState.finished => _startRace,
              },
            ),
          IconButton(
            tooltip: 'Finish and save race',
            icon: const Icon(Icons.flag),
            onPressed: switch (_raceState) {
              _RaceState.running => _confirmAndFinishRace,
              _RaceState.paused => _confirmAndFinishRace,
              _RaceState.stopped => null,
              _RaceState.finished => null,
            },
          ),
        ],
      ),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            if (_raceState == _RaceState.stopped ||
                _raceState == _RaceState.finished) {
              return _buildLauncherBody(mark: mark, fix: fix);
            }
            if (orientation == Orientation.landscape) {
              return _buildLandscapeBody(
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
            return _buildPortraitBody(
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
    );
  }

  Widget _buildLauncherBody({required Buoy mark, required Position? fix}) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _launcherCard(mark: mark),
        const SizedBox(height: 16),
        _coursePreviewCard(fix),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _errorCard(_error!),
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
              value: options.any((option) => option.key == selectedKey)
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
                    () {
                      double total = 0;
                      final b = _selectedCourse.buoys;
                      for (int i = 0; i < b.length - 1; i++) {
                        total +=
                            distanceMeters(b[i].position, b[i + 1].position);
                      }
                      return '${metersToNm(total).toStringAsFixed(1)} NM total';
                    }(),
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
    return Padding(
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
                  if (_error != null)
                    _errorCard(_error!)
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
                    Row(
                      children: [
                        Expanded(
                          child: _metric(
                            'Distance',
                            distance == null
                                ? '--'
                                : metersToNm(distance).toStringAsFixed(2),
                            'NM',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _metric(
                            'Bearing',
                            bearing == null
                                ? '--'
                                : '${bearing.toStringAsFixed(0)}°',
                            bearing == null ? '' : compass(bearing),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _metric(
                            'SOG',
                            msToKnots(sog).toStringAsFixed(2),
                            'kn',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _metric(
                            'COG',
                            '${cog.toStringAsFixed(0)}°',
                            compass(cog),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _metric(
                      'ETA',
                      etaSeconds == null
                          ? '--:--'
                          : formatEta(Duration(seconds: etaSeconds)),
                      '',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Fix: ${fix.latitude.toStringAsFixed(5)}, '
                      '${fix.longitude.toStringAsFixed(5)}  '
                      '±${fix.accuracy.toStringAsFixed(0)} m',
                      style: Theme.of(context).textTheme.bodySmall,
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
    );
  }

  /// Landscape layout: 3-column row.
  ///
  /// Left  — mark header + Previous/Next buttons.
  /// Centre — VMG (the most important metric, prominently centred).
  /// Right — secondary metrics: Distance, Bearing, SOG, COG, ETA, fix info.
  Widget _buildLandscapeBody({
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
    return Row(
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
                      : _error != null
                          ? _errorCard(_error!)
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
                    _error != null ||
                    fix == null)
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _metric(
                                'Distance',
                                distance == null
                                    ? '--'
                                    : metersToNm(distance).toStringAsFixed(2),
                                'NM',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _metric(
                                'Bearing',
                                bearing == null
                                    ? '--'
                                    : '${bearing.toStringAsFixed(0)}°',
                                bearing == null ? '' : compass(bearing),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _metric(
                                'SOG',
                                msToKnots(sog).toStringAsFixed(2),
                                'kn',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _metric(
                                'COG',
                                '${cog.toStringAsFixed(0)}°',
                                compass(cog),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _metric(
                          'ETA',
                          etaSeconds == null
                              ? '--:--'
                              : formatEta(Duration(seconds: etaSeconds)),
                          '',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Fix: ${fix.latitude.toStringAsFixed(5)}, '
                          '${fix.longitude.toStringAsFixed(5)}  '
                          '±${fix.accuracy.toStringAsFixed(0)} m',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
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
    final buoys = widget.course.buoys;
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
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(unit, style: TextStyle(fontSize: 22, color: color)),
              ],
            ),
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
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(unit, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(String msg) => Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(child: Text(msg)),
              TextButton(onPressed: _startRace, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _statusCard({required String title, required String message}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
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
