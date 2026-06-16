import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../app_shell.dart';
import '../models/course.dart';
import '../services/course_file.dart';
import '../services/course_store.dart';
import '../utils/geo.dart';
import 'boat_simulator.dart';
import 'course_map_painter.dart';
import 'simulated_position_source.dart';

/// Dev-only simulator: top-down map + draggable boat with heading/speed
/// controls. Drives the same VMG/bearing/distance math the production
/// Race screen uses, so you can validate behavior on your desk.
class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  final _store = CourseStore();
  Course? _course;
  late BoatSimulator _sim;
  SimulatedPositionSource? _posSource;
  int _currentMark = 0;
  bool _autoAdvance = true;
  /// When true, the phone preview is rendered in landscape orientation so the
  /// landscape layout of the Race screen can be tested without a physical
  /// device rotation.
  bool _previewLandscape = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final saved = await _store.load();
    final course = (saved != null && saved.buoys.isNotEmpty)
        ? saved
        : await _loadDemoCourse();
    final start = _startNear(course);
    final boat = BoatSimulator(
      startPosition: start,
      headingDeg: course.buoys.isNotEmpty
          ? bearingDegrees(start, course.buoys.first.position)
          : 0,
      speedKnots: 5,
    );
    boat.addListener(_onSimTick);
    setState(() {
      _course = course;
      _sim = boat;
      _posSource = SimulatedPositionSource(boat);
    });
  }

  void _onCourseChanged(Course updated) {
    setState(() => _course = updated);
    _store.save(updated);
    if (_currentMark >= updated.buoys.length) {
      setState(() => _currentMark = (updated.buoys.length - 1)
          .clamp(0, updated.buoys.length));
    }
  }

  void _addBuoyAt(LatLng pos) {
    final course = _course;
    if (course == null) return;
    final next = Course(
      name: course.name,
      buoys: [
        ...course.buoys,
        Buoy(name: 'M${course.buoys.length + 1}', position: pos),
      ],
    );
    _onCourseChanged(next);
  }

  void _onSimTick() {
    final course = _course;
    if (course == null) return;
    if (_autoAdvance && _currentMark < course.buoys.length) {
      final mark = course.buoys[_currentMark];
      final d = distanceMeters(_sim.position, mark.position);
      if (d <= mark.roundingRadiusM &&
          _currentMark < course.buoys.length - 1) {
        setState(() => _currentMark++);
        return;
      }
    }
    setState(() {});
  }

  /// Loads the bundled demo course from
  /// `assets/courses/demo_chicago.srcourse.json`. Falls back to an empty
  /// in-memory course if the asset is missing or malformed.
  Future<Course> _loadDemoCourse() async {
    try {
      final raw = await rootBundle
          .loadString('assets/courses/demo_chicago.srcourse.json');
      return CourseFile.decode(raw);
    } catch (_) {
      return Course(name: 'Empty Course', buoys: const []);
    }
  }

  LatLng _startNear(Course c) {
    if (c.buoys.isEmpty) return const LatLng(41.8868, -87.6101);
    // 100 m south-west of mark 1
    return destinationPoint(c.buoys.first.position, 150, 225);
  }

  @override
  void dispose() {
    _sim.removeListener(_onSimTick);
    _posSource?.dispose();
    _sim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final course = _course;
    if (course == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final mark = course.buoys.isEmpty ? null : course.buoys[_currentMark];
    final dist = mark == null ? null : distanceMeters(_sim.position, mark.position);
    final brg = mark == null ? null : bearingDegrees(_sim.position, mark.position);
    final vmg = (brg == null)
        ? 0.0
        : vmgMs(_sim.speedMs, _sim.headingDeg, brg);
    final etaSec =
        (vmg > 0.05 && dist != null) ? (dist / vmg).round() : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulator (dev)'),
        actions: [
          Row(children: [
            const Text('Auto'),
            Switch(
              value: _autoAdvance,
              onChanged: (v) => setState(() => _autoAdvance = v),
            ),
          ]),
          IconButton(
            tooltip: _sim.running ? 'Pause' : 'Start',
            icon: Icon(_sim.running ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(_sim.toggle),
          ),
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt),
            onPressed: () {
              setState(() {
                _currentMark = 0;
                _sim.reset(_startNear(course));
                if (course.buoys.isNotEmpty) {
                  _sim.setHeading(bearingDegrees(
                      _sim.position, course.buoys.first.position));
                }
              });
            },
          ),
          IconButton(
            tooltip: _previewLandscape
                ? 'Switch preview to portrait'
                : 'Switch preview to landscape',
            icon: Icon(_previewLandscape
                ? Icons.stay_current_portrait
                : Icons.stay_current_landscape),
            onPressed: () =>
                setState(() => _previewLandscape = !_previewLandscape),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (ctx, c) {
        final wide = c.maxWidth > 1200;
        final medium = c.maxWidth > 900;
        final map = _MapPanel(
          course: course,
          sim: _sim,
          currentMark: _currentMark,
          onTeleport: (pos) {
            _sim.teleport(pos);
            if (mark != null) {
              _sim.setHeading(bearingDegrees(pos, mark.position));
            }
          },
          onLongPress: _addBuoyAt,
        );
        final controls = _ControlPanel(
          sim: _sim,
          mark: mark,
          distance: dist,
          bearing: brg,
          vmg: vmg,
          etaSec: etaSec,
          currentMark: _currentMark,
          markCount: course.buoys.length,
          onPrev: () {
            if (_currentMark > 0) setState(() => _currentMark--);
          },
          onNext: () {
            if (_currentMark < course.buoys.length - 1) {
              setState(() => _currentMark++);
            }
          },
        );
        final preview = _PhonePreview(
          landscape: _previewLandscape,
          child: AppShell(
            key: const ValueKey('sim-app-shell'),
            course: course,
            onCourseChanged: _onCourseChanged,
            positionSource: _posSource,
            initialTab: 0,
          ),
        );

        if (wide) {
          return Row(children: [
            Expanded(flex: 3, child: map),
            preview,
            SizedBox(width: 360, child: controls),
          ]);
        }
        if (medium) {
          return Row(children: [
            Expanded(
              flex: 3,
              child: Column(children: [
                Expanded(flex: 3, child: map),
                Expanded(flex: 2, child: controls),
              ]),
            ),
            preview,
          ]);
        }
        return DefaultTabController(
          length: 2,
          child: Column(children: [
            const Material(
              color: Colors.transparent,
              child: TabBar(tabs: [
                Tab(icon: Icon(Icons.map), text: 'Simulator'),
                Tab(icon: Icon(Icons.phone_iphone), text: 'App preview'),
              ]),
            ),
            Expanded(
              child: TabBarView(children: [
                Column(children: [
                  Expanded(flex: 3, child: map),
                  Expanded(flex: 2, child: controls),
                ]),
                Center(child: preview),
              ]),
            ),
          ]),
        );
      }),
    );
  }
}

class _PhonePreview extends StatelessWidget {
  const _PhonePreview({required this.child, this.landscape = false});
  final Widget child;
  /// When true, the preview frame is rotated to a landscape aspect ratio so
  /// the horizontal-screen layout can be tested on the desk.
  final bool landscape;

  /// Logical height injected into [MediaQueryData] for the portrait preview
  /// so [OrientationBuilder] inside the app shell sees portrait orientation.
  static const double _portraitPreviewHeight = 700;

  @override
  Widget build(BuildContext context) {
    // Portrait: 360 × unconstrained height (fills the parent vertically).
    // Landscape: 640 × 360 fixed.
    final double width = landscape ? 640 : 360;
    final double? height = landscape ? 360 : null;

    final phone = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.black87, width: 6),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: MediaQuery(
              // Provide a media-query that matches the preview dimensions so
              // OrientationBuilder inside the app shell sees the right
              // orientation.
              data: MediaQueryData(
                size: Size(
                  width - (6 * 2), // subtract border widths (6 each side)
                  landscape ? height! - (6 * 2) : _portraitPreviewHeight,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    return phone;
  }
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({
    required this.course,
    required this.sim,
    required this.currentMark,
    required this.onTeleport,
    required this.onLongPress,
  });

  final Course course;
  final BoatSimulator sim;
  final int currentMark;
  final ValueChanged<LatLng> onTeleport;
  final ValueChanged<LatLng> onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(builder: (ctx, c) {
          final painter = CourseMapPainter(
            course: course,
            boat: sim.position,
            heading: sim.headingDeg,
            speedMs: sim.speedMs,
            track: sim.track,
            currentMarkIndex: currentMark,
          );
          LatLng? translate(Offset p) {
            final size = Size(c.maxWidth, c.maxHeight);
            painter.paint(_NoOpCanvas(), size);
            return painter.canvasToLatLng(p);
          }
          return GestureDetector(
            onTapDown: (d) {
              final ll = translate(d.localPosition);
              if (ll != null) onTeleport(ll);
            },
            onLongPressStart: (d) {
              final ll = translate(d.localPosition);
              if (ll != null) onLongPress(ll);
            },
            child: CustomPaint(
              size: Size.infinite,
              painter: painter,
            ),
          );
        }),
      ),
    );
  }
}

/// Minimal Canvas stand-in so we can call painter.paint() purely to build the
/// internal projection without actually drawing. Cheap enough on tap.
class _NoOpCanvas implements Canvas {
  @override
  noSuchMethod(Invocation invocation) => null;
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.sim,
    required this.mark,
    required this.distance,
    required this.bearing,
    required this.vmg,
    required this.etaSec,
    required this.currentMark,
    required this.markCount,
    required this.onPrev,
    required this.onNext,
  });

  final BoatSimulator sim;
  final Buoy? mark;
  final double? distance;
  final double? bearing;
  final double vmg;
  final int? etaSec;
  final int currentMark;
  final int markCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mark != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mark ${currentMark + 1} / $markCount',
                        style: Theme.of(context).textTheme.labelLarge),
                    Text(mark!.name,
                        style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          _bigMetric(
            context,
            label: 'VMG to mark',
            value: msToKnots(vmg).toStringAsFixed(2),
            unit: 'kn',
            good: vmg > 0,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _metric(
                    context,
                    'Distance',
                    distance == null
                        ? '--'
                        : metersToNm(distance!).toStringAsFixed(3),
                    'NM')),
            const SizedBox(width: 8),
            Expanded(
                child: _metric(
                    context,
                    'Bearing',
                    bearing == null ? '--' : '${bearing!.toStringAsFixed(0)}°',
                    bearing == null ? '' : compass(bearing!))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _metric(context, 'SOG',
                    sim.speedKnots.toStringAsFixed(2), 'kn')),
            const SizedBox(width: 8),
            Expanded(
                child: _metric(context, 'COG',
                    '${sim.headingDeg.toStringAsFixed(0)}°',
                    compass(sim.headingDeg))),
          ]),
          const SizedBox(height: 8),
          _metric(
            context,
            'ETA at current VMG',
            etaSec == null ? '--:--' : formatEta(Duration(seconds: etaSec!)),
            '',
          ),
          const Divider(height: 32),
          Text('Heading', style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: sim.headingDeg,
            min: 0,
            max: 360,
            divisions: 360,
            label: '${sim.headingDeg.toStringAsFixed(0)}°',
            onChanged: (v) => sim.setHeading(v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${sim.headingDeg.toStringAsFixed(0)}°  ${compass(sim.headingDeg)}',
                  style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed: () => sim.setHeading(sim.headingDeg - 1),
                child: const Text('-1°'),
              ),
              TextButton(
                onPressed: () => sim.setHeading(sim.headingDeg + 1),
                child: const Text('+1°'),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final h in const [0, 45, 90, 135, 180, 225, 270, 315])
                OutlinedButton(
                  onPressed: () => sim.setHeading(h.toDouble()),
                  child: Text('$h°'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Speed (kn)', style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: sim.speedKnots,
            min: 0,
            max: 15,
            divisions: 150,
            label: sim.speedKnots.toStringAsFixed(1),
            onChanged: (v) => sim.setSpeed(v),
          ),
          const Divider(height: 32),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: currentMark > 0 ? onPrev : null,
                icon: const Icon(Icons.skip_previous),
                label: const Text('Prev'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: currentMark < markCount - 1 ? onNext : null,
                icon: const Icon(Icons.skip_next),
                label: const Text('Next mark'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.gps_fixed),
            label: Text(mark == null
                ? 'Aim at mark'
                : 'Point heading at ${mark!.name}'),
            onPressed: mark == null
                ? null
                : () => sim
                    .setHeading(bearingDegrees(sim.position, mark!.position)),
          ),
          const SizedBox(height: 12),
          Text(
            'Tip: tap the map to teleport the boat, long-press to drop a new '
            'buoy. Edit names, lat/lng, radius and order in the phone preview\'s '
            'Course tab — the map updates live.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _bigMetric(BuildContext context,
      {required String label,
      required String value,
      required String unit,
      required bool good}) {
    final color = good ? Colors.green.shade700 : Colors.red.shade700;
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 44, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(width: 8),
              Text(unit, style: TextStyle(fontSize: 18, color: color)),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value, String unit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Text(unit, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
