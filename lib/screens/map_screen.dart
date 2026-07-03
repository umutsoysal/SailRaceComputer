import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/course.dart';
import '../services/location_service.dart';
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
  late final LocationService _locationService;
  final _mapTransformController = TransformationController();

  @override
  void initState() {
    super.initState();
    _locationService = LocationService(positionSource: widget.positionSource);
    _locationService.addListener(_handleLocationChanged);
    unawaited(_locationService.start());
  }

  void _handleLocationChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _locationService.removeListener(_handleLocationChanged);
    _locationService.dispose();
    _mapTransformController.dispose();
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
    final fix = _locationService.position;
    final error = _locationService.error;
    final boat = fix != null ? LatLng(fix.latitude, fix.longitude) : null;
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) => InteractiveViewer(
              transformationController: _mapTransformController,
              boundaryMargin: const EdgeInsets.all(120),
              minScale: 0.75,
              maxScale: 8,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: CustomPaint(
                  painter: CourseMapPainter(
                    course: widget.course,
                    boat: boat,
                    heading: fix?.heading ?? 0,
                    speedMs: fix?.speed ?? 0,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (boat == null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: error == null ? _gpsChip() : _locationErrorChip(error),
            ),
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

  Widget _locationErrorChip(String error) {
    final actionLabel = isLocationServicesDisabledError(error)
        ? 'Open Location Services'
        : isLocationPermissionError(error)
            ? 'Open Settings'
            : 'Retry';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_off, color: Colors.red),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      error,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => unawaited(_locationService.start()),
                    child: const Text('Retry'),
                  ),
                  FilledButton(
                    onPressed: () => _openSettingsForError(error),
                    child: Text(actionLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettingsForError(String error) async {
    if (isLocationServicesDisabledError(error)) {
      await Geolocator.openLocationSettings();
      return;
    }
    if (isLocationPermissionError(error)) {
      await Geolocator.openAppSettings();
    }
  }
}
