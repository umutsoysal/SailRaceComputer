import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/course.dart';
import '../services/basemap_store.dart';
import '../services/location_service.dart';
import '../services/map_tiles.dart';
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
    this.tileSource,
  });

  final Course course;

  /// Optional override — the dev simulator passes a [SimulatedPositionSource]
  /// here so the same screen works on the desk. In production this is null and
  /// the screen creates its own [GeolocatorPositionSource].
  final PositionSource? positionSource;

  /// Optional override for the basemap tiles. Null means the screen owns a
  /// [MapTileLoader] of its own; an injected source is not disposed here.
  final TileImageSource? tileSource;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final LocationService _locationService;
  final _mapTransformController = TransformationController();
  final _basemapStore = BasemapStore();

  MapTileLoader? _ownedTiles;
  bool _basemapEnabled = true;

  TileImageSource? get _tiles => widget.tileSource ?? _ownedTiles;

  @override
  void initState() {
    super.initState();
    _locationService = LocationService(positionSource: widget.positionSource);
    _locationService.addListener(_handleLocationChanged);
    _mapTransformController.addListener(_handleTransformChanged);
    unawaited(_locationService.start());
    unawaited(_loadBasemapPreference());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.tileSource != null || _ownedTiles != null) return;
    // Retina tiles are only worth the bytes on a dense screen.
    _ownedTiles = MapTileLoader(
      retina: MediaQuery.devicePixelRatioOf(context) >= 2,
    );
  }

  Future<void> _loadBasemapPreference() async {
    final enabled = await _basemapStore.load();
    if (!mounted || enabled == _basemapEnabled) return;
    setState(() => _basemapEnabled = enabled);
  }

  void _toggleBasemap() {
    setState(() => _basemapEnabled = !_basemapEnabled);
    unawaited(_basemapStore.save(enabled: _basemapEnabled));
  }

  void _handleLocationChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Panning and zooming change which tiles are on screen, so the basemap has
  /// to be recomputed as the view moves.
  void _handleTransformChanged() {
    if (!mounted || _tiles == null || !_basemapEnabled) return;
    setState(() {});
  }

  @override
  void dispose() {
    _locationService.removeListener(_handleLocationChanged);
    _locationService.dispose();
    _mapTransformController.removeListener(_handleTransformChanged);
    _mapTransformController.dispose();
    _ownedTiles?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Map',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              widget.course.name,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('map-basemap-toggle'),
            tooltip: _basemapEnabled
                ? 'Hide map background'
                : 'Show map background',
            onPressed: _toggleBasemap,
            icon: Icon(
              _basemapEnabled ? Icons.layers : Icons.layers_clear_outlined,
            ),
          ),
        ],
      ),
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
              boundaryMargin: const EdgeInsets.all(360),
              // Pulling well back is how you find the shoreline relative to a
              // course laid out in open water — but only the basemap keeps
              // drawing out there, so the plain chart stays tied to its plot.
              minScale: _basemapEnabled ? 0.25 : 0.75,
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
                    paddingPx: 120,
                    basemap: _basemapFor(constraints),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_basemapEnabled && _tiles != null)
          Positioned(left: 12, bottom: 12, child: _attributionChip(_tiles!)),
        if (boat == null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: error == null ? _gpsChip() : _locationErrorChip(error),
            ),
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Tooltip(
            message: 'Center course and boat',
            child: FilledButton.tonalIcon(
              key: const Key('map-fit-button'),
              onPressed: _resetMapView,
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('Center'),
            ),
          ),
        ),
      ],
    );
  }

  void _resetMapView() {
    _mapTransformController.value = Matrix4.identity();
  }

  /// Describes the visible slice of the canvas so the painter only fetches the
  /// tiles the sailor can actually see at the current pan and zoom.
  Basemap? _basemapFor(BoxConstraints constraints) {
    final tiles = _tiles;
    if (!_basemapEnabled || tiles == null) return null;
    final canvas = Offset.zero & constraints.biggest;
    return Basemap(
      tiles: tiles,
      viewScale: _mapTransformController.value.getMaxScaleOnAxis(),
      viewport: MatrixUtils.inverseTransformRect(
        _mapTransformController.value,
        canvas,
      ),
    );
  }

  Widget _attributionChip(TileImageSource tiles) {
    final source = tiles.source;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        onTap: () => unawaited(
          launchUrl(
            Uri.parse(source.attributionUrl),
            mode: LaunchMode.externalApplication,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            source.attribution,
            style: const TextStyle(fontSize: 10, color: Colors.black87),
          ),
        ),
      ),
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
