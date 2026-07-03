import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../dev/course_map_painter.dart';
import '../models/course.dart';
import '../services/position_source.dart';
import '../utils/geo.dart';

enum _MapState { stopped, running, paused }

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.course,
    this.positionSource,
  });

  final Course course;
  final PositionSource? positionSource;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  StreamSubscription<Position>? _sub;
  late final PositionSource _source;
  late final bool _ownsSource;

  Position? _pos;
  String? _error;
  int _currentMark = 0;
  bool _autoAdvance = true;
  _MapState _mapState = _MapState.stopped;
  final List<LatLng> _track = [];

  @override
  void initState() {
    super.initState();
    if (widget.positionSource != null) {
      _source = widget.positionSource!;
      _ownsSource = false;
    } else {
      _source = GeolocatorPositionSource();
      _ownsSource = true;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_ownsSource) {
      _source.dispose();
    }
    super.dispose();
  }

  Future<void> _startTracking() async {
    try {
      if (_sub != null) {
        final oldSub = _sub;
        _sub = null;
        unawaited(oldSub?.cancel());
      }
      if (!mounted) return;
      setState(() {
        _error = null;
        _currentMark = 0;
        _pos = null;
        _track.clear();
      });
      final err = await _source.ensureReady();
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _error = err;
          _mapState = _MapState.stopped;
        });
        return;
      }
      setState(() => _mapState = _MapState.running);
      _sub = _source.stream.listen(_onFix, onError: (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _mapState = _MapState.stopped;
      });
    }
  }

  void _pauseTracking() {
    if (_sub == null) return;
    _sub!.pause();
    if (!mounted) return;
    setState(() {
      _error = null;
      _mapState = _MapState.paused;
    });
  }

  void _resumeTracking() {
    if (_sub == null) return;
    _sub!.resume();
    if (!mounted) return;
    setState(() {
      _error = null;
      _mapState = _MapState.running;
    });
  }

  Future<void> _stopTracking() async {
    await _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    setState(() {
      _mapState = _MapState.stopped;
      _currentMark = 0;
      _pos = null;
      _track.clear();
      _error = null;
    });
  }

  void _onFix(Position p) {
    setState(() {
      _pos = p;
      _track.add(LatLng(p.latitude, p.longitude));
      if (_autoAdvance && _currentMark < widget.course.buoys.length) {
        final mark = widget.course.buoys[_currentMark];
        final d =
            distanceMeters(LatLng(p.latitude, p.longitude), mark.position);
        if (d <= mark.roundingRadiusM &&
            _currentMark < widget.course.buoys.length - 1) {
          _currentMark++;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    if (course.buoys.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Map')),
        body: const Center(
          child: Text('Add buoys on the Course tab first.'),
        ),
      );
    }

    final mark = course.buoys[_currentMark];
    final boat = _pos == null
        ? _fallbackBoatPosition(course, _currentMark)
        : LatLng(_pos!.latitude, _pos!.longitude);
    final distance = _pos == null ? null : distanceMeters(boat, mark.position);
    final bearing = _pos == null ? null : bearingDegrees(boat, mark.position);
    final speedMs = _pos?.speed ?? 0.0;
    final heading = _pos?.heading ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          Row(
            children: [
              const Text('Auto'),
              Switch(
                value: _autoAdvance,
                onChanged: (value) => setState(() => _autoAdvance = value),
              ),
            ],
          ),
          IconButton(
            tooltip: switch (_mapState) {
              _MapState.running => 'Pause map',
              _MapState.paused => 'Resume map',
              _MapState.stopped => 'Start map',
            },
            icon: Icon(
              _mapState == _MapState.running ? Icons.pause : Icons.play_arrow,
            ),
            onPressed: switch (_mapState) {
              _MapState.running => _pauseTracking,
              _MapState.paused => _resumeTracking,
              _MapState.stopped => _startTracking,
            },
          ),
          IconButton(
            tooltip: 'Stop map',
            icon: const Icon(Icons.stop),
            onPressed: _mapState == _MapState.stopped ? null : _stopTracking,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  runSpacing: 12,
                  spacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _headerMetric(
                        'Mark', '${_currentMark + 1}/${course.buoys.length}'),
                    _headerMetric('Target', mark.name),
                    _headerMetric(
                      'Distance',
                      distance == null
                          ? '--'
                          : '${metersToNm(distance).toStringAsFixed(2)} NM',
                    ),
                    _headerMetric(
                      'Bearing',
                      bearing == null
                          ? '--'
                          : '${bearing.toStringAsFixed(0)}° ${compass(bearing)}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: CourseMapPainter(
                          course: course,
                          boat: boat,
                          heading: heading,
                          speedMs: speedMs,
                          track: _track,
                          currentMarkIndex: _currentMark,
                        ),
                      ),
                      if (_mapState == _MapState.stopped)
                        _centerNotice(
                          title: 'Map stopped',
                          message: 'Press Start to begin live map tracking.',
                        )
                      else if (_error != null)
                        _centerNotice(
                          title: 'Map error',
                          message: _error!,
                          isError: true,
                        )
                      else if (_pos == null)
                        _centerNotice(
                          title: 'Waiting for GPS',
                          message: 'Acquiring your first fix for the live map.',
                        ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Card(
                          color: Colors.white.withValues(alpha: 0.92),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _statusText(
                                mark: mark,
                                trackCount: _track.length,
                                position: _pos,
                              ),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  Widget _centerNotice({
    required String title,
    required String message,
    bool isError = false,
  }) {
    return Center(
      child: Card(
        color:
            isError ? Colors.red.shade50 : Colors.white.withValues(alpha: 0.95),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusText({
    required Buoy mark,
    required int trackCount,
    required Position? position,
  }) {
    if (position == null) {
      return 'Current target: ${mark.name}';
    }
    return 'Fix ${position.latitude.toStringAsFixed(5)}, '
        '${position.longitude.toStringAsFixed(5)} · '
        'SOG ${msToKnots(position.speed).toStringAsFixed(2)} kn · '
        'Track points $trackCount';
  }
}

LatLng _fallbackBoatPosition(Course course, int currentMark) {
  if (course.buoys.isEmpty) {
    return const LatLng(41.8868, -87.6101);
  }
  final target = course.buoys[currentMark.clamp(0, course.buoys.length - 1)];
  return destinationPoint(target.position, 150, 225);
}
