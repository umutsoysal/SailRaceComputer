import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/course.dart';
import '../services/position_source.dart';
import '../utils/geo.dart';

enum _RaceState { stopped, running, paused }

/// Live race screen — shows the next mark with bearing, distance, SOG, COG,
/// and VMG toward the mark.
class RaceScreen extends StatefulWidget {
  final Course course;
  final PositionSource? positionSource;

  const RaceScreen({
    super.key,
    required this.course,
    this.positionSource,
  });

  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen> {
  StreamSubscription<Position>? _sub;
  late final PositionSource _source;
  late final bool _ownsSource;
  Position? _pos;
  String? _error;
  int _currentMark = 0;
  bool _autoAdvance = true;
  _RaceState _raceState = _RaceState.stopped;

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
    if (_ownsSource) _source.dispose();
    super.dispose();
  }

  Future<void> _startRace() async {
    try {
      if (_sub != null) {
        await _sub!.cancel();
        _sub = null;
      }
      if (!mounted) return;
      setState(() {
        _error = null;
      });
      final err = await _source.ensureReady();
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _error = err;
          _raceState = _RaceState.stopped;
        });
        return;
      }
      setState(() => _raceState = _RaceState.running);
      _sub = _source.stream.listen(_onFix, onError: (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _raceState = _RaceState.stopped;
      });
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
  }

  void _resumeRace() {
    if (_sub == null) return;
    _sub!.resume();
    if (!mounted) return;
    setState(() {
      _error = null;
      _raceState = _RaceState.running;
    });
  }

  void _stopRace() {
    _sub?.cancel(); // cancel() stops event delivery immediately; no need to await cleanup
    _sub = null;
    if (!mounted) return;
    setState(() {
      _raceState = _RaceState.stopped;
      _currentMark = 0;
      _pos = null;
      _error = null;
    });
  }

  void _onFix(Position p) {
    setState(() {
      _pos = p;
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
    final buoys = widget.course.buoys;
    if (buoys.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Race')),
        body: const Center(
          child: Text('Add buoys on the Course tab first.'),
        ),
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
        title: const Text('Race'),
        actions: [
          Row(children: [
            const Text('Auto'),
            Switch(
              value: _autoAdvance,
              onChanged: (v) => setState(() => _autoAdvance = v),
            ),
          ]),
          IconButton(
            tooltip: switch (_raceState) {
              _RaceState.running => 'Pause race',
              _RaceState.paused => 'Resume race',
              _RaceState.stopped => 'Start race',
            },
            icon: Icon(_raceState == _RaceState.running
                ? Icons.pause
                : Icons.play_arrow),
            onPressed: switch (_raceState) {
              _RaceState.running => _pauseRace,
              _RaceState.paused => _resumeRace,
              _RaceState.stopped => _startRace,
            },
          ),
          IconButton(
            tooltip: 'Stop race',
            icon: const Icon(Icons.stop),
            onPressed: _raceState == _RaceState.stopped ? null : _stopRace,
          ),
        ],
      ),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
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
                  if (_raceState == _RaceState.stopped)
                    _statusCard(
                      title: 'Race stopped',
                      message: 'Press Start to begin VMG tracking.',
                    )
                  else if (_error != null)
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
                    Row(children: [
                      Expanded(
                          child: _metric(
                              'Distance',
                              distance == null
                                  ? '--'
                                  : metersToNm(distance).toStringAsFixed(2),
                              'NM')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _metric(
                              'Bearing',
                              bearing == null
                                  ? '--'
                                  : '${bearing.toStringAsFixed(0)}°',
                              bearing == null ? '' : compass(bearing))),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _metric(
                              'SOG', msToKnots(sog).toStringAsFixed(2), 'kn')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _metric('COG', '${cog.toStringAsFixed(0)}°',
                              compass(cog))),
                    ]),
                    const SizedBox(height: 12),
                    _metric(
                      'ETA at current VMG',
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
                  ? _statusCard(
                      title: 'Race stopped',
                      message: 'Press Start to begin VMG tracking.',
                    )
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
                    _error != null ||
                    fix == null)
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                              child: _metric(
                                  'Distance',
                                  distance == null
                                      ? '--'
                                      : metersToNm(distance).toStringAsFixed(2),
                                  'NM')),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _metric(
                                  'Bearing',
                                  bearing == null
                                      ? '--'
                                      : '${bearing.toStringAsFixed(0)}°',
                                  bearing == null ? '' : compass(bearing))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: _metric('SOG',
                                  msToKnots(sog).toStringAsFixed(2), 'kn')),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _metric('COG',
                                  '${cog.toStringAsFixed(0)}°', compass(cog))),
                        ]),
                        const SizedBox(height: 8),
                        _metric(
                          'ETA at current VMG',
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
        children: [
          previousButton,
          const SizedBox(height: 12),
          nextButton,
        ],
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
            Text('Mark ${_currentMark + 1} / ${buoys.length}',
                style: Theme.of(context).textTheme.labelLarge),
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
                Text(value,
                    style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: color)),
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
                Text(value,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w600)),
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
              Text(
                message,
                textAlign: TextAlign.center,
              ),
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
