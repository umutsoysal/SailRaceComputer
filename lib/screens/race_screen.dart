import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/course.dart';
import '../utils/geo.dart';

/// Live race screen — shows the next mark with bearing, distance, SOG, COG,
/// and VMG toward the mark.
class RaceScreen extends StatefulWidget {
  final Course course;
  const RaceScreen({super.key, required this.course});

  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen> {
  StreamSubscription<Position>? _sub;
  Position? _pos;
  String? _error;
  int _currentMark = 0;
  bool _autoAdvance = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() => _error = 'Location services are disabled.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _error = 'Location permission denied.');
        return;
      }
      const settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
      _sub = Geolocator.getPositionStream(locationSettings: settings)
          .listen(_onFix, onError: (e) {
        setState(() => _error = e.toString());
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _onFix(Position p) {
    setState(() {
      _pos = p;
      if (_autoAdvance && _currentMark < widget.course.buoys.length) {
        final mark = widget.course.buoys[_currentMark];
        final d = distanceMeters(
            LatLng(p.latitude, p.longitude), mark.position);
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
    final vmg = (bearing == null)
        ? 0.0
        : vmgMs(sog, cog, bearing);
    final etaSeconds = (vmg > 0.05 && distance != null)
        ? (distance / vmg).round()
        : null;

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
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                      child: _metric('SOG',
                          msToKnots(sog).toStringAsFixed(2), 'kn')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _metric(
                          'COG', '${cog.toStringAsFixed(0)}°', compass(cog))),
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
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _currentMark > 0 ? _prev : null,
                      icon: const Icon(Icons.skip_previous),
                      label: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _currentMark < buoys.length - 1 ? _next : null,
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Next mark'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
            Text(mark.name,
                style: Theme.of(context).textTheme.headlineSmall),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(width: 8),
                Text(unit,
                    style: TextStyle(fontSize: 22, color: color)),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
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
              TextButton(onPressed: _start, child: const Text('Retry')),
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
