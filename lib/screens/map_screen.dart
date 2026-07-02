import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/course.dart';
import '../services/position_source.dart';
import '../utils/geo.dart';
import '../widgets/course_map_painter.dart';

/// Displays the racecourse as a top-down map with the boat's live GPS
/// position overlaid when available.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.course,
    this.positionSource,
  });

  final Course course;

  /// Optional override — the dev simulator passes a [SimulatedPositionSource]
  /// here so the same screen works on the desk. In production this is null and
  /// the screen creates its own [GeolocatorPositionSource].
  final PositionSource? positionSource;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final PositionSource _source;
  late final bool _ownsSource;
  StreamSubscription<Position>? _sub;
  Position? _pos;

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
    _start();
  }

  Future<void> _start() async {
    final err = await _source.ensureReady();
    if (!mounted) return;
    if (err != null) return; // no GPS — show static course
    _sub = _source.stream.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_ownsSource) _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: widget.course.buoys.isEmpty
          ? const Center(child: Text('Add buoys on the Course tab first.'))
          : _buildMap(),
    );
  }

  Widget _buildMap() {
    final fix = _pos;
    final boat = fix != null ? LatLng(fix.latitude, fix.longitude) : null;
    return Stack(
      children: [
        SizedBox.expand(
          child: CustomPaint(
            painter: CourseMapPainter(
              course: widget.course,
              boat: boat,
              heading: fix?.heading ?? 0,
              speedMs: fix?.speed ?? 0,
            ),
          ),
        ),
        if (boat == null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(child: _gpsChip()),
          ),
      ],
    );
  }

  Widget _gpsChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_off, size: 14, color: Colors.white),
          SizedBox(width: 6),
          Text(
            'Waiting for GPS',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
