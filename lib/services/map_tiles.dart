import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../utils/geo.dart';

/// Web Mercator slippy-map tiles used as the chart background behind a course.
///
/// The app's own plot is an equirectangular projection around the course
/// centre (see `CourseProjection`). Over a race course — a few kilometres at
/// most — that differs from Web Mercator by well under a pixel, so tiles can be
/// blitted straight into the same canvas without reprojecting them.

/// One slippy-map tile address.
@immutable
class TileCoord {
  const TileCoord(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is TileCoord && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => 'TileCoord($z/$x/$y)';
}

/// A raster tile service: where to fetch tiles and who to credit for them.
@immutable
class TileSource {
  const TileSource({
    required this.id,
    required this.urlTemplate,
    required this.attribution,
    required this.attributionUrl,
    this.minZoom = 2,
    this.maxZoom = 19,
  });

  final String id;

  /// Supports `{z}`, `{x}`, `{y}` and `{r}` (the `@2x` retina suffix).
  final String urlTemplate;
  final String attribution;
  final String attributionUrl;
  final int minZoom;
  final int maxZoom;

  String urlFor(TileCoord coord, {bool retina = false}) => urlTemplate
      .replaceAll('{z}', '${coord.z}')
      .replaceAll('{x}', '${coord.x}')
      .replaceAll('{y}', '${coord.y}')
      .replaceAll('{r}', retina ? '@2x' : '');

  /// CARTO Positron: a pale basemap that shows the shoreline and street grid
  /// without competing with the course overlay drawn on top of it.
  static const cartoLight = TileSource(
    id: 'carto-positron',
    urlTemplate: 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    attribution: '© OpenStreetMap contributors, © CARTO',
    attributionUrl: 'https://www.openstreetmap.org/copyright',
    maxZoom: 20,
  );
}

/// Ground resolution of a tile pyramid level, in metres per pixel, at
/// [latitude]. Assumes 256 px tiles.
double tileResolutionMeters(int zoom, double latitude) =>
    156543.03392804097 *
    math.cos(latitude * math.pi / 180.0) /
    math.pow(2, zoom);

/// Picks the pyramid level whose ground resolution is closest to
/// [metersPerPixel] at [latitude], clamped to what [source] serves.
int chooseTileZoom({
  required double metersPerPixel,
  required double latitude,
  TileSource source = TileSource.cartoLight,
}) {
  if (metersPerPixel <= 0 || !metersPerPixel.isFinite) return source.maxZoom;
  final atEquator = 156543.03392804097 * math.cos(latitude * math.pi / 180.0);
  final exact = math.log(atEquator / metersPerPixel) / math.ln2;
  if (!exact.isFinite) return source.minZoom;
  return exact.round().clamp(source.minZoom, source.maxZoom);
}

/// Fractional tile column for [lng] at [zoom].
double tileXForLng(double lng, int zoom) =>
    (lng + 180.0) / 360.0 * math.pow(2, zoom);

/// Fractional tile row for [lat] at [zoom].
double tileYForLat(double lat, int zoom) {
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final rad = clamped * math.pi / 180.0;
  final y = (1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2;
  return y * math.pow(2, zoom);
}

/// Longitude of the west edge of tile column [x] at [zoom].
double lngForTileX(double x, int zoom) => x / math.pow(2, zoom) * 360.0 - 180.0;

/// Latitude of the north edge of tile row [y] at [zoom].
double latForTileY(double y, int zoom) {
  final n = math.pi * (1 - 2 * y / math.pow(2, zoom));
  return 180.0 / math.pi * math.atan(_sinh(n));
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

/// Geographic bounds of a tile, north-west and south-east corners.
({LatLng northWest, LatLng southEast}) tileBounds(TileCoord coord) => (
  northWest: LatLng(
    latForTileY(coord.y.toDouble(), coord.z),
    lngForTileX(coord.x.toDouble(), coord.z),
  ),
  southEast: LatLng(
    latForTileY(coord.y + 1.0, coord.z),
    lngForTileX(coord.x + 1.0, coord.z),
  ),
);

/// Every tile at [zoom] covering the given bounds, row-major from the
/// north-west corner. Returns an empty list when the bounds are inverted.
List<TileCoord> tilesForBounds({
  required LatLng northWest,
  required LatLng southEast,
  required int zoom,
}) {
  if (southEast.lat > northWest.lat || southEast.lng < northWest.lng) {
    return const <TileCoord>[];
  }
  final span = math.pow(2, zoom).toInt();
  final minX = tileXForLng(northWest.lng, zoom).floor().clamp(0, span - 1);
  final maxX = tileXForLng(southEast.lng, zoom).floor().clamp(0, span - 1);
  final minY = tileYForLat(northWest.lat, zoom).floor().clamp(0, span - 1);
  final maxY = tileYForLat(southEast.lat, zoom).floor().clamp(0, span - 1);

  return <TileCoord>[
    for (var y = minY; y <= maxY; y++)
      for (var x = minX; x <= maxX; x++) TileCoord(zoom, x, y),
  ];
}

/// Read-only view of a tile cache, so painters can ask for tiles without
/// knowing how they are fetched (and tests can hand over canned images).
abstract class TileImageSource implements Listenable {
  /// The decoded tile, or null when it is missing — callers draw what they
  /// have and repaint when the source notifies that more arrived.
  ui.Image? imageFor(TileCoord coord);

  /// Asks for tiles that [imageFor] did not have. Safe to call every frame.
  void request(Iterable<TileCoord> coords);

  TileSource get source;
}

/// Fetches and caches basemap tiles.
///
/// Decoding rides on Flutter's own [NetworkImage] pipeline, so tiles get HTTP
/// caching and in-memory reuse for free. Failures are remembered rather than
/// retried on every frame: with no network the map simply keeps the plain
/// chart background it has always had.
class MapTileLoader extends ChangeNotifier implements TileImageSource {
  MapTileLoader({
    this.source = TileSource.cartoLight,
    this.retina = false,
    this.maxCachedTiles = 128,
  });

  @override
  final TileSource source;

  /// Requests `@2x` tiles, which stay sharp on high-density screens.
  final bool retina;

  final int maxCachedTiles;

  // Insertion-ordered, so the first key is the least recently used tile.
  final _images = <TileCoord, ui.Image>{};
  final _pending = <TileCoord>{};
  final _failed = <TileCoord>{};
  bool _disposed = false;

  /// Tiles that failed to load and will not be retried this session.
  @visibleForTesting
  int get failureCount => _failed.length;

  @override
  ui.Image? imageFor(TileCoord coord) {
    final image = _images.remove(coord);
    if (image == null) return null;
    _images[coord] = image; // most recently used goes to the back
    return image;
  }

  @override
  void request(Iterable<TileCoord> coords) {
    for (final coord in coords) {
      if (_disposed) return;
      if (_images.containsKey(coord) ||
          _pending.contains(coord) ||
          _failed.contains(coord)) {
        continue;
      }
      _pending.add(coord);
      unawaited(_fetch(coord));
    }
  }

  Future<void> _fetch(TileCoord coord) async {
    try {
      final image = await _decode(source.urlFor(coord, retina: retina));
      if (_disposed) {
        image.dispose();
        return;
      }
      _pending.remove(coord);
      _images[coord] = image;
      _evictOverflow();
      notifyListeners();
    } catch (error) {
      if (_disposed) return;
      _pending.remove(coord);
      _failed.add(coord);
    }
  }

  void _evictOverflow() {
    while (_images.length > maxCachedTiles) {
      final oldest = _images.keys.first;
      _images.remove(oldest)?.dispose();
    }
  }

  Future<ui.Image> _decode(String url) {
    final completer = Completer<ui.Image>();
    // Headers on web force the XHR path for no benefit, and the tile CDN is
    // reached with the page's own origin there anyway.
    final provider = kIsWeb
        ? NetworkImage(url)
        : NetworkImage(url, headers: const {'User-Agent': tileUserAgent});
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        // Clone before releasing the ImageInfo: the cache may drop the
        // original at any time, and this handle outlives it.
        final image = info.image.clone();
        info.dispose();
        if (!completer.isCompleted) completer.complete(image);
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}

/// Identifies the app to tile servers, as their usage policies ask.
const String tileUserAgent =
    'RaceMate/1.0 (+https://github.com/umutsoysal/SailRaceComputer)';
